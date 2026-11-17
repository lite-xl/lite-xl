#include "api.h"

#define PCRE2_CODE_UNIT_WIDTH 8

#include <SDL3/SDL.h>
#include <string.h>
#include <pcre2.h>
#include <stdbool.h>

/* Bound the work a single match is allowed to do. The PCRE2 defaults
   (10M each) let a pathological pattern lock the UI for seconds or grow the
   heap frame vector without bound; these caps turn that into a clean
   "no match" while staying far above anything a real syntax pattern needs. */
#define REGEX_MATCH_LIMIT 5000000u
#define REGEX_DEPTH_LIMIT 10000u

/* Process-lifetime, single-threaded: lite-xl only ever matches from the main
   thread. Created in luaopen_regex(); a NULL context is valid (PCRE2 falls
   back to its defaults) so callers don't need to check it. */
static pcre2_match_context *g_match_context = NULL;

/* Resource-limit failures are recoverable: treat them as "no match" instead
   of raising, so one bad pattern can't abort a whole tokenize pass. */
static bool regex_is_limit_error(int rc) {
  return rc == PCRE2_ERROR_MATCHLIMIT
      || rc == PCRE2_ERROR_DEPTHLIMIT
      || rc == PCRE2_ERROR_HEAPLIMIT;
}

typedef struct RegexState {
  pcre2_code* re;
  pcre2_match_data* match_data;
  const char* subject;
  size_t subject_len;
  size_t offset;
  bool regex_compiled;
  bool found;
} RegexState;

static pcre2_code* regex_get_pattern(lua_State *L, bool* should_free) {
  pcre2_code* re = NULL;
  *should_free = false;

  if (lua_type(L, 1) == LUA_TTABLE) {
    lua_rawgeti(L, 1, 1);
    re = (pcre2_code*)lua_touserdata(L, -1);
    lua_settop(L, -2);
  } else {
    int errornumber;
    PCRE2_SIZE erroroffset;
    size_t pattern_len = 0;
    const char* pattern = luaL_checklstring(L, 1, &pattern_len);

    re = pcre2_compile(
      (PCRE2_SPTR)pattern,
      pattern_len, PCRE2_UTF,
      &errornumber, &erroroffset, NULL
    );

    if (re == NULL) {
      PCRE2_UCHAR errmsg[256];
      pcre2_get_error_message(errornumber, errmsg, sizeof(errmsg));
      luaL_error(
        L, "regex pattern error at offset %d: %s",
        (int)erroroffset, errmsg
      );
      return NULL;
    }

    pcre2_jit_compile(re, PCRE2_JIT_COMPLETE);

    *should_free = true;
  }

  return re;
}

static int regex_gmatch_iterator(lua_State *L) {
  RegexState *state = (RegexState*)lua_touserdata(L, lua_upvalueindex(3));

  if (!state->found)
    return 0;

  int rc = pcre2_match(
    state->re,
    (PCRE2_SPTR)state->subject, state->subject_len,
    state->offset, 0, state->match_data, g_match_context
  );

  if (rc < 0) {
    if (rc != PCRE2_ERROR_NOMATCH && !regex_is_limit_error(rc)) {
      PCRE2_UCHAR buffer[120];
      pcre2_get_error_message(rc, buffer, sizeof(buffer));
      luaL_error(L, "regex matching error %d: %s", rc, buffer);
    }
    state->found = false;
    return 0;
  }

  size_t ovector_count = pcre2_get_ovector_count(state->match_data);
  if (ovector_count == 0) {
    state->found = false;
    return 0;
  }

  PCRE2_SIZE* ovector = pcre2_get_ovector_pointer(state->match_data);
  if (ovector[0] > ovector[1]) {
    /* We must guard against patterns such as /(?=.\K)/ that use \K in an
    assertion  to set the start of a match later than its end. In the editor,
    we just detect this case and give up. */
    state->found = false;
    return luaL_error(L, "regex matching error: \\K was used in an assertion to "
    " set the match start after its end");
  }

  int index = 0;
  if (ovector_count > 1) index = 2;

  int total = 0;
  int total_results = (int)ovector_count * 2;
  size_t last_offset = 0;

  /* One integer or string is pushed per group; a many-group pattern can blow
     past Lua's minimum stack of LUA_MINSTACK slots without this. */
  if (!lua_checkstack(L, (total_results - index) / 2 + 1)) {
    state->found = false;
    return luaL_error(L, "regex has too many captures");
  }

  for (int i = index; i < total_results; i+=2) {
    if (ovector[i] == ovector[i+1])
      lua_pushinteger(L, ovector[i] + 1);
    else
      lua_pushlstring(L, state->subject+ovector[i], ovector[i+1] - ovector[i]);
    last_offset = ovector[i+1];
    total++;
  }

  if (last_offset - 1 < state->subject_len)
    state->offset = last_offset;
  else
    state->found = false;

  return total;
}

