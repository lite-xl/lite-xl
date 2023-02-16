#include "../api.h"
#include "../../utfconv.h"

#include <stdio.h>
#include <wchar.h>

#define OS_PREFIX "__patch_os__"

static int utf8_os_execute(lua_State *L) {
  int stat;
  const char *cmd = luaL_optstring(L, 1, NULL);
  wchar_t *cmd_w = utfconv_utf8towc(cmd);

  if (cmd && !cmd_w)
    return luaL_error(L, "%s", UTFCONV_ERROR_INVALID_CONVERSION);

  errno = 0;
  stat = _wsystem(cmd_w);
  free(cmd_w);
  if (cmd != NULL) {
    return luaL_execresult(L, stat);
  } else {
    lua_pushboolean(L, stat); // true if there is a shell
    return 1;
  }
}

static int utf8_os_remove(lua_State *L) {
  int stat;
  const char *filename = luaL_checkstring(L, 1);
  wchar_t *filename_w = utfconv_utf8towc(filename);

  if (!filename_w)
    return luaL_error(L, "%s", UTFCONV_ERROR_INVALID_CONVERSION);

  stat = _wremove(filename_w);
  free(filename_w);
  return luaL_fileresult(L, stat == 0, filename);
}

static int utf8_os_rename(lua_State *L) {
  int stat;
  const char *fromname = luaL_checkstring(L, 1);
  const char *toname = luaL_checkstring(L, 2);

  wchar_t *fromname_w = utfconv_utf8towc(fromname);
  wchar_t *toname_w = utfconv_utf8towc(toname);

  if (!fromname_w || !toname_w) {
    free(fromname_w);
    free(toname_w);
    return luaL_error(L, "%s", UTFCONV_ERROR_INVALID_CONVERSION);
  }

  stat = _wrename(fromname_w, toname_w);
  free(fromname_w);
  free(toname_w);
  return luaL_fileresult(L, stat == 0, NULL);
}

static int utf8_os_getenv(lua_State *L) {
  const char *env = luaL_checkstring(L, 1);
  wchar_t *env_w = utfconv_utf8towc(env);
  wchar_t *env_value_w;

  if (!env_w)
    return luaL_error(L, "%s", UTFCONV_ERROR_INVALID_CONVERSION);

  env_value_w = _wgetenv(env_w);
  free(env_w);
  if (env_value_w) {
    // convert back to utf8
    // NOTE:might cause issues if someone specified binary env (shouldn't be possible on Windows)
    char *env_value = utfconv_wctoutf8(env_value_w);
    if (!env_value)
      return luaL_error(L, "%s", UTFCONV_ERROR_INVALID_CONVERSION);
    lua_pushstring(L, env_value);
    free(env_value);
  } else {
    lua_pushnil(L);
  }
  return 1;
}

static const luaL_Reg utf8_oslib[] = {
  { "execute", utf8_os_execute },
  { "remove", utf8_os_remove },
  { "rename", utf8_os_rename },
  { "getenv", utf8_os_getenv },
  { NULL, NULL }
};

static int utf8_os_enable(lua_State *L) {
#if (LUA_VERSION_NUM < 503)
#error "This extension will not work with Lua below version 5.3 or LuaJIT."
#endif

  // here we (attempt to) dynamically detect the version of lua.
  if (lua_version(L) < 503)
    return luaL_error(L, "unsupported runtime Lua version");

  // check if we've patched the os library
  if (lua_getfield(L, LUA_REGISTRYINDEX, OS_PREFIX "patched") != LUA_TNIL) {
    lua_pushboolean(L, 0);
    return 1;
  }

  // set patched
  lua_pushboolean(L, 1);
  lua_setfield(L, LUA_REGISTRYINDEX, OS_PREFIX "patched");

  // patch the functions
  lua_getglobal(L, "os");
  for (int i = 0; utf8_oslib[i].name; i++) {
    lua_getfield(L, -1, utf8_oslib[i].name);

    // save the old IO functions
    lua_pushfstring(L, "%s%s", OS_PREFIX, utf8_oslib[i].name);
    lua_pushvalue(L, -2);
    lua_settable(L, LUA_REGISTRYINDEX);
    lua_pop(L, 1);

    // save the new value
    lua_pushstring(L, utf8_oslib[i].name);
    lua_pushcfunction(L, utf8_oslib[i].func);
    lua_settable(L, -3);
  }

  lua_pushboolean(L, 1);
  return 1;
}

static int utf8_os_disable(lua_State *L) {
  // check if we've patched the os library
  if (lua_getfield(L, LUA_REGISTRYINDEX, OS_PREFIX "patched") == LUA_TNIL) {
    lua_pushboolean(L, 0);
    return 1;
  }

  // unpatch all the functions
  lua_getglobal(L, "os");
  for (int i = 0; utf8_oslib[i].name; i++) {
    // restore the functions to the io table
    lua_pushstring(L, utf8_oslib[i].name);

    lua_pushfstring(L, "%s%s", OS_PREFIX, utf8_oslib[i].name);
    lua_gettable(L, LUA_REGISTRYINDEX);

    lua_settable(L, -3);
  }

  lua_pushnil(L);
  lua_setfield(L, LUA_REGISTRYINDEX, OS_PREFIX "patched");

  lua_pushboolean(L, 1);
  return 1;
}

static const luaL_Reg utf8_os_ctrl_lib[] = {
  { "enable", utf8_os_enable },
  { "disable", utf8_os_disable },
  { NULL, NULL },
};

int luaopen_utf8_os(lua_State *L) {
  luaL_newlib(L, utf8_os_ctrl_lib);
  return 1;
}
