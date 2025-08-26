#ifndef API_UTILS_FONTS_H
#define API_UTILS_FONTS_H

#include "renderer.h"
#include "lua.h"

bool font_retrieve(lua_State* L, RenFont** fonts, int idx);
RenTab checktab(lua_State *L, int idx);

#endif
