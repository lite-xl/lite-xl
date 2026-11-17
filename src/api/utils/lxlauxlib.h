#ifndef API_UTILS_LXLAUXLIB_H
#define API_UTILS_LXLAUXLIB_H

#include "lua.h"
#include "renderer.h"
#include <stdbool.h>

bool luaXL_checkboolean(lua_State *L, int arg);
bool luaXL_optboolean(lua_State *L, int arg, bool dflt);

RenColor luaXL_checkcolor(lua_State *L, int idx, int def);

bool font_retrieve(lua_State* L, RenFont** fonts, int idx);
RenTab luaXL_checktab(lua_State *L, int idx);

#endif
