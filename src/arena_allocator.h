/**
 * An arena allocator using the Lua state; similar to luaL_Buffer.
 * Initialize the arena with lxl_arena_init(), and you can use lxl_arena_malloc(),
 * lxl_arena_zero() to allocate (and optionally zero) the memory.
 * lxl_arena_free() can be optionally used to free memory, but this is generally not needed.
 */

#ifndef LUA_ALLOCATOR_H
#define LUA_ALLOCATOR_H

#include <lua.h>

typedef struct lxl_arena lxl_arena;

lxl_arena *lxl_arena_init(lua_State *L);
void *lxl_arena_malloc(lxl_arena *arena, size_t size);
void *lxl_arena_zero(lxl_arena *arena, size_t size);
char *lxl_arena_copy(lxl_arena *arena, const void *ptr, size_t len);
char *lxl_arena_strdup(lxl_arena *arena, const char *str);
void lxl_arena_free(lxl_arena *arena, void *ptr);

#endif
