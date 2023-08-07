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
  /**
   * This function assumes the following stack positions:
   * -1: the callback to call
   * -2: a table to store errors, if any
   */
  int cb_idx = lua_absindex(L, -1);
  int err_tbl_idx = lua_absindex(L, -2);

  lua_pushvalue(L, cb_idx);
  if (path)
    lua_pushlstring(L, path, watch_id);
  else
    lua_pushnumber(L, watch_id);

  int err = lua_pcall(L, 1, 1, 0);
  if (err != LUA_OK) {
    // stores the corresponding path/watchid and the error message into the table
    if (err != LUA_ERRRUN)
      lua_pushliteral(L, "Lua runtime error");

    if (path)
      lua_pushlstring(L, path, watch_id);
    else
      lua_pushnumber(L, watch_id);
    // stack[-4] = err_tbl, stack[-3] = cb, stack[-2] = err_str, stack[-1] = path
    lua_rawseti(L, err_tbl_idx, lua_rawlen(L, err_tbl_idx) + 1);
    lua_rawseti(L, err_tbl_idx, lua_rawlen(L, err_tbl_idx) + 1);
    return 1;
  }

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
  lua_settop(L, 2);

  int retval = 1;
  int lock_result = SDL_TryLockMutex(monitor->mutex);
  if (lock_result == -1 || monitor->length < 0) {
    lua_pushnil(L);
  } else if (lock_result == SDL_MUTEX_TIMEDOUT || monitor->length == 0) {
    lua_pushboolean(L, 0);
  } else {
    lua_newtable(L);
    lua_pushvalue(L, 2);
    // stack[1] = dirmonitor, stack[2] = cb, stack[3] = err_tbl, stack[4] = cb
    if (translate_changes_dirmonitor(monitor->internal, monitor->buffer, monitor->length, f_check_dir_callback, L) == 0)
      monitor->length = 0;
    lua_pushboolean(L, 1);
    // if an error occured, return a table containing error messages
    if (lua_rawlen(L, 3) > 0) {
      retval = 2;
      lua_pushvalue(L, 3);
    }
  }
  if (lock_result == 0)
    SDL_UnlockMutex(monitor->mutex);
  return retval;
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