/* __gc for the iterator state. Owns match_data unconditionally, and the
   compiled pattern when gmatch compiled it from a string. Running here (not
   at the end of iteration) means an abandoned `for m in regex.gmatch(...)`
   loop no longer leaks. */
static int f_regex_state_gc(lua_State *L) {
  RegexState *state = (RegexState*)lua_touserdata(L, 1);
  if (state->match_data) {
    pcre2_match_data_free(state->match_data);
    state->match_data = NULL;
  }
  if (state->regex_compiled && state->re) {
    pcre2_code_free(state->re);
    state->re = NULL;
  }
  return 0;
}

static size_t regex_offset_relative(lua_Integer pos, size_t len) {
  size_t out;
  if (pos > 0)
    out = (size_t)pos;
  else if (pos == 0)
    out = 1;
  else if (pos < -(lua_Integer)len)  /* inverted comparison */
    out = 1;  /* clip to 1 */
  else
    out = len + (size_t)pos + 1;
  /* Clamp the upper end too: without this, `offset -= 1; len -= offset` in the
     match functions underflows size_t and PCRE2 reads far out of bounds. */
  if (out > len + 1)
    out = len + 1;
  return out;
}

static int f_pcre_gc(lua_State* L) {
  lua_rawgeti(L, -1, 1);
  pcre2_code* re = (pcre2_code*)lua_touserdata(L, -1);
  if (re)
    pcre2_code_free(re);
  return 0;
}

static int f_pcre_compile(lua_State *L) {
  size_t len;
  PCRE2_SIZE errorOffset;
  int errorNumber;
  int pattern = PCRE2_UTF;
  const char* str = luaL_checklstring(L, 1, &len);
  if (lua_gettop(L) > 1) {
    const char* options = luaL_checkstring(L, 2);
    if (strstr(options,"i"))
      pattern |= PCRE2_CASELESS;
    if (strstr(options,"m"))
      pattern |= PCRE2_MULTILINE;
    if (strstr(options,"s"))
      pattern |= PCRE2_DOTALL;
  }
  pcre2_code* re = pcre2_compile(
    (PCRE2_SPTR)str,
    len,
    pattern,
    &errorNumber,
    &errorOffset,
    NULL
  );
  if (re) {
    pcre2_jit_compile(re, PCRE2_JIT_COMPLETE);
    lua_newtable(L);
    lua_pushlightuserdata(L, re);
    lua_rawseti(L, -2, 1);
    luaL_setmetatable(L, "regex");
    return 1;
  }
  PCRE2_UCHAR buffer[256];
  pcre2_get_error_message(errorNumber, buffer, sizeof(buffer));
  lua_pushnil(L);
  char message[1024];
  len = snprintf(message, sizeof(message), "regex compilation failed at offset %d: %s", (int)errorOffset, buffer);
  lua_pushlstring(L, message, len);
  return 2;
}

