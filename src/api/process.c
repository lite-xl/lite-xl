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
    OVERLAPPED overlapped[2];
    bool reading[2];
    char buffer[2][READ_BUF_SIZE];
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
  STDERR_FD,
  // Special values for redirection.
  REDIRECT_DEFAULT = -1,
  REDIRECT_DISCARD = -2,
  REDIRECT_PARENT = -3,
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
  const char *cmd[256], *env[256] = { NULL }, *cwd = NULL;
  bool detach = false;
  int deadline = 10, new_fds[3] = { STDIN_FD, STDOUT_FD, STDERR_FD };
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
    lua_getfield(L, 2, "detach");  detach = lua_toboolean(L, -1);
    lua_getfield(L, 2, "timeout"); deadline = luaL_optnumber(L, -1, deadline);
    lua_getfield(L, 2, "cwd");     cwd = luaL_optstring(L, -1, NULL);
    lua_getfield(L, 2, "stdin");   new_fds[STDIN_FD] = luaL_optnumber(L, -1, STDIN_FD);
    lua_getfield(L, 2, "stdout");  new_fds[STDOUT_FD] = luaL_optnumber(L, -1, STDOUT_FD);
    lua_getfield(L, 2, "stderr");  new_fds[STDERR_FD] = luaL_optnumber(L, -1, STDERR_FD);
    for (int stream = STDIN_FD; stream <= STDERR_FD; ++stream) {
      if (new_fds[stream] > STDERR_FD || new_fds[stream] < REDIRECT_PARENT)
        return luaL_error(L, "redirect to handles, FILE* and paths are not supported");
    }
  }
  env[env_len] = NULL;
  
  process_t* self = lua_newuserdata(L, sizeof(process_t));
  memset(self, 0, sizeof(process_t));
  luaL_setmetatable(L, API_TYPE_PROCESS);
  self->deadline = deadline;
  #if _WIN32
    for (int i = 0; i < 3; ++i) {
      switch (new_fds[i]) {
        case REDIRECT_PARENT:
          switch (i) {
            case STDIN_FD: self->child_pipes[i][0] = GetStdHandle(STD_INPUT_HANDLE); break;
            case STDOUT_FD: self->child_pipes[i][1] = GetStdHandle(STD_OUTPUT_HANDLE); break;
            case STDERR_FD: self->child_pipes[i][1] = GetStdHandle(STD_ERROR_HANDLE); break;
          }
          self->child_pipes[i][i == STDIN_FD ? 1 : 0] = INVALID_HANDLE_VALUE;
        break;
        case REDIRECT_DISCARD: 
          self->child_pipes[i][0] = INVALID_HANDLE_VALUE; 
          self->child_pipes[i][1] = INVALID_HANDLE_VALUE; 
        break;
        default: {
          if (new_fds[i] == i) {
            char pipeNameBuffer[MAX_PATH];
            sprintf(pipeNameBuffer, "\\\\.\\Pipe\\RemoteExeAnon.%08lx.%08lx", GetCurrentProcessId(), InterlockedIncrement(&PipeSerialNumber));
            self->child_pipes[i][0] = CreateNamedPipeA(pipeNameBuffer, PIPE_ACCESS_INBOUND | FILE_FLAG_OVERLAPPED,
              PIPE_TYPE_BYTE | PIPE_WAIT, 1, READ_BUF_SIZE, READ_BUF_SIZE, 0, NULL);
            if (!self->child_pipes[i][0])
              return luaL_error(L, "Error creating read pipe: %d.", GetLastError());
            self->child_pipes[i][1] = CreateFileA(pipeNameBuffer, GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
            if (self->child_pipes[i][1] == INVALID_HANDLE_VALUE) {
              CloseHandle(self->child_pipes[i][0]);
              return luaL_error(L, "Error creating write pipe: %d.", GetLastError());
            }
            if (!SetHandleInformation(self->child_pipes[i][i == STDIN_FD ? 1 : 0], HANDLE_FLAG_INHERIT, 0) ||
                !SetHandleInformation(self->child_pipes[i][i == STDIN_FD ? 0 : 1], HANDLE_FLAG_INHERIT, 1))
                  return luaL_error(L, "Error inheriting pipes: %d.", GetLastError());
          }
        } break;
      }
    }
    for (int i = 0; i < 3; ++i) {
      if (new_fds[i] != i) {
        self->child_pipes[i][0] = self->child_pipes[new_fds[i]][0];
        self->child_pipes[i][1] = self->child_pipes[new_fds[i]][1];
      }
    }
    STARTUPINFO siStartInfo;
    memset(&self->process_information, 0, sizeof(self->process_information));
    memset(&siStartInfo, 0, sizeof(siStartInfo));
    siStartInfo.cb = sizeof(siStartInfo);
    siStartInfo.dwFlags |= STARTF_USESTDHANDLES;
    siStartInfo.hStdInput = self->child_pipes[STDIN_FD][0];
    siStartInfo.hStdOutput = self->child_pipes[STDOUT_FD][1];
    siStartInfo.hStdError = self->child_pipes[STDERR_FD][1];
    char commandLine[32767] = { 0 }, environmentBlock[32767];
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
    if (!CreateProcess(NULL, commandLine, NULL, NULL, true, detach ? DETACHED_PROCESS : CREATE_NO_WINDOW, env_len > 0 ? environmentBlock : NULL, cwd, &siStartInfo, &self->process_information))
      return luaL_error(L, "Error creating a process: %d.", GetLastError());
    self->pid = (long)self->process_information.dwProcessId;
    if (detach) 
      CloseHandle(self->process_information.hProcess);
    CloseHandle(self->process_information.hThread);
  #else
    for (int i = 0; i < 3; ++i) { // Make only the parents fd's non-blocking. Children should block.
      if (pipe(self->child_pipes[i]) || fcntl(self->child_pipes[i][i == STDIN_FD ? 1 : 0], F_SETFL, O_NONBLOCK) == -1)
        return luaL_error(L, "Error creating pipes: %s", strerror(errno));
    }
    self->pid = (long)fork();
    if (self->pid < 0) {
      for (int i = 0; i < 3; ++i) {
        close(self->child_pipes[i][0]);
        close(self->child_pipes[i][1]);
      }
      return luaL_error(L, "Error running fork: %s.", strerror(errno));
    } else if (!self->pid) {
      for (int stream = 0; stream < 3; ++stream) {
        if (new_fds[stream] == REDIRECT_DISCARD) { // Close the stream if we don't want it.
          close(self->child_pipes[stream][stream == STDIN_FD ? 0 : 1]);
          close(stream);
        } else if (new_fds[stream] != REDIRECT_PARENT) // Use the parent handles if we redirect to parent.
          dup2(self->child_pipes[new_fds[stream]][new_fds[stream] == STDIN_FD ? 0 : 1], stream);
        close(self->child_pipes[stream][stream == STDIN_FD ? 1 : 0]);
      }
      if ((!detach || setsid() != -1) && (!cwd || chdir(cwd) != -1))
        execvp((const char*)cmd[0], (char* const*)cmd);  
      const char* msg = strerror(errno);
      int result = write(STDERR_FD, msg, strlen(msg)+1);
      exit(result == strlen(msg)+1 ? -1 : -2);
    }
  #endif
  for (size_t i = 0; i < env_len; ++i)
    free((char*)env[i]);
  for (int stream = 0; stream < 3; ++stream)
    close_fd(self->child_pipes[stream][stream == STDIN_FD ? 0 : 1]);
  self->running = true;
  return 1;
}

