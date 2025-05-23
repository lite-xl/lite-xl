#include "api.h"

#include <SDL3/SDL.h>

#define PROCESS_READ_BUF_SIZE 4096
#define PROCESS_KILL_LIST_NAME "__process_kill_list__"
#define PROCESS_KILL_TRIES 3
#define PROCESS_KILL_DELAY 10
#define PROCESS_KILL_LIST_MIN_SIZE 16
#define PROCESS_PROP_SDL_PTR "lxl.process.SDL_Process.ptr"
#define PROCESS_PROP_KILL_TRIES_NUM "lxl.process.kill_tries.int"

#if defined(SDL_PLATFORM_UNIX)
#include <signal.h>
#elif defined(SDL_PLATFORM_WINDOWS)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

#if !defined(SDL_PROP_PROCESS_CREATE_WORKING_DIRECTORY_STRING) || !defined(SDL_PROP_PROCESS_CREATE_CMDLINE_STRING)
#undef SDL_PROP_PROCESS_CREATE_WORKING_DIRECTORY_STRING
#undef SDL_PROP_PROCESS_CREATE_CMDLINE_STRING
#define SDL_PROP_PROCESS_CREATE_WORKING_DIRECTORY_STRING "TODO"
#define SDL_PROP_PROCESS_CREATE_CMDLINE_STRING "TODO"
#warning SDL_PROP_PROCESS_CREATE_WORKING_DIRECTORY_STRING or SDL_PROP_PROCESS_CREATE_CMDLINE_STRING not supported
#endif

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

static const char *enum_redirect[] = {
  "pipe",
  "parent",
  "discard",
  "stdout",
  NULL
};

typedef enum {
  STREAM_STDIN,
  STREAM_STDOUT,
  STREAM_STDERR,
} stream_type_e;

static const char *enum_read_type[] = { "stdout", "stderr", NULL };
static const char *enum_sdl_read_type[] = {
  SDL_PROP_PROCESS_STDOUT_POINTER,
  SDL_PROP_PROCESS_STDERR_POINTER,
  NULL
};

#if 1 // KILL LIST
typedef struct {
  Uint64 max_idx, cap, size, last_swept;
  SDL_PropertiesID *items;
} kill_list_t;

static bool kill_list_resize(kill_list_t *list, float ratio) {
  size_t new_cap = list->cap * ratio;
  SDL_PropertiesID *new_list = SDL_realloc(list->items, new_cap * sizeof(SDL_PropertiesID));
  if (!new_list)
    return false;
  for (size_t i = list->cap; i < new_cap; i++)
    SDL_zerop(&new_list[i]);
  list->items = new_list;
  list->cap = new_cap;
  return true;
}

static bool kill_list_add(kill_list_t *list, SDL_PropertiesID prop) {
  // attempt to resize list if not sufficient
  if (list->max_idx >= list->cap && !kill_list_resize(list, 1.5f))
    return false;

  list->items[list->max_idx++] = prop;
  list->size++;
  return true;
}

static void kill_list_sweep(kill_list_t *list, bool force) {
  if (SDL_GetTicks() - list->last_swept < PROCESS_KILL_DELAY) return;
  
  // sweep the list, removing processes when they die
  size_t last_idx = 0;
  for (size_t i = 0; i < list->max_idx; i++) {
    if (list->items[i] == 0) break;

    SDL_Process *proc = SDL_GetPointerProperty(list->items[i], PROCESS_PROP_SDL_PTR, NULL);
    SDL_assert(proc != NULL);

    int tries = SDL_GetNumberProperty(list->items[i], PROCESS_PROP_KILL_TRIES_NUM, 0);
    SDL_KillProcess(proc, tries > PROCESS_KILL_TRIES);
    SDL_SetNumberProperty(list->items[i], PROCESS_PROP_KILL_TRIES_NUM, ++tries);

    // if process died or exceeded the amount of tries we can do, just destroy it
    if ((list->items[i] != 0 && tries > PROCESS_KILL_TRIES + 1) || !SDL_WaitProcess(proc, false, NULL)) {
      SDL_DestroyProperties(list->items[i]);
      list->size--;
      if (i < list->max_idx)
        list->items[i] = list->items[i+1];
      else
        SDL_zerop(&list->items[i]);
    }
    
    if (list->items[i] != 0)
      last_idx = i;
  }
  list->max_idx = last_idx + 1;

  // attempt to shrink if utilisation is less than 50% and we just compacted (so everything is on the left)
  if (list->cap > PROCESS_KILL_LIST_MIN_SIZE && ((double) list->max_idx / list->cap) < 0.5)
    kill_list_resize(list, 0.7f);

  list->last_swept = SDL_GetTicks();
}
#endif

