#ifndef COMPAT_H
#define COMPAT_H

#include <lua.h>
#include <lauxlib.h>

#ifdef LITE_USE_LUAJIT

#define luaL_newlibtable(L, l) \
  (lua_createtable(L, 0, sizeof(l)/sizeof(*(l))-1))
#define luaL_newlib(L, l) \
  (luaL_newlibtable(L, l), luaL_register(L, NULL, l))

extern void luaL_requiref (lua_State *L, const char *modname, lua_CFunction openf, int glb);
extern void luaL_setfuncs (lua_State *L, const luaL_Reg *l, int nup);
extern void luaL_setmetatable (lua_State *L, const char *tname);
extern int luaL_getsubtable (lua_State *L, int i, const char *name);
#endif

#endif
