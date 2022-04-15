#include "api.h"
#include <stdlib.h>
#ifdef DIRMONITOR_WIN32
  #include <windows.h>
#endif
#include <unistd.h>
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <string.h>
#include <stdbool.h>

#ifndef DIRMONITOR_BACKEND
#error No dirmonitor backend defined
#endif

#define GLUE_HELPER(x, y) x##y
#define GLUE(x, y) GLUE_HELPER(x, y)

#define init_dirmonitor GLUE(init_dirmonitor_, DIRMONITOR_BACKEND)
#define deinit_dirmonitor GLUE(deinit_dirmonitor_, DIRMONITOR_BACKEND)
#define check_dirmonitor GLUE(check_dirmonitor_, DIRMONITOR_BACKEND)
#define add_dirmonitor GLUE(add_dirmonitor_, DIRMONITOR_BACKEND)
#define remove_dirmonitor GLUE(remove_dirmonitor_, DIRMONITOR_BACKEND)

struct dirmonitor {}; // dirmonitor struct is defined in each backend

// define functions so we know their signature
struct dirmonitor* init_dirmonitor();
void deinit_dirmonitor(struct dirmonitor*);
int check_dirmonitor(struct dirmonitor*, int (*)(int, const char*, void*), void*);
int add_dirmonitor(struct dirmonitor*, const char*);
void remove_dirmonitor(struct dirmonitor*, int);

static int f_check_dir_callback(int watch_id, const char* path, void* L) {
  lua_pushvalue(L, -1);
  #ifdef DIRMONITOR_WIN32
    char buffer[PATH_MAX*4];
    int count = WideCharToMultiByte(CP_UTF8, 0, (WCHAR*)path, watch_id, buffer, PATH_MAX*4 - 1, NULL, NULL);
    lua_pushlstring(L, buffer, count);
  #else
    lua_pushnumber(L, watch_id);
  #endif
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
