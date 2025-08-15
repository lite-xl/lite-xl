#include "api.h"

#include <string.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <SDL3/SDL.h>
#include <SDL3/SDL_thread.h>
#include <assert.h>

#if _WIN32
  // https://stackoverflow.com/questions/60645/overlapped-i-o-on-anonymous-pipe
  // https://docs.microsoft.com/en-us/windows/win32/procthread/creating-a-child-process-with-redirected-input-and-output
  #include <windows.h>
  #include "../utfconv.h"
#else
  #include <errno.h>
  #include <unistd.h>
  #include <signal.h>
  #include <fcntl.h>
  #include <sys/types.h>
  #include <sys/wait.h>
#endif

#include "../arena_allocator.h"

#define READ_BUF_SIZE 2048
#define PROCESS_TERM_TRIES 3
#define PROCESS_TERM_DELAY 50
#define PROCESS_KILL_LIST_NAME "__process_kill_list__"

#if _WIN32

typedef DWORD process_error_t;
typedef HANDLE process_stream_t;
typedef HANDLE process_handle_t;
typedef wchar_t process_arglist_t[32767];
typedef wchar_t *process_env_t;

#define HANDLE_INVALID (INVALID_HANDLE_VALUE)
#define PROCESS_GET_HANDLE(P) ((P)->process_information.hProcess)
#define PROCESS_ARGLIST_INITIALIZER { 0 }

static volatile long PipeSerialNumber;

#else

typedef int process_error_t;
typedef int process_stream_t;
typedef pid_t process_handle_t;
typedef char **process_arglist_t;
typedef char **process_env_t;

#define HANDLE_INVALID (0)
#define PROCESS_GET_HANDLE(P) ((P)->pid)
#define PROCESS_ARGLIST_INITIALIZER NULL

#endif

#ifdef __GNUC__
#define UNUSED __attribute__((__unused__))
#else
#define UNUSED
#endif

typedef struct {
  bool running, detached;
  int returncode, deadline;
  long pid;
  #if _WIN32
    PROCESS_INFORMATION process_information;
    OVERLAPPED overlapped[2];
    bool reading[2];
    char buffer[2][READ_BUF_SIZE];
  #endif
  process_stream_t child_pipes[3][2];
} process_t;

typedef struct process_kill_s {
  int tries;
  uint32_t start_time;
  process_handle_t handle;
  struct process_kill_s *next;
} process_kill_t;

typedef struct {
  bool stop;
  SDL_Mutex *mutex;
  SDL_Condition *has_work, *work_done;
  SDL_Thread *worker_thread;
  process_kill_t *head;
  process_kill_t *tail;
} process_kill_list_t;

