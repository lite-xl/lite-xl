#ifndef API_UTILS_LXLAUXLIB_H
#define API_UTILS_LXLAUXLIB_H

#include "lua.h"
#include <stdbool.h>

bool luaXL_checkboolean(lua_State *L, int arg);
bool luaXL_optboolean(lua_State *L, int arg, bool dflt);

#endif
