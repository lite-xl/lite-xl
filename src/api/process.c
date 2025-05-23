#include "api.h"

#include <SDL3/SDL.h>
#include <SDL3/SDL_thread.h>

#define READ_BUF_SIZE 4096
#define PROCESS_TERM_TRIES 3
#define PROCESS_TERM_DELAY 50
#define PROCESS_KILL_LIST_NAME "__process_kill_list__"

#if defined(SDL_PLATFORM_UNIX)
#include <signal.h>
#if defined(SDL_PLATFORM_WINDOWS)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

#ifndef SDL_PROP_PROCESS_CREATE_WORKING_DIRECTORY_STRING
#define SDL_PROP_PROCESS_CREATE_WORKING_DIRECTORY_STRING "TODO"
#warning SDL_PROP_PROCESS_CREATE_WORKING_DIRECTORY_STRING not supported
#endif

#ifndef SDL_PROP_PROCESS_CREATE_CMDLINE_STRING
#define SDL_PROP_PROCESS_CREATE_CMDLINE_STRING "TODO"
#warning SDL_PROP_PROCESS_CREATE_CMDLINE_STRING not supported
#endif

#define LXL_PROCESS_PROP_PROCESS_PTR "lxl.process.sdl_process.ptr"
#define LXL_PROCESS_PROP_DEADLINE_NUM "lxl.process.deadline.int"
#define LXL_PROCESS_PROP_RETURNCODE_NUM "lxl.process.returncode.int"
#define LXL_PROCESS_PROP_STREAM_CLOSED_NUM "lxl.process.stream_closed.int"

typedef enum {
  SIGNAL_KILL,
  SIGNAL_TERM,
  SIGNAL_INTERRUPT
} signal_e;

typedef enum {
  REDIRECT_PIPE,
  REDIRECT_PARENT,
  REDIRECT_DISCARD,
  REDIRECT_STDOUT
} redirect_e;

static const char *enum_redirect = {
  "pipe",
  "parent",
  "discard",
  "stdout",
  NULL
};

typedef enum {
  STREAM_STDIN = 1 << 0,
  STREAM_STDOUT = 1 << 1,
  STREAM_STDERR = 1 << 2,
} stream_type_e;

// love bitfields
static const char *enum_stream_type = { "stdin", "stdout", "stderr", NULL };

static const char *enum_sdl_stream_type[] = {
  SDL_PROP_PROCESS_STDIN_POINTER,
  SDL_PROP_PROCESS_STDOUT_POINTER,
  SDL_PROP_PROCESS_STDERR_POINTER,
  NULL
};

static int f_cleanup_properties(lua_State *L) {
  SDL_PropertiesID id = lua_rawgeti(L, 1, 1);
  if (id != 0) SDL_DestroyProperties(id);
  return 0;
}

static void free_null_list(void *ud, void *ptr) {
  (void) ud;
  for (void **p = ptr; *p; p++) SDL_free(*p);
  SDL_free(ptr);
}

static void free_sdl_env(void *ud, void *ptr) {
  (void) ud;
  if (ptr) SDL_DestroyEnvironment((SDL_Environment *) ptr);
}

#define GET_PROCESS(L, idx) \
  SDL_GetPointerProperty(*((SDL_PropertiesID *) luaL_checkudata(L, 1, API_TYPE_PROCESS)), LXL_PROCESS_PROP_PROCESS_PTR, NULL)

#define GET_PROCESS_PROP(L, idx) \
  *((SDL_PropertiesID *) luaL_checkudata(L, 1, API_TYPE_PROCESS))


