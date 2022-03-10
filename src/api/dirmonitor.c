#include "api.h"
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <string.h>
#include <stdbool.h>

/*
This is *slightly* a clusterfuck. Normally, we'd
have windows wait on a list of handles like inotify,
however, MAXIMUM_WAIT_OBJECTS is 64. Yes, seriously.

So, for windows, we are recursive.
*/
struct dirmonitor {
  int fd;
};

struct dirmonitor* init_dirmonitor() {
  struct dirmonitor* monitor = calloc(sizeof(struct dirmonitor), 1);
  monitor->fd = 0;
  return monitor;
}


void deinit_dirmonitor(struct dirmonitor* monitor) {
  free(monitor);
}

int check_dirmonitor(struct dirmonitor* monitor, int (*change_callback)(int, const char*, void*), void* data) {
  return 0;	
}

int add_dirmonitor(struct dirmonitor* monitor, const char* path) {
  return 0;
}

void remove_dirmonitor(struct dirmonitor* monitor, int fd) {
}

static int f_check_dir_callback(int watch_id, const char* path, void* L) {
  lua_pushvalue(L, -1);
  lua_pushnumber(L, watch_id);
  lua_call(L, 1, 1);
  int result = lua_toboolean(L, -1);
  lua_pop(L, 1);
  return !result;
}

static int f_dirmonitor_new(lua_State* L) {
  struct dirmonitor** monitor = lua_newuserdata(L, sizeof(struct dirmonitor**));
  *monitor = init_dirmonitor();
  luaL_setmetatable(L, API_TYPE_DIRMONITOR);
  return 1;
}

static int f_dirmonitor_gc(lua_State* L) {
  deinit_dirmonitor(*((struct dirmonitor**)luaL_checkudata(L, 1, API_TYPE_DIRMONITOR)));
  return 0;
}

static int f_dirmonitor_watch(lua_State *L) {
  lua_pushnumber(L, add_dirmonitor(*(struct dirmonitor**)luaL_checkudata(L, 1, API_TYPE_DIRMONITOR), luaL_checkstring(L, 2)));
  return 1;
}

static int f_dirmonitor_unwatch(lua_State *L) {
  remove_dirmonitor(*(struct dirmonitor**)luaL_checkudata(L, 1, API_TYPE_DIRMONITOR), luaL_checknumber(L, 2));
  return 0;
}

static int f_dirmonitor_check(lua_State* L) {
  lua_pushnumber(L, check_dirmonitor(*(struct dirmonitor**)luaL_checkudata(L, 1, API_TYPE_DIRMONITOR), f_check_dir_callback, L));
  return 1;
}
static const luaL_Reg dirmonitor_lib[] = {
  { "new",      f_dirmonitor_new         },
  { "__gc",     f_dirmonitor_gc          },
  { "watch",    f_dirmonitor_watch       },
  { "unwatch",  f_dirmonitor_unwatch     },
  { "check",    f_dirmonitor_check       },
  {NULL, NULL}
};

int luaopen_dirmonitor(lua_State* L) {
  luaL_newmetatable(L, API_TYPE_DIRMONITOR);
  luaL_setfuncs(L, dirmonitor_lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  return 1;
}
