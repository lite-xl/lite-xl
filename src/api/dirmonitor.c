#include "api.h"
#include "lua.h"
#include "custom_events.h"
#include <SDL3/SDL.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <assert.h>

struct dirmonitor {
  SDL_Thread* thread;
  SDL_Mutex* mutex;
  char buffer[64512];
  volatile int length;
  struct dirmonitor_internal* internal;
};


struct dirmonitor_internal* init_dirmonitor();
void deinit_dirmonitor(struct dirmonitor_internal*);
int get_changes_dirmonitor(struct dirmonitor_internal*, char*, int);
int translate_changes_dirmonitor(struct dirmonitor_internal*, char*, int, int (*)(int, const char*, void*), void*);
int add_dirmonitor(struct dirmonitor_internal*, const char*);
void remove_dirmonitor(struct dirmonitor_internal*, int);
int get_mode_dirmonitor();


static int f_check_dir_callback(int watch_id, const char* path, void* L) {
  // using absolute indices from f_dirmonitor_check (2: callback, 3: error_callback, 4: watch_id notified table)

  // Check if we already notified about this watch
  lua_rawgeti(L, 4, watch_id);
  bool skip = !lua_isnoneornil(L, -1);
  lua_pop(L, 1);
  if (skip) return 0;

  // Set watch as notified
  lua_pushboolean(L, true);
  lua_rawseti(L, 4, watch_id);

  // Prepare callback call
  lua_pushvalue(L, 2);
  if (path)
    lua_pushlstring(L, path, watch_id);
  else
    lua_pushnumber(L, watch_id);

  int result = 0;
  if (lua_pcall(L, 1, 1, 3) == LUA_OK)
    result = lua_toboolean(L, -1);
  lua_pop(L, 1);
  return !result;
}


static int dirmonitor_check_thread(void* data) {
  struct dirmonitor* monitor = data;

  while (monitor->length >= 0) {
    if (monitor->length == 0) {
      int result = get_changes_dirmonitor(monitor->internal, monitor->buffer, sizeof(monitor->buffer));
      SDL_LockMutex(monitor->mutex);
      if (monitor->length == 0)
        monitor->length = result;
      SDL_UnlockMutex(monitor->mutex);
    }
    SDL_Delay(1);
    CustomEvent event;
    SDL_zero(event);
    push_custom_event("dirmonitor", &event);
  }
  return 0;
}


static int f_dirmonitor_new(lua_State* L) {
  struct dirmonitor* monitor = lua_newuserdata(L, sizeof(struct dirmonitor));
  luaL_setmetatable(L, API_TYPE_DIRMONITOR);
  memset(monitor, 0, sizeof(struct dirmonitor));
  monitor->mutex = SDL_CreateMutex();
  monitor->internal = init_dirmonitor();
  return 1;
}


static int f_dirmonitor_gc(lua_State* L) {
  struct dirmonitor* monitor = luaL_checkudata(L, 1, API_TYPE_DIRMONITOR);
  SDL_LockMutex(monitor->mutex);
  monitor->length = -1;
  deinit_dirmonitor(monitor->internal);
  SDL_UnlockMutex(monitor->mutex);
  SDL_WaitThread(monitor->thread, NULL);
  SDL_free(monitor->internal);
  SDL_DestroyMutex(monitor->mutex);
  return 0;
}


static int f_dirmonitor_watch(lua_State *L) {
  struct dirmonitor* monitor = luaL_checkudata(L, 1, API_TYPE_DIRMONITOR);
  lua_pushnumber(L, add_dirmonitor(monitor->internal, luaL_checkstring(L, 2)));
  if (!monitor->thread)
    monitor->thread = SDL_CreateThread(dirmonitor_check_thread, "dirmonitor_check_thread", monitor);
  return 1;
}


static int f_dirmonitor_unwatch(lua_State *L) {
  remove_dirmonitor(((struct dirmonitor*)luaL_checkudata(L, 1, API_TYPE_DIRMONITOR))->internal, lua_tonumber(L, 2));
  return 0;
}


static int f_noop(lua_State *L) { return 0; }


static int f_dirmonitor_check(lua_State* L) {
  struct dirmonitor* monitor = luaL_checkudata(L, 1, API_TYPE_DIRMONITOR);
  luaL_checktype(L, 2, LUA_TFUNCTION);
  if (!lua_isnoneornil(L, 3)) {
    luaL_checktype(L, 3, LUA_TFUNCTION);
  } else {
    lua_settop(L, 2);
    lua_pushcfunction(L, f_noop);
  }
  lua_settop(L, 3);

  SDL_LockMutex(monitor->mutex);
  if (monitor->length < 0)
    lua_pushnil(L);
  else if (monitor->length > 0) {
    // Create a table for keeping track of what watch ids were notified in this check,
    // so that we avoid notifying multiple times.
    lua_newtable(L);
    if (translate_changes_dirmonitor(monitor->internal, monitor->buffer, monitor->length, f_check_dir_callback, L) == 0)
      monitor->length = 0;
    lua_pushboolean(L, 1);
  } else
    lua_pushboolean(L, 0);
  SDL_UnlockMutex(monitor->mutex);
  return 1;
}


static int f_dirmonitor_mode(lua_State* L) {
  int mode = get_mode_dirmonitor();
  if (mode == 1)
    lua_pushstring(L, "single");
  else
    lua_pushstring(L, "multiple");
  return 1;
}


static const luaL_Reg dirmonitor_lib[] = {
  { "new",      f_dirmonitor_new         },
  { "__gc",     f_dirmonitor_gc          },
  { "watch",    f_dirmonitor_watch       },
  { "unwatch",  f_dirmonitor_unwatch     },
  { "check",    f_dirmonitor_check       },
  { "mode",     f_dirmonitor_mode        },
  {NULL, NULL}
};


int luaopen_dirmonitor(lua_State* L) {
  if (!register_custom_event("dirmonitor", NULL)) {
    return luaL_error(L, "Unable to register custom dirmonitor event: %s", SDL_GetError());
  }
  luaL_newmetatable(L, API_TYPE_DIRMONITOR);
  luaL_setfuncs(L, dirmonitor_lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  return 1;
}
