
#include "lite_plugin_api.h"

int lua_open_sample(lua_State* L, void* (*symbol(const char*))) {
  lite_init_plugin(symbol);
  lua_createtable(L, 0, 0);
  lua_pushstring(L, "value");
  lua_setfield(L, -2, "example");
  return 1;
}