static int g_read(lua_State* L, int stream, unsigned long read_size) {
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
  long length = 0;
  if (stream != STDOUT_FD && stream != STDERR_FD)
    return luaL_error(L, "redirect to handles, FILE* and paths are not supported");
  #if _WIN32
    if (self->reading[stream] || !ReadFile(self->child_pipes[stream][0], self->buffer[stream], READ_BUF_SIZE, NULL, &self->overlapped[stream])) {
      if (self->reading[stream] || GetLastError() == ERROR_IO_PENDING) {
        self->reading[stream] = true;
        DWORD bytesTransferred = 0;
        if (GetOverlappedResult(self->child_pipes[stream][0], &self->overlapped[stream], &bytesTransferred, false)) {
          self->reading[stream] = false;
          length = bytesTransferred;
        }
      } else {
        signal_process(self, SIGNAL_TERM);
        return 0;
      }
    } else {
      length = self->overlapped[stream].InternalHigh;
    }
    lua_pushlstring(L, self->buffer[stream], length);
  #else
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    uint8_t* buffer = (uint8_t*)luaL_prepbuffer(&b);
    length = read(self->child_pipes[stream][0], buffer, read_size > READ_BUF_SIZE ? READ_BUF_SIZE : read_size);
    if (length == 0 && !poll_process(self, WAIT_NONE))
      return 0;
    else if (length < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
      length = 0;
    if (length < 0) {
      signal_process(self, SIGNAL_TERM);
      return 0;
    }
    luaL_addsize(&b, length);
    luaL_pushresult(&b);
  #endif
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
    if (length < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
      length = 0;
  #endif
  if (length < 0) {
    signal_process(self, SIGNAL_TERM);
    return luaL_error(L, "error writing to process: %s", strerror(errno));
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
  signal_process(self, sig);
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

  API_CONSTANT_DEFINE(L, -1, "WAIT_INFINITE", WAIT_INFINITE);
  API_CONSTANT_DEFINE(L, -1, "WAIT_DEADLINE", WAIT_DEADLINE);

  API_CONSTANT_DEFINE(L, -1, "STREAM_STDIN", STDIN_FD);
  API_CONSTANT_DEFINE(L, -1, "STREAM_STDOUT", STDOUT_FD);
  API_CONSTANT_DEFINE(L, -1, "STREAM_STDERR", STDERR_FD);

  API_CONSTANT_DEFINE(L, -1, "REDIRECT_DEFAULT", REDIRECT_DEFAULT);
  API_CONSTANT_DEFINE(L, -1, "REDIRECT_STDOUT", STDOUT_FD); 
  API_CONSTANT_DEFINE(L, -1, "REDIRECT_STDERR", STDERR_FD);
  API_CONSTANT_DEFINE(L, -1, "REDIRECT_PARENT", REDIRECT_PARENT); // Redirects to parent's STDOUT/STDERR
  API_CONSTANT_DEFINE(L, -1, "REDIRECT_DISCARD", REDIRECT_DISCARD); // Closes the filehandle, discarding it.

  return 1;
}
