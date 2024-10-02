/**
 * luapool.h: Pool allocator for Lua.
 * A simple pool allocator that can be used to allocate and free memory
 * using Lua's GC.
 * 
 * Create a lxl_pool with lxl_pcreate() and allocate memory using
 * lxl_palloc(), lxl_pzero(), lxl_presize(), lxl_pcopy() and lxl_pstrdup().
 * You can free the memory with lxl_pfree(), but this is generally not needed.
 * If you need to free the memory in a pool immediately, use lxl_pdestroy().
 * You must not use the pool after it has been destroyed.
 * 
 * We call the act of setting the pool's lifetime as "pinning".
 * When a pool is created, it is "pinned" to the stack slot that contains the "pool reference".
 * A pool reference is the Lua object that manages the lifetime of the pool.
 * You can use pool->ref to get the stack index of the pool reference.
 * Note that pool->ref is always the stack index, and this value will be invalid
 * if you stored the pool reference somewhere else (e.g. the Lua Registry).
 * You can use  lxl_pfromidx() to get a lxl_pool from an object in the stack.
 * Finally, you can use pool->userdata to store extra data as a pointer.
 * 
 * Memory will not be freed immediately when the pool goes out of scope - it is
 * subjected under the rules of Lua GC. There is no way to control this.
 */

#ifndef LUAPOOL_H
#define LUAPOOL_H

#include <lua.h>

typedef struct {
  /** Lua state associated to the pool */
  lua_State *L;
  /** Stack index to the pool reference */
  int        ref;
  /** User-specified data */
  void      *userdata;
} lxl_pool;

/**
 * Creates a pool, pushes the pool reference on the stack,
 * and returns the pool reference.
 */
lxl_pool *lxl_pcreate(lua_State *L);
/**
 * Returns a pool reference on the Lua stack, as specified by the index.
 * Returns NULL if the pool reference is invalid.
 */
lxl_pool *lxl_pfromidx(lua_State *L, int idx);

/**
 * Allocates memory in the pool and returns it.
 * Returns NULL if the pool reference is invalid.
 */
void *lxl_palloc(lxl_pool *pool, size_t size);
/**
 * Allocates zeroed memory in the pool and returns it.
 * Returns NULL if the pool reference is invalid.
 */
void *lxl_pzero(lxl_pool *pool, size_t size);
/**
 * Resizes the memory pointed by ptr and returns it. ptr can be NULL.
 * This function is similar to realloc(), but it will ALWAYS return
 * a different pointer as resizing userdata is impossible in Lua.
 * Returns NULL if the pool reference is invalid.
 */
void *lxl_presize(lxl_pool *pool, void *ptr, size_t size);
/**
 * Creates a copy of data in ptr, up to size bytes, and returns it.
 * Returns NULL if the pool reference is invalid, or ptr is NULL.
 */
void *lxl_pcopy(lxl_pool *pool, void *ptr, size_t size);
/**
 * Creates a copy of str.
 * Returns NULL if the pool reference is invalid, or str is NULL.
 */
char *lxl_pstrdup(lxl_pool *pool, const char *str);

/**
 * Frees memory in a pool. ptr can be NULL.
 * This function cannot guarantee that the allocated memory are freed immediately.
 */
void lxl_pfree(lxl_pool *pool, void *ptr);
/**
 * Frees the pool and all allocated memory in it.
 * This function cannot guarantee that the allocated memory are freed immediately.
 */
void lxl_pdestroy(lxl_pool *pool);

#endif