#if 1 // CLEANUP
static int f_cleanup_properties(lua_State *L) {
  SDL_PropertiesID id = (lua_rawgeti(L, 1, 1), lua_tointeger(L, -1));
  if (id != 0) SDL_DestroyProperties(id);
  return 0;
}

static void destroy_null_array(void *ud, void *ptr) {
  (void) ud;
  for (void **p = ptr; *p; p++) SDL_free(*p);
  SDL_free(ptr);
}

static void destroy_SDL_Environment(void *ud, void *ptr) {
  (void) ud;
  if (ptr) SDL_DestroyEnvironment((SDL_Environment *) ptr);
}

static void destroy_SDL_Process(void *ud, void *ptr) {
  (void) ud;
  if (ptr) SDL_DestroyProcess((SDL_Process *) ptr);
}
#endif

#define GET_PROCESS(L, idx) \
  SDL_GetPointerProperty(*((SDL_PropertiesID *) luaL_checkudata(L, 1, API_TYPE_PROCESS)), PROCESS_PROP_SDL_PTR, NULL)

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
    return luaL_error(L, "cannot start process: %s", SDL_GetError());
  
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
    SDL_SetPointerPropertyWithCleanup(props, SDL_PROP_PROCESS_CREATE_ARGS_POINTER, cmd, destroy_null_array, NULL);

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
  SDL_SetPointerPropertyWithCleanup(props, SDL_PROP_PROCESS_CREATE_ENVIRONMENT_POINTER, env, destroy_SDL_Environment, NULL);

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
  SDL_SetPointerPropertyWithCleanup(props, PROCESS_PROP_SDL_PTR, proc, destroy_SDL_Process, NULL);

  // clear the to-be-closed slot to prevent it from destroying the process
  lua_pushinteger(L, 0); lua_rawseti(L, to_close, 1);

  *((SDL_PropertiesID *) lua_newuserdata(L, sizeof(SDL_PropertiesID))) = props;
  luaL_setmetatable(L, API_TYPE_PROCESS);

  return 1;
}

static int g_read(lua_State* L, stream_type_e stream_type, size_t read_size) {
  SDL_Process *proc = GET_PROCESS(L, 1);
  SDL_assert(proc != NULL);

  SDL_PropertiesID props = SDL_GetProcessProperties(proc);
  if (!props)
    return luaL_error(L, "cannot read stream: %s", SDL_GetError());

  SDL_IOStream *stream = SDL_GetPointerProperty(props, enum_sdl_read_type[stream_type], NULL);
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
    case SDL_IO_STATUS_READY:     break;
  }

  return lua_gettop(L) - top + 1;
}

static int f_write(lua_State* L) {
  SDL_Process *proc = GET_PROCESS(L, 1);
  SDL_assert(proc != NULL);

  SDL_IOStream *stream = SDL_GetProcessInput(proc);
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
    case SDL_IO_STATUS_READY:     break;
  }

  return lua_gettop(L) - top;
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

static int f_wait(lua_State* L) {
  SDL_Process *proc = GET_PROCESS(L, 1);
  SDL_assert(proc != NULL);
  int exitcode = 0;

  if (SDL_WaitProcess(proc, false, &exitcode))
    return 0;
  
  lua_pushinteger(L, exitcode);
  return 1;
}

