#include "api.h"

#include <string.h>
#include <stdbool.h>
#include <stdlib.h>
#include <SDL.h>

#if _WIN32
  // https://stackoverflow.com/questions/60645/overlapped-i-o-on-anonymous-pipe
  // https://docs.microsoft.com/en-us/windows/win32/procthread/creating-a-child-process-with-redirected-input-and-output
  #include <windows.h> 
#else
  #include <errno.h>
  #include <unistd.h>
  #include <signal.h>
  #include <fcntl.h>
  #include <sys/types.h>
  #include <sys/wait.h>
#endif

#define READ_BUF_SIZE 2048

typedef struct {
  bool running;
  int returncode, deadline;
  long pid;
  #if _WIN32
    PROCESS_INFORMATION process_information;
    HANDLE child_pipes[3][2];
  #else
    int child_pipes[3][2];
  #endif
} process_t;

typedef enum {
  SIGNAL_KILL,
  SIGNAL_TERM,
  SIGNAL_BREAK
} signal_e;

typedef enum {
  WAIT_NONE     = 0,
  WAIT_DEADLINE = -1,
  WAIT_INFINITE = -2
} wait_e;

typedef enum {
  STDIN_FD,
  STDOUT_FD,
  STDERR_FD
} filed_e;

#ifdef _WIN32
  static volatile long PipeSerialNumber;
  static void close_fd(HANDLE handle) { CloseHandle(handle); }
#else
  static void close_fd(int fd) { close(fd); }
#endif

static bool poll_process(process_t* proc, int timeout) {
  if (!proc->running)
    return false;
  unsigned int ticks = SDL_GetTicks();
  if (timeout == WAIT_DEADLINE)
    timeout = proc->deadline;
  do {
    #ifdef _WIN32
      DWORD exit_code = -1;
      if (!GetExitCodeProcess( proc->process_information.hProcess, &exit_code ) || exit_code != STILL_ACTIVE) {
        proc->returncode = exit_code;
        proc->running = false;
        break;
      }
    #else
      int status;
      pid_t wait_response = waitpid(proc->pid, &status, WNOHANG);
      if (wait_response != 0) {
        proc->running = false;
        proc->returncode = WEXITSTATUS(status);
        break;
      }
    #endif
    if (timeout)
      SDL_Delay(5);
  } while (timeout == WAIT_INFINITE || SDL_GetTicks() - ticks < timeout);
  if (!proc->running) {
    close_fd(proc->child_pipes[STDIN_FD ][1]);
    close_fd(proc->child_pipes[STDOUT_FD][0]);
    close_fd(proc->child_pipes[STDERR_FD][0]);
    return false;
  }
  return true;
}

static bool signal_process(process_t* proc, signal_e sig) {
  bool terminate = false;
  #if _WIN32
    switch(sig) {
      case SIGNAL_TERM: terminate = GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, GetProcessId(proc->process_information.hProcess)); break;
      case SIGNAL_KILL: terminate = TerminateProcess(proc->process_information.hProcess, -1); break;
      case SIGNAL_BREAK: DebugBreakProcess(proc->process_information.hProcess); break;
    }
  #else
    switch (sig) {
      case SIGNAL_TERM: terminate = kill(proc->pid, SIGTERM) == 1; break;
      case SIGNAL_KILL: terminate = kill(proc->pid, SIGKILL) == 1; break;
      case SIGNAL_BREAK: kill(proc->pid, SIGINT); break;
    }
  #endif
  if (terminate) 
    poll_process(proc, WAIT_NONE);
  return true;
}

