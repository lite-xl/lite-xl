#include "api.h"

#define PCRE2_CODE_UNIT_WIDTH 8

#include <string.h>
#include <pcre2.h>

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
  const char* str = luaL_checklstring(L, -1, &len);
  pcre2_code* re = pcre2_compile((PCRE2_SPTR)str, len, 0, &errorNumber, &errorOffset, NULL);
  if (re) {
    lua_newtable(L);
    lua_pushlightuserdata(L, re);
    lua_rawseti(L, -2, 1);
    lua_getfield(L, LUA_REGISTRYINDEX, "regex");
    lua_setmetatable(L, -2);
    return 1;
  }
  PCRE2_UCHAR buffer[256];
  pcre2_get_error_message(errorNumber, buffer, sizeof(buffer));
  luaL_error(L, "regex compilation failed at offset %d: %s", (int)errorOffset, buffer);
  return 0;
}

// Takes string, compiled regex, returns list of indices of matched groups (including the whole match), if a match was found.
static int f_pcre_match(lua_State *L) {
  size_t len;
  const char* str = luaL_checklstring(L, -1, &len);
  luaL_checktype(L, -2, LUA_TTABLE);
  lua_rawgeti(L, -2, 1);
  pcre2_code* re = (pcre2_code*)lua_touserdata(L, -1);
  pcre2_match_data* match_data = pcre2_match_data_create_from_pattern(re, NULL);
  int rc = pcre2_match(re, (PCRE2_SPTR)str, len, 0, 0, match_data, NULL);
  if (rc < 0) {
    pcre2_match_data_free(match_data);
    if (rc != PCRE2_ERROR_NOMATCH)
      luaL_error(L, "regex matching error %d", rc);
    return 0;
  }
  PCRE2_SIZE* ovector = pcre2_get_ovector_pointer(match_data);
  if (ovector[0] > ovector[1]) {
    /* We must guard against patterns such as /(?=.\K)/ that use \K in an assertion
    to set the start of a match later than its end. In the editor, we just detect this case and give up. */
    luaL_error(L, "regex matching error: \\K was used in an assertion to set the match start after its end"); 
    pcre2_match_data_free(match_data);
    return 0;
  }
  for (int i = 0; i < rc*2; i++)
    lua_pushnumber(L, ovector[i]+1);
  pcre2_match_data_free(match_data);
  return rc*2;
}

static const luaL_Reg lib[] = {
  { "compile",  f_pcre_compile },
  { "cmatch",   f_pcre_match },
  { "__gc",     f_pcre_gc },
  { NULL,       NULL }
};

int luaopen_regex(lua_State *L) {
  luaL_newlib(L, lib);
  lua_pushliteral(L, "regex");
  lua_setfield(L, -2, "__name");
  lua_pushvalue(L, -1);
  lua_setfield(L, LUA_REGISTRYINDEX, "regex");
  return 1;
}
