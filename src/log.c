#include <stdarg.h>
#include <SDL.h>
#include <lua.h>
#include <lauxlib.h>
#include "log.h"

#define LXL_LOG_STR_IDX "__lxl_log_str__"

// TODO: thread safety
static SDL_LogOutputFunction default_fn = NULL;
static void *default_userdata = NULL;

static void lxl_log(void *userdata, int category, SDL_LogPriority priority, const char *message) {
  if (default_fn)
    default_fn(default_userdata, category, priority, message);
  if (priority == SDL_LOG_PRIORITY_CRITICAL)
    SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "Critical error", message, NULL);
}

void lxl_log_init() {
  SDL_LogOutputFunction fn;
  void *data;
  SDL_LogGetOutputFunction(&fn, &data);

  if (default_fn != fn && fn != lxl_log) {
    default_fn = fn;
    default_userdata = data;
  }

  if (getenv("LITE_XL_DEBUG"))
    SDL_LogSetPriority(SDL_LOG_CATEGORY_APPLICATION, SDL_LOG_PRIORITY_VERBOSE);
}

void lxl_log_verbose(const char *fmt, ...) {
  va_list ap;

  va_start(ap, fmt);
  SDL_LogMessageV(SDL_LOG_CATEGORY_APPLICATION, SDL_LOG_PRIORITY_VERBOSE, fmt, ap);
  va_end(ap);
}

void lxl_log_info(const char *fmt, ...) {
  va_list ap;

  va_start(ap, fmt);
  SDL_LogMessageV(SDL_LOG_CATEGORY_APPLICATION, SDL_LOG_PRIORITY_INFO, fmt, ap);
  va_end(ap);
}

void lxl_log_warn(const char *fmt, ...) {
  va_list ap;

  va_start(ap, fmt);
  SDL_LogMessageV(SDL_LOG_CATEGORY_APPLICATION, SDL_LOG_PRIORITY_WARN, fmt, ap);
  va_end(ap);
}

void lxl_log_error(const char *fmt, ...) {
  va_list ap;

  va_start(ap, fmt);
  SDL_LogMessageV(SDL_LOG_CATEGORY_APPLICATION, SDL_LOG_PRIORITY_ERROR, fmt, ap);
  va_end(ap);
}

void lxl_log_critical(const char *fmt, ...) {
  va_list ap;

  va_start(ap, fmt);
  SDL_LogMessageV(SDL_LOG_CATEGORY_APPLICATION, SDL_LOG_PRIORITY_CRITICAL, fmt, ap);
  va_end(ap);
}

static void warnoff(void *ud, const char *msg, int tocont);

static int checkcontrol(lua_State *L, const char *msg, int tocont) {
  // adapted from Lua 5.4 source code
  // https://www.lua.org/source/5.4/lauxlib.c.html#checkcontrol
  if (tocont || *(msg++) != '@')
    return 0;
  if (strcmp(msg, "off") == 0)
    lua_setwarnf(L, warnoff, L); // disable warning
  else if (strcmp(msg, "on") == 0)
    lua_setwarnf(L, lxl_log_setwarnf, L); // enable warning
  return 1;
}

// warn handler when warning is turned on (default)
void lxl_log_setwarnf(void *ud, const char *msg, int tocont) {
  lua_State *L = (lua_State*) ud;

  if (checkcontrol(L, msg, tocont))
    return;

  // get an existing warning
  if (lua_getfield(L, LUA_REGISTRYINDEX, LXL_LOG_STR_IDX) != LUA_TSTRING) {
    lua_pop(L, 1);
    lua_pushliteral(L, "");
  }
  lua_pushnil(L);
  lua_setfield(L, LUA_REGISTRYINDEX, LXL_LOG_STR_IDX);

  // concatenate the last warn message with the current one
  lua_pushstring(L, msg);
  lua_concat(L, 2);

  if (tocont) {
    // if we have more message, save this warn message to the registry
    lua_setfield(L, LUA_REGISTRYINDEX, LXL_LOG_STR_IDX);
  } else {
    // just print it
    lxl_log_warn("%s", lua_tostring(L, -1));
    lua_pop(L, 1);
  }
}

// warn handler when warning is turned off
static void warnoff(void *ud, const char *msg, int tocont) {
  checkcontrol((lua_State*) ud, msg, tocont);
}