typedef enum {
  SIGNAL_KILL,
  SIGNAL_TERM,
  SIGNAL_INTERRUPT
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

static void close_fd(process_stream_t *handle) {
  if (*handle && *handle != HANDLE_INVALID) {
#ifdef _WIN32
    CloseHandle(*handle);
#else
    close(*handle);
#endif
    *handle = HANDLE_INVALID;
  }
}


static int kill_list_worker(void *ud);


static void kill_list_free(process_kill_list_t *list) {
  process_kill_t *node, *temp;
  SDL_WaitThread(list->worker_thread, NULL);
  SDL_DestroyMutex(list->mutex);
  SDL_DestroyCondition(list->has_work);
  SDL_DestroyCondition(list->work_done);
  node = list->head;
  while (node) {
    temp = node;
    node = node->next;
    SDL_free(temp);
  }
  memset(list, 0, sizeof(process_kill_list_t));
}


static bool kill_list_init(process_kill_list_t *list) {
  memset(list, 0, sizeof(process_kill_list_t));
  list->mutex = SDL_CreateMutex();
  list->has_work = SDL_CreateCondition();
  list->work_done = SDL_CreateCondition();
  list->head = list->tail = NULL;
  list->stop = false;
  if (!list->mutex || !list->has_work || !list->work_done) {
    kill_list_free(list);
    return false;
  }
  list->worker_thread = SDL_CreateThread(kill_list_worker, "process_kill", list);
  if (!list->worker_thread) {
    kill_list_free(list);
    return false;
  }
  return true;
}


static void kill_list_push(process_kill_list_t *list, process_kill_t *task) {
  if (!list) return;
  task->next = NULL;
  if (list->tail) {
    list->tail->next = task;
    list->tail = task;
  } else {
    list->head = list->tail = task;
  }
}


static void kill_list_pop(process_kill_list_t *list) {
  if (!list || !list->head) return;
  process_kill_t *head = list->head;
  list->head = list->head->next;
  if (!list->head) list->tail = NULL;
  head->next = NULL;
}


static void kill_list_wait_all(process_kill_list_t *list) {
  SDL_LockMutex(list->mutex);
  // wait until list is empty
  while (list->head)
    SDL_WaitCondition(list->work_done, list->mutex);
  // tell the worker to stop
  list->stop = true;
  SDL_SignalCondition(list->has_work);
  SDL_UnlockMutex(list->mutex);
}


static void process_handle_close(process_handle_t *handle) {
#ifdef _WIN32
  if (*handle) {
    CloseHandle(*handle);
    *handle = NULL;
  }
#endif
  (void) 0;
}


static bool process_handle_is_running(process_handle_t handle, int *status) {
#ifdef _WIN32
  DWORD s;
  if (GetExitCodeProcess(handle, &s) && s != STILL_ACTIVE) {
    if (status != NULL)
      *status = s;
    return false;
  }
#else
  int s;
  if (waitpid(handle, &s, WNOHANG) != 0) {
    if (status != NULL)
      *status = WEXITSTATUS(s);
    return false;
  }
#endif
  return true;
}


static bool process_handle_signal(process_handle_t handle, signal_e sig) {
#if _WIN32
  switch(sig) {
    case SIGNAL_TERM: return GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, GetProcessId(handle));
    case SIGNAL_KILL: return TerminateProcess(handle, -1);
    case SIGNAL_INTERRUPT: return DebugBreakProcess(handle);
  }
#else
  switch (sig) {
    case SIGNAL_TERM: return kill(-handle, SIGTERM) == 0; break;
    case SIGNAL_KILL: return kill(-handle, SIGKILL) == 0; break;
    case SIGNAL_INTERRUPT: return kill(-handle, SIGINT) == 0; break;
  }
#endif
  return false;
}


static int kill_list_worker(void *ud) {
  process_kill_list_t *list = (process_kill_list_t *) ud;
  process_kill_t *current_task;
  uint32_t delay;

  while (true) {
    SDL_LockMutex(list->mutex);

    // wait until we have work to do
    while (!list->head && !list->stop)
      SDL_WaitCondition(list->has_work, list->mutex); // LOCK MUTEX

    if (list->stop) break;

    while ((current_task = list->head)) {
      if ((SDL_GetTicks() - current_task->start_time) < PROCESS_TERM_DELAY)
        break;
      kill_list_pop(list);
      if (process_handle_is_running(current_task->handle, NULL)) {
        if (current_task->tries < PROCESS_TERM_TRIES)
          process_handle_signal(current_task->handle, SIGNAL_TERM);
        else if (current_task->tries == PROCESS_TERM_TRIES)
          process_handle_signal(current_task->handle, SIGNAL_KILL);
        else
          goto free_task;

        // add the task back into the queue
        current_task->tries++;
        current_task->start_time = SDL_GetTicks();
        kill_list_push(list, current_task);
      } else {
        free_task:
        SDL_SignalCondition(list->work_done);
        process_handle_close(&current_task->handle);
        SDL_free(current_task);
      }
    }
    delay = list->head ? (list->head->start_time + PROCESS_TERM_DELAY) - SDL_GetTicks() : 0;
    SDL_UnlockMutex(list->mutex);
    SDL_Delay(delay);
  }
  SDL_UnlockMutex(list->mutex);
  return 0;
}


