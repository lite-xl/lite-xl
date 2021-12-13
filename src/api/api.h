#ifndef API_H
#define API_H

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#define API_TYPE_FONT "Font"
#define API_TYPE_PROCESS "Process"

#define API_CONSTANT_DEFINE(L, idx, key, n) (lua_pushnumber(L, n), lua_setfield(L, idx - 1, key))

void api_load_libs(lua_State *L);

#ifdef _WIN32
  #define WINDOWS_DARK_MODE_BEFORE_20H1 19
  #define WINDOWS_DARK_MODE 20
  #include <windows.h>
  int api_windows_dark_theme_activated();
#endif

#endif
