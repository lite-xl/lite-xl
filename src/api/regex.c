#include "api.h"

#define PCRE2_CODE_UNIT_WIDTH 8

#include <stdarg.h>
#include <string.h>
#include <pcre2.h>


// something similiar to luaL_checkudata() but for regex only
static pcre2_code* check_regex(lua_State* L, int arg) {
  luaL_checktype(L, arg, LUA_TTABLE);
  int hasmt = 0; 
  pcre2_code* re = NULL;

  if (lua_getmetatable(L, arg)) {
    luaL_getmetatable(L, API_TYPE_REGEX);
    hasmt = lua_rawequal(L, -1, -2);
    lua_pop(L, 2);
  }

  lua_rawgeti(L, arg, 1);
  re = lua_touserdata(L, -1);
  lua_pop(L, 1);

  if (!hasmt || re == NULL)
    luaL_argerror(L, arg, "invalid regex object");

  return re;
}

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
  pcre2_code* re = check_regex(L, 1);
  if (re)
    pcre2_code_free(re);
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

  lua_newtable(L);
  luaL_setmetatable(L, API_TYPE_REGEX);

  lua_pushlightuserdata(L, (void*) re);
  lua_rawseti(L, -2, 1);

  lua_pushvalue(L, 1);
  lua_setfield(L, -2, "source");

  lua_pushstring(L, optstr);
  lua_setfield(L, -2, "flags");

  return 1;
}

// get nametable (useful for named captures)
static int f_pcre_nametable(lua_State* L) {
  pcre2_code* re = check_regex(L, 1);
  int ret;
  uint32_t namecount, entrysize;
  PCRE2_SPTR nametable;

  ret = pcre2_pattern_info(re, PCRE2_INFO_NAMETABLE, &nametable);
  if (ret)
    return pcre2_error(L, ret, "cannot get PCRE2_INFO_NAMETABLE: ");

  pcre2_pattern_info(re, PCRE2_INFO_NAMECOUNT, &namecount);
  pcre2_pattern_info(re, PCRE2_INFO_NAMEENTRYSIZE, &entrysize);

  lua_createtable(L, namecount, 0);
  for (uint32_t i = 0; i < namecount; i++) {
    uint16_t index = (nametable[1] << 0) | (nametable[0] << 8);
    nametable += 2;
    
    lua_createtable(L, 0, 2);
    lua_pushnumber(L, index);
    lua_setfield(L, -2, "index");
    lua_pushstring(L, (const char *) nametable);
    lua_setfield(L, -2, "name");
    lua_rawseti(L, -2, i + 1);

    nametable += (entrysize - 2);
  }

  return 1;
}

// Takes string, compiled regex, returns list of indices of matched groups
// (including the whole match), if a match was found.
static int f_pcre_match(lua_State *L) {
  size_t len, offset, options;
  pcre2_code* re = check_regex(L, 1);
  const char* str = luaL_checklstring(L, 2, &len);

  offset = luaL_optnumber(L, 3, 1);
  options = luaL_optnumber(L, 4, 0);

  pcre2_match_data* md = pcre2_match_data_create_from_pattern(re, NULL);
  int rc = pcre2_match(re, (PCRE2_SPTR)str, len, offset - 1, options, md, NULL);
  if (rc < 0) {
    pcre2_match_data_free(md);
    if (rc != PCRE2_ERROR_NOMATCH) {
      PCRE2_UCHAR buffer[256];
      pcre2_get_error_message(rc, buffer, sizeof(buffer));
      luaL_error(L, "regex matching error: %s", buffer);
    }
    return 0;
  }

  PCRE2_SIZE* ovector = pcre2_get_ovector_pointer(md);
  if (ovector[0] > ovector[1]) {
    pcre2_match_data_free(md);
    /* We must guard against patterns such as /(?=.\K)/ that use \K in an
    assertion  to set the start of a match later than its end. In the editor,
    we just detect this case and give up. */
    luaL_error(L, "regex matching error: \\K was used in an assertion to "
    " set the match start after its end");
    return 0;
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
  { "nametable", f_pcre_nametable },
  { "compile",  f_pcre_compile },
  { "cmatch",   f_pcre_match },
  { "__gc",     f_pcre_gc },
  { NULL,       NULL }
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
