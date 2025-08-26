#include "lauxlib.h"
#include "colors.h"
#include "lua.h"

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

int get_color_value(lua_State *L, int idx, int table_idx) {
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

int get_color_value_opt(lua_State *L, int idx, int table_idx, int default_value) {
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

RenColor checkcolor(lua_State *L, int idx, int def) {
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
