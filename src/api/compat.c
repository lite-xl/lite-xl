#include <string.h>

#include <lauxlib.h>

#include "compat.h"

static int lua_absindex (lua_State *L, int i) {
  if (i < 0 && i > LUA_REGISTRYINDEX)
    i += lua_gettop(L) + 1;
  return i;
}

int luaL_getsubtable (lua_State *L, int i, const char *name) {
  int abs_i = lua_absindex(L, i);
  luaL_checkstack(L, 3, "not enough stack slots");
  lua_pushstring(L, name);
  lua_gettable(L, abs_i);
  if (lua_istable(L, -1))
    return 1;
  lua_pop(L, 1);
  lua_newtable(L);
  lua_pushstring(L, name);
  lua_pushvalue(L, -2);
  lua_settable(L, abs_i);
  return 0;
}

void luaL_requiref (lua_State *L, const char *modname, lua_CFunction openf, int glb) {
  luaL_checkstack(L, 3, "not enough stack slots available");
  luaL_getsubtable(L, LUA_REGISTRYINDEX, "_LOADED");
  lua_getfield(L, -1, modname);
  if (lua_isnil(L, -1)) {
    lua_pop(L, 1);
    lua_pushcfunction(L, openf);
    lua_pushstring(L, modname);
    lua_call(L, 1, 1);
    lua_pushvalue(L, -1);
    lua_setfield(L, -3, modname);
  }
  if (glb) {
    lua_pushvalue(L, -1);
    lua_setglobal(L, modname);
  }
  lua_replace(L, -2);
}

void luaL_setfuncs (lua_State *L, const luaL_Reg *l, int nup) {
  luaL_checkstack(L, nup+1, "too many upvalues");
  for (; l->name != NULL; l++) {  /* fill the table with given functions */
    int i;
    lua_pushstring(L, l->name);
    for (i = 0; i < nup; i++)  /* copy upvalues to the top */
      lua_pushvalue(L, -(nup + 1));
    lua_pushcclosure(L, l->func, nup);  /* closure with those upvalues */
    lua_settable(L, -(nup + 3)); /* table must be below the upvalues, the name and the closure */
  }
  lua_pop(L, nup);  /* remove upvalues */
}


void luaL_setmetatable (lua_State *L, const char *tname) {
  luaL_checkstack(L, 1, "not enough stack slots");
  luaL_getmetatable(L, tname);
  lua_setmetatable(L, -2);
}

void luaL_buffinit (lua_State *L, luaL_Buffer_52 *B) {
  /* make it crash if used via pointer to a 5.1-style luaL_Buffer */
  B->b.p = NULL;
  B->b.L = NULL;
  B->b.lvl = 0;
  /* reuse the buffer from the 5.1-style luaL_Buffer though! */
  B->ptr = B->b.buffer;
  B->capacity = LUAL_BUFFERSIZE;
  B->nelems = 0;
  B->L2 = L;
}


char *luaL_prepbuffsize (luaL_Buffer_52 *B, size_t s) {
  if (B->capacity - B->nelems < s) { /* needs to grow */
    char* newptr = NULL;
    size_t newcap = B->capacity * 2;
    if (newcap - B->nelems < s)
      newcap = B->nelems + s;
    if (newcap < B->capacity) /* overflow */
      luaL_error(B->L2, "buffer too large");
    newptr = lua_newuserdata(B->L2, newcap);
    memcpy(newptr, B->ptr, B->nelems);
    if (B->ptr != B->b.buffer)
      lua_replace(B->L2, -2); /* remove old buffer */
    B->ptr = newptr;
    B->capacity = newcap;
  }
  return B->ptr+B->nelems;
}


void luaL_addlstring (luaL_Buffer_52 *B, const char *s, size_t l) {
  memcpy(luaL_prepbuffsize(B, l), s, l);
  luaL_addsize(B, l);
}


void luaL_addvalue (luaL_Buffer_52 *B) {
  size_t len = 0;
  const char *s = lua_tolstring(B->L2, -1, &len);
  if (!s)
    luaL_error(B->L2, "cannot convert value to string");
  if (B->ptr != B->b.buffer)
    lua_insert(B->L2, -2); /* userdata buffer must be at stack top */
  luaL_addlstring(B, s, len);
  lua_remove(B->L2, B->ptr != B->b.buffer ? -2 : -1);
}


void luaL_pushresult (luaL_Buffer_52 *B) {
  lua_pushlstring(B->L2, B->ptr, B->nelems);
  if (B->ptr != B->b.buffer)
    lua_replace(B->L2, -2); /* remove userdata buffer */
}

#define lua_number2unsigned(i,n)	((i)=(lua_Unsigned)(n))
#define lua_unsigned2number(u)  \
    (((u) <= (lua_Unsigned)INT_MAX) ? (lua_Number)(int)(u) : (lua_Number)(u))

lua_Unsigned luaL_checkunsigned (lua_State *L, int i) {
  lua_Unsigned result;
  lua_Number n = lua_tonumber(L, i);
  if (n == 0 && !lua_isnumber(L, i))
    luaL_checktype(L, i, LUA_TNUMBER);
  lua_number2unsigned(result, n);
  return result;
}

lua_Unsigned luaL_optunsigned (lua_State *L, int i, lua_Unsigned def) {
  return luaL_opt(L, luaL_checkunsigned, i, def);
}

void lua_pushunsigned (lua_State *L, lua_Unsigned n) {
  lua_pushnumber(L, lua_unsigned2number(n));
}

