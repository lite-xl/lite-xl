#ifndef API_H
#define API_H

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#define API_TYPE_FONT "Font"
#define API_TYPE_PROCESS "Process"
#define API_TYPE_DIRMONITOR "Dirmonitor"
#define API_TYPE_NATIVE_PLUGIN "NativePlugin"
#define API_TYPE_RENWINDOW "RenWindow"

#define API_CONSTANT_DEFINE(L, idx, key, n) (lua_pushnumber(L, n), lua_setfield(L, idx - 1, key))

void api_load_libs(lua_State *L);

#endif