static int push_error_string(lua_State *L, process_error_t err) {
#ifdef _WIN32
  char *msg = NULL;
  FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM
                | FORMAT_MESSAGE_ALLOCATE_BUFFER
                | FORMAT_MESSAGE_IGNORE_INSERTS,
                NULL,
                err,
                MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
                (char *) &msg,
                0,
                NULL);
  if (!msg)
    return 0;

  lua_pushstring(L, msg);
  LocalFree(msg);
#else
  lua_pushstring(L, strerror(err));
#endif
  return 1;
}

static void push_error(lua_State *L, const char *extra, process_error_t err) {
  const char *msg = "unknown error";
  extra = extra != NULL ? extra : "error";
  if (push_error_string(L, err))
    msg = lua_tostring(L, -1);
  lua_pushfstring(L, "%s: %s (%d)", extra, msg, err);
}

static bool poll_process(process_t* proc, int timeout) {
  uint32_t ticks;

  if (!proc->running)
    return false;

  if (timeout == WAIT_DEADLINE)
    timeout = proc->deadline;

  ticks = SDL_GetTicks();
  do {
    int status;
    if (!process_handle_is_running(PROCESS_GET_HANDLE(proc), &status)) {
      proc->running = false;
      proc->returncode = status;
      break;
    }
    if (timeout)
      SDL_Delay(timeout >= 5 ? 5 : 0);
  } while (timeout == WAIT_INFINITE || (int)SDL_GetTicks() - ticks < timeout);

  return proc->running;
}

static bool signal_process(process_t* proc, signal_e sig) {
  if (process_handle_signal(PROCESS_GET_HANDLE(proc), sig))
    poll_process(proc, WAIT_NONE);
  return true;
}

