#include <string.h>
#include <lauxlib.h>
#include "luapool.h"

/**
 * Creates a pool, pushes the pool reference on the stack,
 * and returns the pool reference.
 */
lxl_pool *lxl_pcreate(lua_State *L) {
  lua_newtable(L);
  lxl_pool *pool = lua_newuserdata(L, sizeof(lxl_pool));
  lua_rawseti(L, -2, 1);
  pool->L = L; pool->ref = lua_gettop(L); pool->userdata = NULL;
  return pool;
}

/**
 * Returns a pool reference on the Lua stack, as specified by the index.
 * Returns NULL if the pool reference is invalid.
 */
lxl_pool *lxl_pfromidx(lua_State *L, int idx) {
  if (!lua_istable(L, idx)) return NULL;
  if (lua_rawgeti(L, idx, 1) != LUA_TUSERDATA) return (lua_pop(L, 1), NULL);
  lxl_pool *result = lua_touserdata(L, -1); lua_pop(L, 1);
  return result;
}

#define check_pool(pool) { \
  if (!(pool) || !(pool)->L) return NULL; \
  if (!lua_istable((pool)->L, (pool)->ref)) return NULL; \
  if (lua_rawgeti((pool)->L, (pool)->ref, 1) != LUA_TUSERDATA) return (lua_pop((pool)->L, 1), NULL); \
  lua_pop((pool)->L, 1); \
}

static void *alloc(lxl_pool *pool, size_t size) {
  lua_newtable(pool->L);
  void *res = lua_newuserdata(pool->L, size); lua_rawseti(pool->L, -2, 1);
  lua_pushinteger(pool->L, size); lua_rawseti(pool->L, -2, 2);
  lua_pushlightuserdata(pool->L, res);
  lua_rotate(pool->L, lua_gettop(pool->L)-1, 1);
  lua_rawset(pool->L, pool->ref);
  lua_pop(pool->L, 1);
  return res;
}

/**
 * Allocates memory in the pool and returns it.
 * Returns NULL if the pool reference is invalid.
 */
void *lxl_palloc(lxl_pool *pool, size_t size) {
  check_pool(pool);
  return alloc(pool, size);
}

/**
 * Allocates zeroed memory in the pool and returns it.
 * Returns NULL if the pool reference is invalid.
 */
void *lxl_pzero(lxl_pool *pool, size_t size) {
  check_pool(pool);
  void *res = alloc(pool, size);
  return memset(res, 0, size);
} 

/**
 * Resizes the memory pointed by ptr and returns it. ptr can be NULL.
 * This function is similar to realloc(), but it will ALWAYS return
 * a different pointer as resizing userdata is impossible in Lua.
 * Returns NULL if the pool reference is invalid.
 */
void *lxl_presize(lxl_pool *pool, void *ptr, size_t size) {
  check_pool(pool);
  void *res = alloc(pool, size);
  if (ptr) {
    // get the size of ptr and copy the value over
    if (lua_rawgetp(pool->L, pool->ref, ptr) != LUA_TTABLE)
      return (lua_pop(pool->L, 1), NULL);
    int isnum = 0;
    size_t old_size = (lua_rawgeti(pool->L, -1, 2), lua_tointegerx(pool->L, -1, &isnum));
    if (!isnum) return (lua_pop(pool->L, 1), NULL);
    lua_pop(pool->L, 1);
    memcpy(res, ptr, old_size > size ? size : old_size);
  }
  return res;
}

/**
 * Creates a copy of data in ptr, up to size bytes, and returns it.
 * Returns NULL if the pool reference is invalid, or ptr is NULL.
 */
void *lxl_pcopy(lxl_pool *pool, void *ptr, size_t size) {
  check_pool(pool);
  void *res = alloc(pool, size);
  return memcpy(res, ptr, size);
}

/**
 * Creates a copy of str.
 * Returns NULL if the pool reference is invalid, or str is NULL.
 */
char *lxl_pstrdup(lxl_pool *pool, const char *str) {
  check_pool(pool);
  size_t len = strlen(str) + 1;
  void *res = alloc(pool, len * sizeof(char));
  return memcpy(res, (void *) str, len);
}

/**
 * Frees memory in a pool. ptr can be NULL.
 * This function cannot guarantee that the allocated memory are freed immediately.
 */
void lxl_pfree(lxl_pool *pool, void *ptr) {
  if (!pool || !pool->L) return;
  if (!lua_istable(pool->L, pool->ref)) return;
  if (lua_rawgeti(pool->L, pool->ref, 1) != LUA_TUSERDATA) { lua_pop(pool->L, 1); return; }
  lua_pop(pool->L, 1);
  lua_pushnil(pool->L);
  lua_rawsetp(pool->L, pool->ref, ptr);
}

/**
 * Frees the pool and all allocated memory in it.
 * This function cannot guarantee that the allocated memory are freed immediately.
 */
void lxl_pdestroy(lxl_pool *pool) {
  if (!pool || !pool->L) return;
  if (!lua_istable(pool->L, pool->ref)) return;
  if (lua_rawgeti(pool->L, pool->ref, 1) != LUA_TUSERDATA) { lua_pop(pool->L, 1); return; }
  lua_pushnil(pool->L);
  lua_replace(pool->L, pool->ref);
}