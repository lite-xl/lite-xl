#ifndef API_H
#define API_H

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#define API_TYPE_FONT "Font"
#define API_TYPE_REPLACE "Replace"
#define API_TYPE_PROCESS "Process"

void api_load_libs(lua_State *L);

#ifdef _WIN32
#include <windows.h>
int api_windows_dark_theme_activated();
#endif

#endif