// Takes string, compiled regex, returns list of indices of matched groups
// (including the whole match), if a match was found.
static int f_pcre_match(lua_State *L) {
  size_t len, offset = 1, opts = 0;
  bool regex_compiled = false;
  pcre2_code* re = regex_get_pattern(L, &regex_compiled);
  if (!re) return 0 ;
  const char* str = luaL_checklstring(L, 2, &len);
  if (lua_gettop(L) > 2)
    offset = regex_offset_relative(luaL_checknumber(L, 3), len);
  offset -= 1;
  len -= offset;
  if (lua_gettop(L) > 3)
    opts = luaL_checknumber(L, 4);
  pcre2_match_data* md = pcre2_match_data_create_from_pattern(re, NULL);
  int rc = pcre2_match(re, (PCRE2_SPTR)&str[offset], len, 0, opts, md, g_match_context);
  if (rc < 0) {
    bool limit = regex_is_limit_error(rc);
    if (regex_compiled) pcre2_code_free(re);
    pcre2_match_data_free(md);
    if (rc != PCRE2_ERROR_NOMATCH && !limit) {
      PCRE2_UCHAR buffer[120];
      pcre2_get_error_message(rc, buffer, sizeof(buffer));
      luaL_error(L, "regex matching error %d: %s", rc, buffer);
    }
    return 0;
  }
  PCRE2_SIZE* ovector = pcre2_get_ovector_pointer(md);
  if (ovector[0] > ovector[1]) {
    /* We must guard against patterns such as /(?=.\K)/ that use \K in an
    assertion  to set the start of a match later than its end. In the editor,
    we just detect this case and give up. */
    if (regex_compiled) pcre2_code_free(re);
    pcre2_match_data_free(md);
    return luaL_error(L, "regex matching error: \\K was used in an assertion to "
    " set the match start after its end");
  }
  /* rc pairs of offsets get pushed; guard the Lua stack for many-group
     patterns before touching it. */
  if (!lua_checkstack(L, rc * 2)) {
    if (regex_compiled) pcre2_code_free(re);
    pcre2_match_data_free(md);
    return luaL_error(L, "regex has too many captures");
  }
  for (int i = 0; i < rc*2; i++)
    lua_pushinteger(L, ovector[i]+offset+1);
  if (regex_compiled) pcre2_code_free(re);
  pcre2_match_data_free(md);
  return rc*2;
}

static int f_pcre_gmatch(lua_State *L) {
  /* pattern param */
  bool regex_compiled = false;
  pcre2_code* re = regex_get_pattern(L, &regex_compiled);
  if (!re) return 0;
  size_t subject_len = 0;

  /* subject param */
  const char* subject = luaL_checklstring(L, 2, &subject_len);

  /* offset param */
  size_t offset = regex_offset_relative(
    luaL_optnumber(L, 3, 1), subject_len
  ) - 1;

  /* keep strings on closure to avoid being collected */
  lua_settop(L, 2);

  RegexState *state;
  state = (RegexState*)lua_newuserdata(L, sizeof(RegexState));
  state->re = re;
  state->match_data = NULL;
  state->subject = subject;
  state->subject_len = subject_len;
  state->offset = offset;
  state->found = true;
  state->regex_compiled = regex_compiled;
  /* set the metatable before the next allocation so that if it throws, the
     already-created state (and its owned pattern) is still freed by __gc */
  luaL_setmetatable(L, "regex_state");

  state->match_data = pcre2_match_data_create_from_pattern(re, NULL);
  if (!state->match_data)
    return luaL_error(L, "regex gmatch: out of memory");

  lua_pushcclosure(L, regex_gmatch_iterator, 3);
  return 1;
}