static int process_start(lua_State* L) {
  size_t env_len = 0, key_len, val_len;
  const char *cmd[256], *env[256] = { NULL };
  bool detach = false;
  luaL_checktype(L, 1, LUA_TTABLE);
  #if LUA_VERSION_NUM > 501
    lua_len(L, 1);
  #else
    lua_pushnumber(L, (int)lua_objlen(L, 1));
  #endif
  size_t cmd_len = luaL_checknumber(L, -1); lua_pop(L, 1);
  size_t arg_len = lua_gettop(L);
  for (size_t i = 1; i <= cmd_len; ++i) {
    lua_pushnumber(L, i);
    lua_rawget(L, 1);
    cmd[i-1] = luaL_checkstring(L, -1);
  }
  cmd[cmd_len] = NULL;
  if (arg_len > 1) {
    lua_getfield(L, 2, "env");
    if (!lua_isnil(L, -1)) {
      lua_pushnil(L); 
      while (lua_next(L, -2) != 0) {
        const char* key = luaL_checklstring(L, -2, &key_len);
        const char* val = luaL_checklstring(L, -1, &val_len);
        env[env_len] = malloc(key_len+val_len+2);
        snprintf((char*)env[env_len++], key_len+val_len+2, "%s=%s", key, val);
        lua_pop(L, 1);
      }
    } else
      lua_pop(L, 1);
    lua_getfield(L, 2, "detach");
    detach = lua_toboolean(L, -1);
      
  }
  env[env_len] = NULL;
  
  process_t* self = lua_newuserdata(L, sizeof(process_t));
  luaL_setmetatable(L, API_TYPE_PROCESS);
  self->deadline = 10;
  #if _WIN32
    char pipeNameBuffer[MAX_PATH];
    for (int i = 0; i < 3; ++i) {
      sprintf(pipeNameBuffer, "\\\\.\\Pipe\\RemoteExeAnon.%08lx.%08lx", GetCurrentProcessId(), InterlockedIncrement(&PipeSerialNumber));
      HANDLE readPipeHandle = CreateNamedPipeA(pipeNameBuffer, PIPE_ACCESS_INBOUND | FILE_FLAG_OVERLAPPED,
        PIPE_TYPE_BYTE | PIPE_WAIT, 1, READ_BUF_SIZE, READ_BUF_SIZE, 120 * 1000, NULL);
      if (!readPipeHandle)
        return luaL_error(L, "Error creating read pipe.");
      HANDLE writePipeHandle = CreateFileA(pipeNameBuffer, GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OVERLAPPED, NULL);
      if (writePipeHandle == INVALID_HANDLE_VALUE) {
        CloseHandle(readPipeHandle);
        return luaL_error(L, "Error creating write pipe.");
      }
      self->child_pipes[i][0] = readPipeHandle;
      self->child_pipes[i][1] = writePipeHandle;
    }
    if (!SetHandleInformation(self->child_pipes[STDIN_FD ][1], HANDLE_FLAG_INHERIT, 0) ||
        !SetHandleInformation(self->child_pipes[STDOUT_FD][0], HANDLE_FLAG_INHERIT, 0) ||
        !SetHandleInformation(self->child_pipes[STDERR_FD][0], HANDLE_FLAG_INHERIT, 0)
    )
      return luaL_error(L, "Error inheriting pipes.");
    STARTUPINFO siStartInfo;
    memset(&self->process_information, 0, sizeof(self->process_information));
    memset(&siStartInfo, 0, sizeof(siStartInfo));
    siStartInfo.cb = sizeof(siStartInfo);
    siStartInfo.hStdError = self->child_pipes[STDERR_FD][1];
    siStartInfo.hStdOutput = self->child_pipes[STDOUT_FD][1];
    siStartInfo.hStdInput = self->child_pipes[STDIN_FD][0];
    char commandLine[32767] = { 0 };
    char environmentBlock[32767];
    int offset = 0;
    strcpy(commandLine, cmd[0]);
    for (size_t i = 1; i < arg_len; ++i) {
      size_t len = strlen(cmd[i]);
      if (offset + len + 1 >= sizeof(commandLine))
        break;
      strcat(commandLine, " ");
      strcat(commandLine, cmd[i]);
    }
    for (size_t i = 0; i < env_len; ++i) {
      size_t len = strlen(env[i]);
      if (offset + len >= sizeof(environmentBlock))
        break;
      memcpy(&environmentBlock[offset], env[i], len);
      offset += len;
      environmentBlock[offset++] = 0;
    }
    environmentBlock[offset++] = 0;
    if (!CreateProcess(NULL, commandLine, NULL, NULL, true, detach ? DETACHED_PROCESS : 0, env_len > 0 ? environmentBlock : NULL, NULL, &siStartInfo, &self->process_information))
      return luaL_error(L, "Error creating a process: %d.", GetLastError());
    self->pid = (long)self->process_information.dwProcessId;
    if (detach) 
      CloseHandle(self->process_information.hProcess);
    CloseHandle(self->process_information.hThread);
  #else
    for (int i = 0; i < 3; ++i) {
      if (pipe(self->child_pipes[i]) || fcntl(self->child_pipes[i][0], F_SETFL, O_NONBLOCK) == -1 || fcntl(self->child_pipes[i][1], F_SETFL, O_NONBLOCK) == -1)
        return luaL_error(L, "Error creating pipes: %d", errno);
    }
    self->pid = (long)fork();
    if (self->pid < 0) {
      for (int i = 0; i < 3; ++i) {
        close(self->child_pipes[i][0]);
        close(self->child_pipes[i][1]);
      }
      return luaL_error(L, "Error running fork: %d.", self->pid);
    } else if (!self->pid) {
      dup2(self->child_pipes[STDOUT_FD][1], STDOUT_FD);
      dup2(self->child_pipes[STDERR_FD][1], STDERR_FD);
      dup2(self->child_pipes[STDIN_FD ][0], STDIN_FD);
      close(self->child_pipes[STDIN_FD ][1]);
      close(self->child_pipes[STDOUT_FD][0]);
      close(self->child_pipes[STDERR_FD][0]);
      if (detach)
        setsid();
      execvp((const char*)cmd[0], (char* const*)cmd);
      const char* message = strerror(errno);
      int result = write(STDERR_FD, message, strlen(message)+1);
      exit(result == strlen(message)+1 ? -1 : -2);
    }
  #endif
  for (size_t i = 0; i < env_len; ++i)
    free((char*)env[i]);
  close_fd(self->child_pipes[STDIN_FD ][0]);
  close_fd(self->child_pipes[STDOUT_FD][1]);
  close_fd(self->child_pipes[STDERR_FD][1]);
  self->running = true;
  return 1;
}