static int process_start(lua_State* L) {
  lua_settop(L, 2);
  if (!lua_istable(L, 1) && !lua_isstring(L, 1))
    return luaL_argerror(L, 1, "expected string or table");
  if (!lua_isnoneornil(L, 1))
    luaL_checktype(L, 2, LUA_TTABLE);

  SDL_PropertiesID props = SDL_CreateProperties();
  if (!props)
    return luaL_error("cannot start process: %s", SDL_GetError());
  
  // create properties on a to be closed slot
  lua_newtable(L);
  lua_pushinteger(L, props); lua_rawseti(L, -2, 1);
  lua_pushcfunction(L, f_cleanup_properties); lua_setfield(L, -2, "__close");
  lua_pushvalue(L, -1); lua_setmetatable(L, -2);
  int to_close = lua_gettop(L);
  // anything down here failing will automatically destroy the SDL_propertiesID

  if (lua_istable(L, 1)) {
    int len = luaL_len(L, 1);
    if (!len)
      return luaL_argerror(L, 1, "argument table cannot be empty");
    
    char **cmd = SDL_calloc(len + 1, sizeof(char *));
    if (!cmd)
      return luaL_error(L, "cannot start process: cannot allocate memory");
    SDL_SetPointerPropertyWithCleanup(props, SDL_PROP_PROCESS_CREATE_ARGS_POINTER, cmd, free_null_list, NULL);

    // if this block errors everything is handled by property cleanup
    for (int i = 1; i <= len; i++) {
      cmd[i-1] = SDL_strdup((lua_rawgeti(L, 1, i), luaL_checkstring(L, -1)));
      if (!cmd[i-1])
        return luaL_error(L, "cannot start process: cannot allocate memory");
      lua_pop(L, 1);
    }
  } else {
    // only supported on Windows
    SDL_SetStringProperty(props, SDL_PROP_PROCESS_CREATE_CMDLINE_STRING, luaL_checkstring(L, 1));
  }

  if (lua_isnoneornil(L, 2)) {
    lua_newtable(L);
    lua_replace(L, 2);
  }

  if (lua_getfield(L, 2, "detach") != LUA_TNIL) SDL_SetBooleanProperty(props, SDL_PROP_PROCESS_CREATE_BACKGROUND_BOOLEAN, lua_toboolean(L, -1));
  if (lua_getfield(L, 2, "cwd") != LUA_TNIL)    SDL_SetStringProperty(props, SDL_PROP_PROCESS_CREATE_WORKING_DIRECTORY_STRING, luaL_checkstring(L, -1));
  lua_pop(L, 2);
  
  const char *stdpipes[][2] = {
    { "stdin", SDL_PROP_PROCESS_CREATE_STDIN_NUMBER },
    { "stdout", SDL_PROP_PROCESS_CREATE_STDOUT_NUMBER },
    { "stderr", SDL_PROP_PROCESS_CREATE_STDERR_NUMBER },
  };
  for (int i = 0; i < SDL_arraysize(stdpipes); i++) {
    lua_getfield(L, 2, stdpipes[i][0]);
    switch (luaL_checkoption(L, -1, "parent", enum_redirect)) {
      case REDIRECT_PARENT:
        SDL_SetNumberProperty(props, stdpipes[i][1], SDL_PROCESS_STDIO_INHERITED);
        break;
      case REDIRECT_DISCARD:
        SDL_SetNumberProperty(props, stdpipes[i][1], SDL_PROCESS_STDIO_NULL);
        break;
      case REDIRECT_PIPE:
        SDL_SetNumberProperty(props, stdpipes[i][1], SDL_PROCESS_STDIO_APP);
        break;
      case REDIRECT_STDOUT:
        if (SDL_strcmp(stdpipes[i][0], "stderr") != 0)
          return luaL_argerror(L, 2, "cannot start process: redirect type 'stdout' is not supported on stdin or stdout");
        SDL_SetBooleanProperty(props, SDL_PROP_PROCESS_CREATE_STDERR_TO_STDOUT_BOOLEAN, true);
      break;
    }
    lua_pop(L, 1);
  }

  if (lua_getfield(L, 2, "env"))
    luaL_checktype(L, -1, LUA_TTABLE);

  SDL_Environment *env = SDL_CreateEnvironment(true);
  if (!env)
    return luaL_error(L, "cannot start process: %s", SDL_GetError());
  SDL_SetPointerPropertyWithCleanup(props, SDL_PROP_PROCESS_CREATE_ENVIRONMENT_POINTER, env, free_sdl_env, NULL);

  // again, environment is cleaned up if this fails
  lua_pushnil(L);
  while (lua_next(L, -2)) {
    SDL_SetEnvironmentVariable(env, luaL_checkstring(L, -2), luaL_checkstring(L, -1), true);
    lua_pop(L, 1);
  }
  lua_pop(L, 1);

  SDL_Process *proc = SDL_CreateProcessWithProperties(props);
  if (!proc)
    return luaL_error(L, "cannot start process: %s", SDL_GetError());

  SDL_SetPointerProperty(props, LXL_PROCESS_PROP_PROCESS_PTR, proc);
  // clear the to-be-closed slot to prevent it from destroying the process
  lua_pushinteger(L, 0); lua_rawseti(L, to_close, 1);

  *((SDL_PropertiesID *) lua_newuserdata(L, sizeof(SDL_PropertiesID))) = props;
  luaL_setmetatable(L, API_TYPE_PROCESS);

  return 1;
}