static int process_start(lua_State* L) {
  int retval = 1;
  process_t *self = NULL;
  int deadline = 10, detach = false, new_fds[3] = { STDIN_FD, STDOUT_FD, STDERR_FD };

#ifdef _WIN32
  wchar_t *commandline = NULL, *env = NULL, *cwd = NULL;
#else
  const char **cmd = NULL, *env = NULL, *cwd = NULL;
#endif

  lua_settop(L, 3);
  lxl_arena *A = lxl_arena_init(L);
  // copy command line arguments
#ifdef _WIN32
  if ( !(commandline = utfconv_fromutf8(A, luaL_checkstring(L, 1))) )
    return luaL_error(L, "%s", UTFCONV_ERROR_INVALID_CONVERSION);
#else
  luaL_checktype(L, 1, LUA_TTABLE);
  int len = luaL_len(L, 1);
  cmd = lxl_arena_zero(A, (len + 1) * sizeof(char *));
  for (int i = 0; i < len; i++) {
    cmd[i] = lxl_arena_strdup(A, (lua_rawgeti(L, 1, i+1), luaL_checkstring(L, -1)));
  }
#endif

  if (lua_istable(L, 2)) {
    lua_getfield(L, 2, "detach");  detach = lua_toboolean(L, -1);
    lua_getfield(L, 2, "timeout"); deadline = luaL_optnumber(L, -1, deadline);
    lua_getfield(L, 2, "stdin");   new_fds[STDIN_FD] = luaL_optnumber(L, -1, STDIN_FD);
    lua_getfield(L, 2, "stdout");  new_fds[STDOUT_FD] = luaL_optnumber(L, -1, STDOUT_FD);
    lua_getfield(L, 2, "stderr");  new_fds[STDERR_FD] = luaL_optnumber(L, -1, STDERR_FD);
    for (int stream = STDIN_FD; stream <= STDERR_FD; ++stream) {
      if (new_fds[stream] > STDERR_FD || new_fds[stream] < REDIRECT_PARENT)
        return luaL_error(L, "error: redirect to handles, FILE* and paths are not supported");
    }
    lua_pop(L, 5); // pop all the values above

#ifdef _WIN32
    if (lua_getfield(L, 2, "env") == LUA_TFUNCTION) {
      lua_newtable(L);
      LPWCH system_env = GetEnvironmentStringsW(), envp = system_env;
      while (wcslen(envp) > 0) {
        const char *env = utfconv_fromwstr(A, envp), *eq = env ? strchr(env, '=') : NULL;
        if (!env) return (FreeEnvironmentStringsW(system_env), luaL_error(L, "%s", UTFCONV_ERROR_INVALID_CONVERSION));
        if (!eq) return (FreeEnvironmentStringsW(system_env), luaL_error(L, "invalid environment variable"));
        lua_pushlstring(L, env, eq - env); lua_pushstring(L, eq+1);
        lxl_arena_free(A, (void *) env);
        lua_rawset(L, -3);
        envp += wcslen(envp) + 1;
      }
      FreeEnvironmentStringsW(system_env);
      lua_call(L, 1, 1);
      size_t len = 0; const char *env_mb = luaL_checklstring(L, -1, &len);
      if (!(env = utfconv_fromlutf8(A, env_mb, len)))
        return luaL_error(L, "%s", UTFCONV_ERROR_INVALID_CONVERSION);
    }
    if (lua_getfield(L, 2, "cwd"), luaL_optstring(L, -1, NULL)) {
      if ( !(cwd = utfconv_fromutf8(A, lua_tostring(L, -1))) )
        return luaL_error(L, UTFCONV_ERROR_INVALID_CONVERSION);
    }
    lua_pop(L, 2);
#else
    if (lua_getfield(L, 2, "env") == LUA_TFUNCTION) {
      lua_newtable(L);
      lua_call(L, 1, 1);
      size_t len = 0; env = lua_tolstring(L, -1, &len);
      env = lxl_arena_copy(A, (void *) env, len+1);
    }
    cwd = lxl_arena_strdup(A, (lua_getfield(L, 2, "cwd"), luaL_optstring(L, -1, NULL)));
    lua_pop(L, 2);
#endif
  }

  self = lua_newuserdata(L, sizeof(process_t));
  memset(self, 0, sizeof(process_t));
  luaL_setmetatable(L, API_TYPE_PROCESS);
  self->deadline = deadline;
  self->detached = detach;
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
            if (self->child_pipes[i][0] == INVALID_HANDLE_VALUE) {
              push_error(L, "cannot create pipe", GetLastError());
              retval = -1;
              goto cleanup;
            }
            self->child_pipes[i][1] = CreateFileA(pipeNameBuffer, GENERIC_WRITE, 0, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
            if (self->child_pipes[i][1] == INVALID_HANDLE_VALUE) {
              // prevent CloseHandle from messing up error codes
              DWORD err = GetLastError();
              CloseHandle(self->child_pipes[i][0]);
              push_error(L, "cannot open pipe", err);
              retval = -1;
              goto cleanup;
            }
            if (!SetHandleInformation(self->child_pipes[i][i == STDIN_FD ? 1 : 0], HANDLE_FLAG_INHERIT, 0) ||
                !SetHandleInformation(self->child_pipes[i][i == STDIN_FD ? 0 : 1], HANDLE_FLAG_INHERIT, 1)) {
                  push_error(L, "cannot set pipe permission", GetLastError());
                  retval = -1;
                  goto cleanup;
            }
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
    STARTUPINFOW siStartInfo;
    memset(&self->process_information, 0, sizeof(self->process_information));
    memset(&siStartInfo, 0, sizeof(siStartInfo));
    siStartInfo.cb = sizeof(siStartInfo);
    siStartInfo.dwFlags |= STARTF_USESTDHANDLES;
    siStartInfo.hStdInput = self->child_pipes[STDIN_FD][0];
    siStartInfo.hStdOutput = self->child_pipes[STDOUT_FD][1];
    siStartInfo.hStdError = self->child_pipes[STDERR_FD][1];
    if (!CreateProcessW(NULL, commandline, NULL, NULL, true, (detach ? DETACHED_PROCESS : CREATE_NO_WINDOW) | CREATE_UNICODE_ENVIRONMENT, env, cwd, &siStartInfo, &self->process_information)) {
      push_error(L, NULL, GetLastError());
      retval = -1;
      goto cleanup;
    }
    self->pid = (long)self->process_information.dwProcessId;
    if (detach)
      CloseHandle(self->process_information.hProcess);
    CloseHandle(self->process_information.hThread);
  #else
    int control_pipe[2] = { 0 };
    for (int i = 0; i < 3; ++i) { // Make only the parents fd's non-blocking. Children should block.
      if (pipe(self->child_pipes[i]) || fcntl(self->child_pipes[i][i == STDIN_FD ? 1 : 0], F_SETFL, O_NONBLOCK) == -1) {
        push_error(L, "cannot create pipe", errno);
        retval = -1;
        goto cleanup;
      }
    }
    // create a pipe to get the exit code of exec()
    if (pipe(control_pipe) == -1) {
      lua_pushfstring(L, "Error creating control pipe: %s", strerror(errno));
      retval = -1;
      goto cleanup;
    }
    if (fcntl(control_pipe[1], F_SETFD, FD_CLOEXEC) == -1) {
      lua_pushfstring(L, "Error setting FD_CLOEXEC: %s", strerror(errno));
      retval = -1;
      goto cleanup;
    }

    self->pid = (long)fork();
    if (self->pid < 0) {
      push_error(L, "cannot create child process", errno);
      retval = -1;
      goto cleanup;
    } else if (!self->pid) {
      // child process
      if (!detach)
        setpgid(0,0);
      for (int stream = 0; stream < 3; ++stream) {
        if (new_fds[stream] == REDIRECT_DISCARD) { // Close the stream if we don't want it.
          close(self->child_pipes[stream][stream == STDIN_FD ? 0 : 1]);
          close(stream);
        } else if (new_fds[stream] != REDIRECT_PARENT) // Use the parent handles if we redirect to parent.
          dup2(self->child_pipes[new_fds[stream]][new_fds[stream] == STDIN_FD ? 0 : 1], stream);
        close(self->child_pipes[stream][stream == STDIN_FD ? 1 : 0]);
      }
      if (env) {
        size_t len = 0;
        while ((len = strlen(env)) != 0) {
          char *value = strchr(env, '=');
          *value = '\0'; value++; // change the '=' into '\0', forming 2 strings side by side
          setenv(env, value, 1);
          env += len+1;
        }
      }
      if ((!detach || setsid() != -1) && (!cwd || chdir(cwd) != -1))
        execvp(cmd[0], (char** const) cmd);
      write(control_pipe[1], &errno, sizeof(errno));
      _exit(-1);
    }
    // close our write side so we can read from child
    close(control_pipe[1]);
    control_pipe[1] = 0;

    // wait for child process to respond
    int sz, process_rc;
    while ((sz = read(control_pipe[0], &process_rc, sizeof(int))) == -1) {
      if (errno == EPIPE) break;
      if (errno != EINTR) {
        lua_pushfstring(L, "Error getting child process status: %s", strerror(errno));
        retval = -1;
        goto cleanup;
      }
    }

    if (sz) {
      // read something from pipe; exec failed
      int status;
      waitpid(self->pid, &status, 0);
      lua_pushfstring(L, "Error creating child process: %s", strerror(process_rc));
      retval = -1;
      goto cleanup;
    }

  #endif
  cleanup:
  #ifndef _WIN32
    if (control_pipe[0]) close(control_pipe[0]);
    if (control_pipe[1]) close(control_pipe[1]);
  #endif
  if (self) {
    for (int stream = 0; stream < 3; ++stream) {
      process_stream_t* pipe = &self->child_pipes[stream][stream == STDIN_FD ? 0 : 1];
      if (*pipe) {
        close_fd(pipe);
      }
    }
  }

  if (retval == -1)
    return lua_error(L);

  self->running = true;
  return retval;
}

static int g_read(lua_State* L, int stream, lua_Integer read_size) {
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
  long length = 0;
  if (stream != STDOUT_FD && stream != STDERR_FD)
    return luaL_error(L, "error: redirect to handles, FILE* and paths are not supported");
  #if _WIN32
    int writable_stream_idx = stream - 1;
    if (self->reading[writable_stream_idx] || !ReadFile(self->child_pipes[stream][0], self->buffer[writable_stream_idx], read_size > READ_BUF_SIZE ? READ_BUF_SIZE : read_size, NULL, &self->overlapped[writable_stream_idx])) {
      if (self->reading[writable_stream_idx] || GetLastError() == ERROR_IO_PENDING) {
        self->reading[writable_stream_idx] = true;
        DWORD bytesTransferred = 0;
        if (GetOverlappedResult(self->child_pipes[stream][0], &self->overlapped[writable_stream_idx], &bytesTransferred, false)) {
          self->reading[writable_stream_idx] = false;
          length = bytesTransferred;
          memset(&self->overlapped[writable_stream_idx], 0, sizeof(self->overlapped[writable_stream_idx]));
        }
      } else if (GetLastError() != ERROR_HANDLE_EOF || !poll_process(self, WAIT_NONE)) {
        // emulate POSIX behavior in the code below by returning empty string until process exits
        signal_process(self, SIGNAL_TERM);
        return 0;
      }
    } else {
      length = self->overlapped[writable_stream_idx].InternalHigh;
      memset(&self->overlapped[writable_stream_idx], 0, sizeof(self->overlapped[writable_stream_idx]));
    }
    lua_pushlstring(L, self->buffer[writable_stream_idx], length);
  #else
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    do {
      uint8_t* buffer = (uint8_t*)luaL_prepbuffer(&b);
      length = read(self->child_pipes[stream][0], buffer, read_size < LUAL_BUFFERSIZE ? read_size : LUAL_BUFFERSIZE);
      if (length == 0 && !poll_process(self, WAIT_NONE))
        break;
      else if (length < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
        length = 0;
      if (length < 0) {
        signal_process(self, SIGNAL_TERM);
        return 0;
      }
      if (length) {
        luaL_addsize(&b, length);
        read_size -= length;
      }
    } while (read_size > 0 && length > 0);
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
    if (!WriteFile(self->child_pipes[STDIN_FD][1], data, data_size, &dwWritten, NULL)) {
      push_error(L, NULL, GetLastError());
      signal_process(self, SIGNAL_TERM);
      return lua_error(L);
    }
    length = dwWritten;
  #else
    length = write(self->child_pipes[STDIN_FD][1], data, data_size);
    if (length < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
      length = 0;
    else if (length < 0) {
      push_error(L, "cannot write to child process", errno);
      signal_process(self, SIGNAL_TERM);
      return lua_error(L);
    }
  #endif
  lua_pushinteger(L, length);
  return 1;
}

static int f_close_stream(lua_State* L) {
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
  int stream = luaL_checknumber(L, 2);
  close_fd(&self->child_pipes[stream][stream == STDIN_FD ? 1 : 0]);
  lua_pushboolean(L, 1);
  return 1;
}

// Generic stuff below here.
static int process_strerror(lua_State* L) {
  return push_error_string(L, luaL_checknumber(L, 1));
}

static int f_tostring(lua_State* L) {
  lua_pushliteral(L, API_TYPE_PROCESS);
  return 1;
}

static int f_pid(lua_State* L) {
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
  lua_pushinteger(L, self->pid);
  return 1;
}

static int f_returncode(lua_State *L) {
  process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
  if (poll_process(self, WAIT_NONE))
    return 0;
  lua_pushinteger(L, self->returncode);
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
  lua_pushinteger(L, self->returncode);
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
static int f_interrupt(lua_State* L) { return self_signal(L, SIGNAL_INTERRUPT); }

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
