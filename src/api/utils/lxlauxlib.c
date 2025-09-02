#include "lxlauxlib.h"
#include "lauxlib.h"
#include "../api.h"
#include <math.h>

bool luaXL_checkboolean(lua_State *L, int arg) {
  if (!lua_isboolean(L, arg)) {
    return luaL_typeerror(L, arg, lua_typename(L, LUA_TBOOLEAN));
  }
  return lua_toboolean(L, arg);
}

bool luaXL_optboolean(lua_State *L, int arg, bool dflt) {
  return luaL_opt(L, luaXL_checkboolean, arg, dflt);
}


static int color_value_error(lua_State *L, int idx, int table_idx) {
  const char *type, *msg;
  // generate an appropriate error message
  if (luaL_getmetafield(L, -1, "__name") == LUA_TSTRING) {
    type = lua_tostring(L, -1); // metatable name
  } else if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
    type = "light userdata"; // special name for light userdata
  } else {
    type = lua_typename(L, lua_type(L, -1)); // default name
  }
  // the reason it went through so much hoops is to generate the correct error
  // message (with function name and proper index).
  msg = lua_pushfstring(L, "table[%d]: %s expected, got %s", table_idx, lua_typename(L, LUA_TNUMBER), type);
  return luaL_argerror(L, idx, msg);
}

static int get_color_value(lua_State *L, int idx, int table_idx) {
  int top = lua_gettop(L);
  if (idx < 0) {
    idx += top;
  }
  if (table_idx < 0) {
    idx += top;
  }

  lua_rawgeti(L, idx, table_idx);
  return lua_isnumber(L, -1) ? lua_tonumber(L, -1) : color_value_error(L, idx, table_idx);
}

static int get_color_value_opt(lua_State *L, int idx, int table_idx, int default_value) {
  int top = lua_gettop(L);
  if (idx < 0) {
    idx += top;
  }
  if (table_idx < 0) {
    idx += top;
  }

  lua_rawgeti(L, idx, table_idx);
  if (lua_isnoneornil(L, -1))
    return default_value;
  else if (lua_isnumber(L, -1))
    return lua_tonumber(L, -1);
  else
    return color_value_error(L, idx, table_idx);
}

RenColor luaXL_checkcolor(lua_State *L, int idx, int def) {
  RenColor color;
  if (lua_isnoneornil(L, idx)) {
    return (RenColor) { def, def, def, 255 };
  }
  luaL_checktype(L, idx, LUA_TTABLE);
  color.r = get_color_value(L, idx, 1);
  color.g = get_color_value(L, idx, 2);
  color.b = get_color_value(L, idx, 3);
  color.a = get_color_value_opt(L, idx, 4, 255);
  lua_pop(L, 4);
  return color;
}


bool font_retrieve(lua_State *L, RenFont **fonts, int idx) {
  bool is_table;
  memset(fonts, 0, sizeof(RenFont *) * FONT_FALLBACK_MAX);
  if (lua_type(L, idx) != LUA_TTABLE) {
    fonts[0] = *(RenFont **)luaL_checkudata(L, idx, API_TYPE_FONT);
    is_table = false;
  } else {
    is_table = true;
    int len = luaL_len(L, idx);
    len = len > FONT_FALLBACK_MAX ? FONT_FALLBACK_MAX : len;
    for (int i = 0; i < len; i++) {
      lua_rawgeti(L, idx, i + 1);
      fonts[i] = *(RenFont **)luaL_checkudata(L, -1, API_TYPE_FONT);
      lua_pop(L, 1);
    }
  }
#ifdef LITE_USE_SDL_RENDERER
  update_font_scale(ren_get_target_window(), fonts);
#endif
  return is_table;
}

RenTab luaXL_checktab(lua_State *L, int idx) {
  RenTab tab = {.offset = NAN};
  if (lua_isnoneornil(L, idx)) {
    return tab;
  }
  luaL_checktype(L, idx, LUA_TTABLE);
  if (lua_getfield(L, idx, "tab_offset") == LUA_TNIL) {
    return tab;
  }
  tab.offset = luaL_checknumber(L, -1);
  return tab;
}
