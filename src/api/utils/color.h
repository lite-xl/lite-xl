#ifndef API_UTILS_COLOR_H
#define API_UTILS_COLOR_H

#include "renderer.h"
#include <lua.h>

int get_color_value(lua_State *L, int idx, int table_idx);
int get_color_value_opt(lua_State *L, int idx, int table_idx, int default_value);
RenColor checkcolor(lua_State *L, int idx, int def);

#endif
