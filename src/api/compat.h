/* Adapted from:
** https://github.com/keplerproject/lua-compat-5.2
*/
#ifndef COMPAT_H
#define COMPAT_H

#include <stdint.h>

#include <lua.h>
#include <lauxlib.h>

typedef uint32_t lua_Unsigned;

typedef struct luaL_Buffer_52 {
  luaL_Buffer b; /* make incorrect code crash! */
  char *ptr;
  size_t nelems;
  size_t capacity;
  lua_State *L2;
} luaL_Buffer_52;
#define luaL_Buffer luaL_Buffer_52

#define luaL_newlibtable(L, l) \
  (lua_createtable(L, 0, sizeof(l)/sizeof(*(l))-1))
#define luaL_newlib(L, l) \
  (luaL_newlibtable(L, l), luaL_register(L, NULL, l))

extern void luaL_requiref (lua_State *L, const char *modname, lua_CFunction openf, int glb);
extern void luaL_setfuncs (lua_State *L, const luaL_Reg *l, int nup);
extern void luaL_setmetatable (lua_State *L, const char *tname);
extern int luaL_getsubtable (lua_State *L, int i, const char *name);
extern void lua_pushunsigned (lua_State *L, lua_Unsigned n);
extern lua_Unsigned luaL_checkunsigned (lua_State *L, int i);
extern lua_Unsigned luaL_optunsigned (lua_State *L, int i, lua_Unsigned def);

#define lua_rawlen(L, i) lua_objlen(L, i)

#define luaL_buffinit luaL_buffinit_52
void luaL_buffinit (lua_State *L, luaL_Buffer_52 *B);

#define luaL_prepbuffsize luaL_prepbuffsize_52
char *luaL_prepbuffsize (luaL_Buffer_52 *B, size_t s);

#define luaL_addlstring luaL_addlstring_52
void luaL_addlstring (luaL_Buffer_52 *B, const char *s, size_t l);

#define luaL_addvalue luaL_addvalue_52
void luaL_addvalue (luaL_Buffer_52 *B);

#define luaL_pushresult luaL_pushresult_52
void luaL_pushresult (luaL_Buffer_52 *B);

#undef luaL_buffinitsize
#define luaL_buffinitsize(L, B, s) \
  (luaL_buffinit(L, B), luaL_prepbuffsize(B, s))

#undef luaL_prepbuffer
#define luaL_prepbuffer(B) \
  luaL_prepbuffsize(B, LUAL_BUFFERSIZE)

#undef luaL_addsize
#define luaL_addsize(B, s) \
  ((B)->nelems += (s))

#undef luaL_addstring
#define luaL_addstring(B, s) \
  luaL_addlstring(B, s, strlen(s))

#undef luaL_pushresultsize
#define luaL_pushresultsize(B, s) \
  (luaL_addsize(B, s), luaL_pushresult(B))

#endif