static int g_read(lua_State* L, stream_type_e stream, size_t read_size) {
  SDL_Process *proc = GET_PROCESS(L, 1);
  SDL_assert(proc != NULL);

  int closed = SDL_GetNumberProperty(GET_PROCESS_PROP(L, 1), LXL_PROCESS_PROP_STREAM_CLOSED_NUM, 0);
  if (closed & stream)
    return luaL_error(L, "cannot read stream: stream is closed");

  SDL_PropertiesID props = SDL_GetProcessProperties(proc);
  if (!props)
    return luaL_error(L, "cannot read stream: %s", SDL_GetError());

  SDL_ProcessIO *stream = SDL_GetPointerProperty(props, stream == STREAM_STDOUT ? SDL_PROP_PROCESS_STDOUT_POINTER : SDL_PROP_PROCESS_STDERR_POINTER, NULL);
  if (!stream)
    return luaL_error(L, "cannot read stream: %s", SDL_GetError());

  luaL_Buffer B;
  char *buf = luaL_buffinitsize(L, &B, read_size);
  size_t length = SDL_ReadIO(stream, buf, read_size);
  luaL_pushresultsize(&B, length);

  int top = lua_gettop(L);
  switch (SDL_GetIOStatus(stream)) {
    case SDL_IO_STATUS_ERROR:     lua_pushliteral(L, "error"); lua_pushstring(L, SDL_GetError()); break;
    case SDL_IO_STATUS_EOF:       lua_pushliteral(L, "eof");   break;
    case SDL_IO_STATUS_NOT_READY: lua_pushliteral(L, "wait");  break;
    case SDL_IO_STATUS_READONLY:
    case SDL_IO_STATUS_WRITEONLY: SDL_assert(true && "unreachable code"); break;
  }

  return lua_gettop(L) - top + 1;
}

static int f_write(lua_State* L) {
  SDL_Process *proc = GET_PROCESS(L, 1);
  SDL_assert(proc != NULL);

  int closed = SDL_GetNumberProperty(GET_PROCESS_PROP(L, 1), LXL_PROCESS_PROP_STREAM_CLOSED_NUM, 0);
  if (closed & STREAM_STDIN)
    return luaL_error(L, "cannot write to stream: stream is closed");

  SDL_ProcessIO *stream = SDL_GetProcessInput(proc);
  if (!stream)
    return luaL_error(L, "cannot write to stream: %s", SDL_GetError());

  int top = lua_gettop(L);
  lua_pushinteger(L, SDL_WriteIO(stream, luaL_checkstring(L, 2), lua_rawlen(L, 2)));
  switch (SDL_GetIOStatus(stream)) {
    case SDL_IO_STATUS_ERROR:     lua_pushliteral(L, "error"); lua_pushstring(L, SDL_GetError()); break;
    case SDL_IO_STATUS_EOF:       lua_pushliteral(L, "eof");   break;
    case SDL_IO_STATUS_NOT_READY: lua_pushliteral(L, "wait");  break;
    case SDL_IO_STATUS_READONLY:
    case SDL_IO_STATUS_WRITEONLY: SDL_assert(true && "unreachable code"); break;
  }

  return lua_gettop(L) - top;
}