static int f_pcre_gsub(lua_State *L) {
  size_t subject_len = 0, replacement_len = 0;

  bool regex_compiled = false;
  pcre2_code* re = regex_get_pattern(L, &regex_compiled);
  if (!re) return 0 ;

  char* subject = (char*) luaL_checklstring(L, 2, &subject_len);
  const char* replacement = luaL_checklstring(L, 3, &replacement_len);
  int limit = luaL_optinteger(L, 4, 0);
  if (limit < 0 ) limit = 0;

  pcre2_match_data* match_data = pcre2_match_data_create_from_pattern(re, NULL);

  size_t buffer_size = 1024;
  char *output = (char *)SDL_malloc(buffer_size);
  bool oom = output == NULL;

  int options = PCRE2_SUBSTITUTE_OVERFLOW_LENGTH | PCRE2_SUBSTITUTE_EXTENDED;
  if (limit == 0) options |= PCRE2_SUBSTITUTE_GLOBAL;

  int results_count = 0;
  int limit_count = 0;
  bool done = oom;
  size_t offset = 0;
  PCRE2_SIZE outlen = buffer_size;
  while (!done) {
    results_count = pcre2_substitute(
      re,
      (PCRE2_SPTR)subject, subject_len,
      offset, options,
      match_data, g_match_context,
      (PCRE2_SPTR)replacement, replacement_len,
      (PCRE2_UCHAR*)output, &outlen
    );

    if (results_count != PCRE2_ERROR_NOMEMORY || buffer_size >= outlen) {
      /* PCRE2_SUBSTITUTE_GLOBAL code path (fastest) */
      if(limit == 0) {
        done = true;
      /* non PCRE2_SUBSTITUTE_GLOBAL with limit code path (slower) */
      } else {
        size_t ovector_count = pcre2_get_ovector_count(match_data);
        if (results_count > 0 && ovector_count > 0) {
          limit_count++;
          PCRE2_SIZE* ovector = pcre2_get_ovector_pointer(match_data);
          if (outlen > subject_len) {
            offset = ovector[1] + (outlen - subject_len);
          } else {
            offset = ovector[1] - (subject_len - outlen);
          }
          if (limit_count > 1) SDL_free(subject);
          if (limit_count == limit || offset-1 == outlen) {
            done = true;
            results_count = limit_count;
          } else {
            subject = output;
            subject_len = outlen;
            output = (char *)SDL_malloc(buffer_size);
            if (!output) { oom = true; done = true; }
            outlen = buffer_size;
          }
        } else {
          if (limit_count > 1) {
            SDL_free(subject);
          }
          done = true;
          results_count = limit_count;
        }
      }
    } else {
      /* Grow through SDL_realloc, not realloc(): `output` came from SDL_malloc
         and is later handed to SDL_free -- mixing allocators is UB when SDL is
         built with a custom allocator. */
      buffer_size = outlen;
      char *grown = (char *)SDL_realloc(output, buffer_size);
      if (!grown) { oom = true; done = true; }
      else output = grown;
    }
  }

  int return_count = 0;

  if (!oom && results_count > 0) {
    lua_pushlstring(L, (const char*) output, outlen);
    lua_pushinteger(L, results_count);
    return_count = 2;
  } else if (!oom && results_count == 0) {
    lua_pushlstring(L, subject, subject_len);
    lua_pushinteger(L, 0);
    return_count = 2;
  }

  SDL_free(output);
  pcre2_match_data_free(match_data);
  if (regex_compiled)
    pcre2_code_free(re);

  if (oom)
    return luaL_error(L, "regex substitute: out of memory");

  if (results_count < 0) {
    PCRE2_UCHAR errmsg[256];
    pcre2_get_error_message(results_count, errmsg, sizeof(errmsg));
    return luaL_error(L, "regex substitute error: %s", errmsg);
  }

  return return_count;
}

static const luaL_Reg lib[] = {
  { "compile",  f_pcre_compile },
  { "cmatch",   f_pcre_match },
  { "gmatch",   f_pcre_gmatch },
  { "gsub",     f_pcre_gsub },
  { "__gc",     f_pcre_gc },
  { NULL,       NULL }
};

int luaopen_regex(lua_State *L) {
  if (!g_match_context) {
    g_match_context = pcre2_match_context_create(NULL);
    if (g_match_context) {
      pcre2_set_match_limit(g_match_context, REGEX_MATCH_LIMIT);
      pcre2_set_depth_limit(g_match_context, REGEX_DEPTH_LIMIT);
    }
  }

  /* metatable for the gmatch iterator state */
  luaL_newmetatable(L, "regex_state");
  lua_pushcfunction(L, f_regex_state_gc);
  lua_setfield(L, -2, "__gc");
  lua_pop(L, 1);

  luaL_newlib(L, lib);
  lua_pushliteral(L, "regex");
  lua_setfield(L, -2, "__name");
  lua_pushvalue(L, -1);
  lua_setfield(L, LUA_REGISTRYINDEX, "regex");
  lua_pushinteger(L, PCRE2_ANCHORED);
  lua_setfield(L, -2, "ANCHORED");
  lua_pushinteger(L, PCRE2_ENDANCHORED);
  lua_setfield(L, -2, "ENDANCHORED");
  lua_pushinteger(L, PCRE2_NOTBOL);
  lua_setfield(L, -2, "NOTBOL");
  lua_pushinteger(L, PCRE2_NOTEOL);
  lua_setfield(L, -2, "NOTEOL");
  lua_pushinteger(L, PCRE2_NOTEMPTY);
  lua_setfield(L, -2, "NOTEMPTY");
  lua_pushinteger(L, PCRE2_NOTEMPTY_ATSTART);
  lua_setfield(L, -2, "NOTEMPTY_ATSTART");
  return 1;
}
