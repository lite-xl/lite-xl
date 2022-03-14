#include "api.h"

int luaopen_system(lua_State *L);
int luaopen_renderer(lua_State *L);
int luaopen_regex(lua_State *L);
int luaopen_process(lua_State *L);
int luaopen_dirmonitor(lua_State* L);
int luaopen_utf8extra(lua_State* L);

#ifdef LUA_JIT
int luaopen_bit32(lua_State *L);
int luaopen_compat53_string(lua_State *L);
int luaopen_compat53_table(lua_State *L);
int luaopen_compat53_utf8(lua_State *L);
#define LUAJIT_COMPATIBILITY { "bit32", luaopen_bit32 }, \
  { "compat53.string", luaopen_compat53_string }, \
  { "compat53.table", luaopen_compat53_table }, \
  { "compat53.utf8", luaopen_compat53_utf8 },
#else
#define LUAJIT_COMPATIBILITY
#endif

static const luaL_Reg libs[] = {
  { "system",     luaopen_system     },
  { "renderer",   luaopen_renderer   },
  { "regex",      luaopen_regex      },
  { "process",    luaopen_process    },
  { "dirmonitor", luaopen_dirmonitor },
  { "utf8extra",  luaopen_utf8extra  },
  LUAJIT_COMPATIBILITY
  { NULL, NULL }
};


void api_load_libs(lua_State *L) {
  for (int i = 0; libs[i].name; i++)
    luaL_requiref(L, libs[i].name, libs[i].func, 1);
}
