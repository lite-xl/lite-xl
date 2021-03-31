#include "api.h"
#include "renderer.h"


static int f_new(lua_State *L) {
  CPReplaceTable *rep_table = lua_newuserdata(L, sizeof(CPReplaceTable));
  luaL_setmetatable(L, API_TYPE_REPLACE);
  ren_cp_replace_init(rep_table);
  return 1;
}


static int f_gc(lua_State *L) {
  CPReplaceTable *rep_table = luaL_checkudata(L, 1, API_TYPE_REPLACE);
  ren_cp_replace_free(rep_table);
  return 0;
}


static int f_add(lua_State *L) {
  CPReplaceTable *rep_table = luaL_checkudata(L, 1, API_TYPE_REPLACE);
  const char *src = luaL_checkstring(L, 2);
  const char *dst = luaL_checkstring(L, 3);
  ren_cp_replace_add(rep_table, src, dst);
  return 0;
}


static const luaL_Reg lib[] = {
  { "__gc",               f_gc     },
  { "new",                f_new    },
  { "add",                f_add    },
  { NULL, NULL }
};

int luaopen_renderer_replacements(lua_State *L) {
  luaL_newmetatable(L, API_TYPE_REPLACE);
  luaL_setfuncs(L, lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  return 1;
}