static int f_close_stream(lua_State* L) {
  lua_settop(L, 2);
  SDL_Process *proc = GET_PROCESS(L, 1);
  SDL_assert(proc != NULL);

  SDL_PropertiesID props = SDL_GetProcessProperties(proc);
  if (!props)
    return luaL_error(L, "cannot close stream: %s", SDL_GetError());

  SDL_IOStream *stream = SDL_GetPointerProperty(props, enum_sdl_stream_type[luaL_checkoption(L, 2, NULL, enum_stream_type)], NULL);
  if (!stream)
    return luaL_error(L, "cannot close stream: %s", SDL_GetError());

  lua_pushboolean(L, SDL_CloseIO(stream));
  if (!lua_toboolean(L, -1))
    lua_pushstring(L, SDL_GetError());

  return lua_gettop(L) - 2;
}

static int f_tostring(lua_State* L) {
  lua_pushliteral(L, API_TYPE_PROCESS);
  return 1;
}

static int f_pid(lua_State* L) {
  SDL_Process *proc = GET_PROCESS(L, 1);
  SDL_assert(proc != NULL);

  SDL_PropertiesID props = SDL_GetProcessProperties(proc);
  if (!props)
    return luaL_error(L, "cannot get PID: %s", SDL_GetError());

  lua_pushinteger(L, SDL_GetNumberProperty(props, SDL_PROP_PROCESS_PID_NUMBER, 0));
  return 1;
}

static int f_returncode(lua_State *L) {
  SDL_Process *proc = GET_PROCESS(L, 1);
  SDL_assert(proc != NULL);

  int exitcode = 0;
  if (!SDL_WaitProcess(proc, false, &exitcode))
    return luaL_error(L, "cannot get return code: %s", SDL_GetError());

  // god knows this will work since this is not explicitly worked around on windows
  lua_pushinteger(L, exitcode);
  return 1;
}

static int f_read_stdout(lua_State* L) {
  return g_read(L, STREAM_STDOUT, luaL_optinteger(L, 2, READ_BUF_SIZE));
}

static int f_read_stderr(lua_State* L) {
  return g_read(L, STREAM_STDERR, luaL_optinteger(L, 2, READ_BUF_SIZE));
}

static int f_read(lua_State* L) {
  return g_read(L, luaL_checkoption(L, 2, NULL, enum_stream_type), luaL_optinteger(L, 3, READ_BUF_SIZE));
}

static int f_wait(lua_State* L) {
  return f_returncode(L);
}

static int g_signal(lua_State* L, signal_e sig) {
  SDL_Process *proc = GET_PROCESS(L, 1);
  SDL_assert(proc != NULL);

  switch (sig) {
    case SIGNAL_TERM: SDL_KillProcess(proc, false); break;
    case SIGNAL_KILL: SDL_KillProcess(proc, true); break;
    case SIGNAL_INTERRUPT: {
#if defined(SDL_PLATFORM_UNIX)
      SDL_PropertiesID props = SDL_GetProcessProperties(proc);
      if (!props)
        return luaL_error(L, "cannot kill process: %s", SDL_GetError());
      int pid = SDL_GetNumberProperty(props, SDL_PROP_PROCESS_PID_NUMBER, 0);
      if (pid == 0)
        return luaL_error(L, "cannot kill process: cannot get PID");
      kill(-pid);
#elif defined(SDL_PLATFORM_WINDOWS)

#endif
    }
  }
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
  signal_process(self, sig);
  lua_pushboolean(L, 1);
  return 1;
}
static int f_terminate(lua_State* L) { return g_signal(L, SIGNAL_TERM); }
static int f_kill(lua_State* L) { return g_signal(L, SIGNAL_KILL); }
static int f_interrupt(lua_State* L) { return g_signal(L, SIGNAL_INTERRUPT); }

