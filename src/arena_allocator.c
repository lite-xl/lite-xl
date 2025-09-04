#include "arena_allocator.h"

#include <string.h>
#include <lauxlib.h>

struct lxl_arena {
  lua_State *L;
  int ref;
};

lxl_arena *lxl_arena_init(lua_State *L) {
  lua_newtable(L);
  lxl_arena *arena = lua_newuserdata(L, sizeof(lxl_arena));
  arena->L = L; arena->ref = lua_gettop(L)-1;
  lua_rawseti(L, -2, 1);
  return arena;
}

void *lxl_arena_malloc(lxl_arena *arena, size_t size) {
  if (!arena || !arena->L) return NULL;
  if (!lua_istable(arena->L, arena->ref)) luaL_error(arena->L, "invalid arena reference");
  void *data = lua_newuserdata(arena->L, size);
  lua_pushlightuserdata(arena->L, data);
  lua_pushvalue(arena->L, -2);
  lua_settable(arena->L, arena->ref);
  lua_pop(arena->L, 1);
  return data;
}

void *lxl_arena_zero(lxl_arena *arena, size_t size) {
  void *v = lxl_arena_malloc(arena, size);
  return v ? memset(v, 0, size) : NULL;
}

char *lxl_arena_strdup(lxl_arena *arena, const char *str) {
  if (!str) return NULL;
  return lxl_arena_copy(arena, (void *) str, (strlen(str) + 1) * sizeof(char));
}

char *lxl_arena_copy(lxl_arena *arena, const void *ptr, size_t len) {
  if (!ptr) return NULL;
  char *output = lxl_arena_malloc(arena, sizeof(char) * len);
  return output ? memcpy(output, ptr, len) : NULL;
}

void lxl_arena_free(lxl_arena *arena, void *ptr) {
  if (!arena || !arena->L || !ptr) return;
  if (!lua_istable(arena->L, arena->ref)) luaL_error(arena->L, "invalid arena reference");
  lua_pushlightuserdata(arena->L, ptr);
  lua_pushnil(arena->L);
  lua_settable(arena->L, arena->ref);
}
