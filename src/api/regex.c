#include "api.h"

#define PCRE2_CODE_UNIT_WIDTH 8

#include <stdarg.h>
#include <string.h>
#include <pcre2.h>

typedef struct regex_t {
  pcre2_code *re;
  int metadata;
} regex_t;

static int pcre2_error(lua_State *L, int rc, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  lua_pushvfstring(L, fmt, ap);
  va_end(ap);

  PCRE2_UCHAR err[256];
  pcre2_get_error_message(rc, err, sizeof(err));
  lua_pushstring(L, (const char *) err);

  lua_concat(L, 2);
  lua_error(L);
  return 0;
}

static int f_pcre_gc(lua_State* L) {
  regex_t *re = luaL_checkudata(L, 1, API_TYPE_REGEX);
  luaL_unref(L, LUA_REGISTRYINDEX, re->metadata);
  if (re->re)
    pcre2_code_free(re->re);
  return 0;
}

static int f_pcre_compile(lua_State *L) {
  size_t len; 
  int options = PCRE2_UTF;
  const char* pattern = luaL_checklstring(L, 1, &len);
  const char* optstr = luaL_optstring(L, 2, "");
  if (strstr(optstr,"i"))
    options |= PCRE2_CASELESS;
  if (strstr(optstr,"m"))
    options |= PCRE2_MULTILINE;
  if (strstr(optstr,"s"))
    options |= PCRE2_DOTALL;
  
  int error;
  PCRE2_SIZE error_offset;
  pcre2_code* re = pcre2_compile(
    (PCRE2_SPTR)pattern,
    len,
    options,
    &error,
    &error_offset,
    NULL
  );

  if (re == NULL)
    return pcre2_error(L, error, "regex compilation failed at %d: ", error_offset);
    
  regex_t *regex = (regex_t*) lua_newuserdata(L, sizeof(regex_t));
  luaL_setmetatable(L, API_TYPE_REGEX);
  regex->re = re;

  lua_newtable(L);

  lua_pushvalue(L, 1);
  lua_setfield(L, -2, "source");

  lua_pushstring(L, optstr);
  lua_setfield(L, -2, "flags");
  
  regex->metadata = luaL_ref(L, LUA_REGISTRYINDEX);

  return 1;
}

static int get_nametable(lua_State *L, pcre2_code *re) {
  int ret;
  uint32_t namecount, entrysize;
  PCRE2_SPTR nametable;

  ret = pcre2_pattern_info(re, PCRE2_INFO_NAMETABLE, &nametable);
  if (ret)
    return pcre2_error(L, ret, "cannot get PCRE2_INFO_NAMETABLE: ");

  pcre2_pattern_info(re, PCRE2_INFO_NAMECOUNT, &namecount);
  pcre2_pattern_info(re, PCRE2_INFO_NAMEENTRYSIZE, &entrysize);

  lua_createtable(L, namecount, 0);
  for (uint32_t i = 1; i <= namecount; i++) {
    uint16_t index = (nametable[1] << 0) | (nametable[0] << 8);
    nametable += 2;
    
    lua_createtable(L, 0, 2);
    lua_pushnumber(L, index);
    lua_setfield(L, -2, "index");
    lua_pushstring(L, (const char *) nametable);
    lua_setfield(L, -2, "name");
    lua_rawseti(L, -2, i);

    nametable += (entrysize - 2);
  }

  return 1;
}

static int f_pcre_get_metadata(lua_State *L) {
  regex_t *re = luaL_checkudata(L, 1, API_TYPE_REGEX);
  
  lua_rawgeti(L, LUA_REGISTRYINDEX, re->metadata);
  lua_getfield(L, -1, "nametable");
  if (lua_type(L, -1) == LUA_TTABLE) {
    lua_pop(L, 1);
  } else {
    lua_pop(L, 1);
    get_nametable(L, re->re);
    lua_setfield(L, -2, "nametable");
  }
  
  return 1;
}

static size_t check_bitfield(lua_State *L, int t) {
  size_t size, bit = 0;
  luaL_checktype(L, t, LUA_TTABLE);
  size = lua_rawlen(L, t);
  for (size_t i = 1; i <= size; i++) {
    lua_rawgeti(L, t, i);
    bit |= luaL_checkinteger(L, -1);
    lua_pop(L, 1);
  }
  return bit;
}

// Takes string, compiled regex, returns list of indices of matched groups
// (including the whole match), if a match was found.
static int f_pcre_match(lua_State *L) {
  size_t len, offset, options;
  regex_t *re = luaL_checkudata(L, 1, API_TYPE_REGEX);
  const char* str = luaL_checklstring(L, 2, &len);

  offset = luaL_optnumber(L, 3, 1);
  options = lua_gettop(L) == 4 ? check_bitfield(L, 4) : 0;

  pcre2_match_data* md = pcre2_match_data_create_from_pattern(re->re, NULL);
  int rc = pcre2_match(re->re, (PCRE2_SPTR)str, len, offset - 1, options, md, NULL);
  if (rc < 0) {
    pcre2_match_data_free(md);
    if (rc != PCRE2_ERROR_NOMATCH)
      return pcre2_error(L, rc, "regex matching error: ");
    else
      return 0;
  }

  PCRE2_SIZE* ovector = pcre2_get_ovector_pointer(md);
  if (ovector[0] > ovector[1]) {
    pcre2_match_data_free(md);
    /* We must guard against patterns such as /(?=.\K)/ that use \K in an
    assertion  to set the start of a match later than its end. In the editor,
    we just detect this case and give up. */
    return luaL_error(L, "regex matching error: \\K was used in an assertion to "
                          " set the match start after its end");
  }

  rc *= 2;
  luaL_checkstack(L, rc, NULL);
  for (int i = 0; i < rc; i++)
    // for every even vector (the end of a pair), we do not increment by 1
    lua_pushnumber(L, ovector[i] + (i + 1) % 2);
  pcre2_match_data_free(md);
  return rc;
}

static const luaL_Reg lib[] = {
  { "get_metadata", f_pcre_get_metadata },
  { "compile",      f_pcre_compile },
  { "cmatch",       f_pcre_match },
  { "__gc",         f_pcre_gc },
  { NULL,           NULL }
};

int luaopen_regex(lua_State *L) {
  luaL_newmetatable(L, API_TYPE_REGEX);
  luaL_setfuncs(L, lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");

  lua_pushnumber(L, PCRE2_ANCHORED);
  lua_setfield(L, -2, "ANCHORED");
  
  lua_pushnumber(L, PCRE2_ANCHORED) ;
  lua_setfield(L, -2, "ENDANCHORED");
  
  lua_pushnumber(L, PCRE2_NOTBOL);
  lua_setfield(L, -2, "NOTBOL");
  
  lua_pushnumber(L, PCRE2_NOTEOL);
  lua_setfield(L, -2, "NOTEOL");
  
  lua_pushnumber(L, PCRE2_NOTEMPTY);
  lua_setfield(L, -2, "NOTEMPTY");
  
  lua_pushnumber(L, PCRE2_NOTEMPTY_ATSTART);
  lua_setfield(L, -2, "NOTEMPTY_ATSTART");
  
  return 1;
}