static int f_returncode(lua_State *L) {
  return f_wait(L);
}

static int f_read_stdout(lua_State* L) {
  return g_read(L, STREAM_STDOUT, luaL_optinteger(L, 2, PROCESS_READ_BUF_SIZE));
}

static int f_read_stderr(lua_State* L) {
  return g_read(L, STREAM_STDERR, luaL_optinteger(L, 2, PROCESS_READ_BUF_SIZE));
}

static int f_read(lua_State* L) {
  return g_read(L, luaL_checkoption(L, 2, NULL, enum_read_type), luaL_optinteger(L, 3, PROCESS_READ_BUF_SIZE));
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
      kill(-pid, SIGINT);
#elif defined(SDL_PLATFORM_WINDOWS)
      SDL_PropertiesID props = SDL_GetProcessProperties(proc);
      if (!props)
        return luaL_error(L, "cannot kill process: %s", SDL_GetError());
      int pid = SDL_GetNumberProperty(props, SDL_PROP_PROCESS_PID_NUMBER, 0);
      HANDLE proc_handle = OpenProcess(PROCESS_SUSPEND_RESUME, FALSE, pid);
      if (!proc_handle)
        return luaL_error(L, "cannot kill process: OpenProcess() returned %d", GetLastError());
      DebugBreakProcess(proc_handle);
      CloseHandle(proc_handle);
#endif
      break;
    }
  }
  lua_pushboolean(L, 1);
  return 1;
}

static int f_terminate(lua_State* L) { return g_signal(L, SIGNAL_TERM); }
static int f_kill(lua_State* L) { return g_signal(L, SIGNAL_KILL); }
static int f_interrupt(lua_State* L) { return g_signal(L, SIGNAL_INTERRUPT); }

static int f_gc(lua_State* L) {
  SDL_Process *proc = GET_PROCESS(L, 1);
  SDL_assert(proc != NULL);

  SDL_KillProcess(proc, false);
  if (!SDL_WaitProcess(proc, false, NULL))
    goto destroy;

  // add to kill list; if it doesn't exist, fall back to killing them synchronously
  kill_list_t *list = (lua_getfield(L, LUA_REGISTRYINDEX, PROCESS_KILL_LIST_NAME), lua_touserdata(L, -1));
  if (!list || kill_list_add(list, GET_PROCESS_PROP(L, 1)))
    goto fallback;

  return 0;

fallback:
  SDL_KillProcess(proc, true);
  SDL_WaitProcess(proc, true, NULL);
destroy:
  SDL_DestroyProperties(GET_PROCESS_PROP(L, 1));
  return 0;
}

static int f_running(lua_State* L) {
  SDL_Process *proc = GET_PROCESS(L, 1);
  SDL_assert(proc != NULL);

  lua_pushboolean(L, SDL_WaitProcess(proc, false, NULL));
  return 1;
}

static int process_gc(lua_State *L) {
  kill_list_t *list = (lua_getfield(L, LUA_REGISTRYINDEX, PROCESS_KILL_LIST_NAME), lua_touserdata(L, -1));
  if (!list)
    return 0;
  
  // sweep until this list is empty
  while (list->size) {
    kill_list_sweep(list, true);
    SDL_Delay(PROCESS_KILL_DELAY * 1.1f);
  }
  SDL_free(list->items);
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
  {"wait", f_wait},
  {"terminate", f_terminate},
  {"kill", f_kill},
  {"interrupt", f_interrupt},
  {"running", f_running},
  {NULL, NULL}
};

static const struct luaL_Reg lib[] = {
  { "start", process_start },
  { NULL, NULL }
};

int luaopen_process(lua_State *L) {
  kill_list_t *list = lua_newuserdata(L, sizeof(kill_list_t));
  SDL_zerop(list);
  list->items = SDL_calloc(16, sizeof(SDL_PropertiesID));
  if (!list->items)
    lua_pop(L, 1);
  else
    lua_setfield(L, LUA_REGISTRYINDEX, PROCESS_KILL_LIST_NAME);

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

  return 1;
}