static int f_gc(lua_State* L) {
  process_kill_list_t *list = NULL;
  process_kill_t *p = NULL;
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);

  // get the kill_list for the lua_State
  if (lua_getfield(L, LUA_REGISTRYINDEX, PROCESS_KILL_LIST_NAME) == LUA_TUSERDATA)
    list = (process_kill_list_t *) lua_touserdata(L, -1);

  if (poll_process(self, 0) && !self->detached) {
    // attempt to kill the process if still running and not detached
    signal_process(self, SIGNAL_TERM);
    if (!list || !list->worker_thread || !(p = SDL_malloc(sizeof(process_kill_t)))) {
      // use synchronous waiting
      if (poll_process(self, PROCESS_TERM_DELAY)) {
        signal_process(self, SIGNAL_KILL);
        poll_process(self, PROCESS_TERM_DELAY);
      }
    } else {
      // put the handle into a queue for asynchronous waiting
      p->handle = PROCESS_GET_HANDLE(self);
      p->start_time = SDL_GetTicks();
      p->tries = 1;
      SDL_LockMutex(list->mutex);
      kill_list_push(list, p);
      SDL_SignalCondition(list->has_work);
      SDL_UnlockMutex(list->mutex);
    }
  }
  close_fd(&self->child_pipes[STDIN_FD ][1]);
  close_fd(&self->child_pipes[STDOUT_FD][0]);
  close_fd(&self->child_pipes[STDERR_FD][0]);
  return 0;
}

static int f_running(lua_State* L) {
  process_t* self = (process_t*)luaL_checkudata(L, 1, API_TYPE_PROCESS);
  lua_pushboolean(L, poll_process(self, WAIT_NONE));
  return 1;
}

static int process_gc(lua_State *L) {
  process_kill_list_t *list = NULL;
  // get the kill_list for the lua_State
  if (lua_getfield(L, LUA_REGISTRYINDEX, PROCESS_KILL_LIST_NAME) == LUA_TUSERDATA) {
    list = (process_kill_list_t *) lua_touserdata(L, -1);
    kill_list_wait_all(list);
    kill_list_free(list);
  }
  return 0;
}

static const struct luaL_Reg process_metatable[] = {
  {"__gc", f_gc},
  {"__tostring", f_tostring},
  {"pid", f_pid},
  {"returncode", f_returncode},
  {"read", f_read},
  {"read_stdout", f_read_stdout},
  {"read_stderr", f_read_stderr},
  {"write", f_write},
  {"close_stream", f_close_stream},
  {"wait", f_wait},
  {"terminate", f_terminate},
  {"kill", f_kill},
  {"interrupt", f_interrupt},
  {"running", f_running},
  {NULL, NULL}
};

static const struct luaL_Reg lib[] = {
  { "start", process_start },
  { "strerror", process_strerror },
  { NULL, NULL }
};

int luaopen_process(lua_State *L) {
  process_kill_list_t *list = lua_newuserdata(L, sizeof(process_kill_list_t));
  if (kill_list_init(list))
    lua_setfield(L, LUA_REGISTRYINDEX, PROCESS_KILL_LIST_NAME);
  else
    lua_pop(L, 1); // discard the list

  // create the process metatable
  luaL_newmetatable(L, API_TYPE_PROCESS);
  luaL_setfuncs(L, process_metatable, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");

  // create the process library
  luaL_newlib(L, lib);
  lua_newtable(L);
  lua_pushcfunction(L, process_gc);
  lua_setfield(L, -2, "__gc");
  lua_setmetatable(L, -2);

  API_CONSTANT_DEFINE(L, -1, "WAIT_INFINITE", WAIT_INFINITE);
  API_CONSTANT_DEFINE(L, -1, "WAIT_DEADLINE", WAIT_DEADLINE);

  API_CONSTANT_DEFINE(L, -1, "REDIRECT_DEFAULT", REDIRECT_DEFAULT);
  API_CONSTANT_DEFINE(L, -1, "REDIRECT_STDOUT", STDOUT_FD);
  API_CONSTANT_DEFINE(L, -1, "REDIRECT_STDERR", STDERR_FD);
  API_CONSTANT_DEFINE(L, -1, "REDIRECT_PARENT", REDIRECT_PARENT); // Redirects to parent's STDOUT/STDERR
  API_CONSTANT_DEFINE(L, -1, "REDIRECT_DISCARD", REDIRECT_DISCARD); // Closes the filehandle, discarding it.

  return 1;
}