static int g_read(lua_State* L, int stream, unsigned long read_size) {
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
  if (stream != STDOUT_FD && stream != STDERR_FD)
    return luaL_error(L, "redirect to handles, FILE* and paths are not supported");
  if (read_size > LUAL_BUFFERSIZE)
    return luaL_error(L, "can only read a maximum of %d at once", LUAL_BUFFERSIZE);
  luaL_Buffer b;
  luaL_buffinit(L, &b);
  uint8_t* buffer = (uint8_t*)luaL_prepbuffer(&b);
  long length;
  #if _WIN32
    DWORD dwRead;
    length = ReadFile(self->child_pipes[stream][0], buffer, read_size, &dwRead, NULL) ? dwRead : -1;
  #else
    length = read(self->child_pipes[stream][0], buffer, read_size);
    if (length == 0 && !poll_process(self, WAIT_NONE))
      return 0;
    else if (length < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
      length = 0;
  #endif
  if (length < 0) {
    signal_process(self, SIGNAL_TERM);
    return 0;
  } 
  luaL_addsize(&b, length);
  luaL_pushresult(&b);
  return 1;
}

static int f_write(lua_State* L) {
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
  size_t data_size = 0;
  const char* data = luaL_checklstring(L, 2, &data_size);
  long length;
  #if _WIN32
    DWORD dwWritten;
    length = WriteFile(self->child_pipes[STDIN_FD][1], data, data_size, &dwWritten, NULL) ? dwWritten : -1;
  #else
    length = write(self->child_pipes[STDIN_FD][1], data, data_size);
    if (length < 0)
      perror(NULL);
    if (length < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
      length = 0;
  #endif
  if (length < 0) {
    signal_process(self, SIGNAL_TERM);
    return 0;
  }
  lua_pushnumber(L, length);
  return 1;
}

static int f_close_stream(lua_State* L) {
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
  int stream = luaL_checknumber(L, 2);
  close_fd(self->child_pipes[stream][stream == STDIN_FD ? 1 : 0]);
  lua_pushboolean(L, 1);
  return 1;
}

// Generic stuff below here.
static int process_strerror(lua_State* L) {
  int error_code = luaL_checknumber(L, 1);
  if (error_code < 0)
    lua_pushstring(L, strerror(error_code));
  else
    lua_pushnil(L);
  return 1;
}

static int f_tostring(lua_State* L) {
  lua_pushliteral(L, API_TYPE_PROCESS);
  return 1;
}

static int f_pid(lua_State* L) {
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
  lua_pushnumber(L, self->pid);
  return 1;
}

static int f_returncode(lua_State *L) {
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
  if (self->running)
    return 0;
  lua_pushnumber(L, self->returncode);
  return 1;
}

static int f_read_stdout(lua_State* L) {
  return g_read(L, STDOUT_FD, luaL_optinteger(L, 2, READ_BUF_SIZE));
}

static int f_read_stderr(lua_State* L) {
  return g_read(L, STDERR_FD, luaL_optinteger(L, 2, READ_BUF_SIZE));
}

static int f_read(lua_State* L) {
  return g_read(L, luaL_checknumber(L, 2), luaL_optinteger(L, 3, READ_BUF_SIZE));
}

static int f_wait(lua_State* L) {
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
  int timeout = luaL_optnumber(L, 2, 0);
  if (poll_process(self, timeout))
    return 0;
  lua_pushnumber(L, self->returncode);
  return 1;
}

static int self_signal(lua_State* L, signal_e sig) {
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
  signal_process(self, SIGNAL_TERM);
  lua_pushboolean(L, 1);
  return 1;
}
static int f_terminate(lua_State* L) { return self_signal(L, SIGNAL_TERM); }
static int f_kill(lua_State* L) { return self_signal(L, SIGNAL_KILL); }
static int f_break(lua_State* L) { return self_signal(L, SIGNAL_BREAK); }
static int f_gc(lua_State* L) { return self_signal(L, SIGNAL_TERM); }

static int f_running(lua_State* L) {
  process_t* self = (process_t*)luaL_checkudata(L, 1, API_TYPE_PROCESS);  
  lua_pushboolean(L, self->running);
  return 1;
}

static const struct luaL_Reg lib[] = {
  {"__gc", f_gc},
  {"__tostring", f_tostring},
  {"start", process_start},
  {"strerror", process_strerror},
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
  {"break", f_break},
  {"running", f_running},
  {NULL, NULL}
};

int luaopen_process(lua_State *L) {
  luaL_newmetatable(L, API_TYPE_PROCESS);
  luaL_setfuncs(L, lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");

  // constants
  API_CONSTANT_DEFINE(L, -1, "ERROR_INVAL", -1);
  API_CONSTANT_DEFINE(L, -1, "ERROR_TIMEDOUT", -2);
  API_CONSTANT_DEFINE(L, -1, "ERROR_PIPE", -3);
  API_CONSTANT_DEFINE(L, -1, "ERROR_NOMEM", -4);
  API_CONSTANT_DEFINE(L, -1, "ERROR_WOULDBLOCK", -4);

  API_CONSTANT_DEFINE(L, -1, "WAIT_INFINITE", WAIT_INFINITE);
  API_CONSTANT_DEFINE(L, -1, "WAIT_DEADLINE", WAIT_DEADLINE);

  API_CONSTANT_DEFINE(L, -1, "STREAM_STDIN", STDIN_FD);
  API_CONSTANT_DEFINE(L, -1, "STREAM_STDOUT", STDOUT_FD);
  API_CONSTANT_DEFINE(L, -1, "STREAM_STDERR", STDERR_FD);

  API_CONSTANT_DEFINE(L, -1, "REDIRECT_DEFAULT", 0);
  API_CONSTANT_DEFINE(L, -1, "REDIRECT_PIPE", 1);
  API_CONSTANT_DEFINE(L, -1, "REDIRECT_PARENT", 2);
  API_CONSTANT_DEFINE(L, -1, "REDIRECT_DISCARD", 4);
  API_CONSTANT_DEFINE(L, -1, "REDIRECT_STDOUT", 8);

  return 1;
}
