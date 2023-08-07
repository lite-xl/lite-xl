#include "api.h"
#include <SDL.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

// the buffer size must not exceed 64KB on Windows
// https://learn.microsoft.com/en-gb/windows/win32/api/winbase/nf-winbase-readdirectorychangesw
#define DIRMONITOR_BUFFER_SIZE 64512

static unsigned int DIR_EVENT_TYPE = 0;

struct dirmonitor {
  SDL_Thread* thread;
  SDL_mutex* mutex;
  char buffer[DIRMONITOR_BUFFER_SIZE];
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
  lua_pushvalue(L, -1);
  if (path)
    lua_pushlstring(L, path, watch_id);
  else
    lua_pushnumber(L, watch_id);
  lua_call(L, 1, 1);
  int result = lua_toboolean(L, -1);
  lua_pop(L, 1);
  return !result;
}


static int dirmonitor_check_thread(void* data) {
  struct dirmonitor* monitor = data;
  for (;;) {
    SDL_LockMutex(monitor->mutex);
    if (monitor->length < 0) break;
    // wait for changes from the backend
    if (monitor->length == 0)
      monitor->length = get_changes_dirmonitor(monitor->internal, monitor->buffer, sizeof(monitor->buffer));
    SDL_PushEvent(&(SDL_Event) { .type = DIR_EVENT_TYPE });
    SDL_UnlockMutex(monitor->mutex);
    SDL_Delay(1);
  }
  SDL_UnlockMutex(monitor->mutex);
  return 0;
}


static int f_dirmonitor_new(lua_State* L) {
  if (DIR_EVENT_TYPE == 0)
    DIR_EVENT_TYPE = SDL_RegisterEvents(1);
  struct dirmonitor* monitor = lua_newuserdata(L, sizeof(struct dirmonitor));
  luaL_setmetatable(L, API_TYPE_DIRMONITOR);
  memset(monitor, 0, sizeof(struct dirmonitor));
  monitor->mutex = SDL_CreateMutex();
  monitor->internal = init_dirmonitor();
  return 1;
}


static int f_dirmonitor_gc(lua_State* L) {
  struct dirmonitor* monitor = luaL_checkudata(L, 1, API_TYPE_DIRMONITOR);
  // when waiting for directory changes, the mutex is held by the thread, so we need to
  // cancel the current wait operation and attempt to set monitor->length to -1.
  // currently, all backends sets monitor->length to -1 when they encounter an error,
  // so it should stop the monitor thread just fine.
  deinit_dirmonitor(monitor->internal);
  SDL_LockMutex(monitor->mutex);
  monitor->length = -1;
  SDL_UnlockMutex(monitor->mutex);
  SDL_WaitThread(monitor->thread, NULL);
  free(monitor->internal);
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


static int f_dirmonitor_check(lua_State* L) {
  struct dirmonitor* monitor = luaL_checkudata(L, 1, API_TYPE_DIRMONITOR);
  luaL_checktype(L, 2, LUA_TFUNCTION);
  int lock_result = SDL_TryLockMutex(monitor->mutex);
  if (lock_result == -1 || monitor->length < 0) {
    lua_pushnil(L);
  } else if (lock_result == SDL_MUTEX_TIMEDOUT || monitor->length == 0) {
    lua_pushboolean(L, 0);
  } else {
    if (translate_changes_dirmonitor(monitor->internal, monitor->buffer, monitor->length, f_check_dir_callback, L) == 0)
      monitor->length = 0;
    lua_pushboolean(L, 1);
  }
  if (lock_result == 0)
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
  luaL_newmetatable(L, API_TYPE_DIRMONITOR);
  luaL_setfuncs(L, dirmonitor_lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  return 1;
}
