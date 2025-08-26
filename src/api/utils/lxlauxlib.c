#include "lxlauxlib.h"
#include "lauxlib.h"

bool luaXL_checkboolean(lua_State *L, int arg) {
  if (!lua_isboolean(L, arg)) {
    return luaL_typeerror(L, arg, lua_typename(L, LUA_TBOOLEAN));
  }
  return lua_toboolean(L, arg);
}

bool luaXL_optboolean(lua_State *L, int arg, bool dflt) {
  return luaL_opt(L, luaXL_checkboolean, arg, dflt);
}
