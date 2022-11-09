#include "process.h"

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#ifdef _WIN32
#include <windows.h>
// oh yeah...
#include <wchar.h>
#include <wctype.h>
#else
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#endif

#define READ_BUF_SIZE 4096
#define P_MIN(A, B) ((A) > (B) ? (B) : (A))
#define P_ASSERT_ERR(E, COND) \
  do { \
    if (!(COND)) { \
      retval = (E); \
      goto CLEANUP; \
    } \
  } while (0)
#define P_ASSERT_SYS(COND) P_ASSERT_ERR(-P_SYS_ERRNO, (COND))

#ifdef _WIN32

#define P_SYS_ERRNO (GetLastError())

typedef HANDLE process_handle_t;
#define PROCESS_INVALID_HANDLE INVALID_HANDLE_VALUE

const int PROCESS_EINVAL = -ERROR_INVALID_PARAMETER;
const int PROCESS_ENOMEM = -ERROR_NOT_ENOUGH_MEMORY;
const int PROCESS_EPIPE = -ERROR_BROKEN_PIPE;
const int PROCESS_EWOULDBLOCK = -ERROR_IO_PENDING;

// stolen from linux
const int PROCESS_SIGTERM = 15;
const int PROCESS_SIGINT = 2;
const int PROCESS_SIGKILL = 9;


static void close_handle(process_handle_t *handle) {
  if (*handle != INVALID_HANDLE_VALUE) {
    CloseHandle(*handle);
    *handle = INVALID_HANDLE_VALUE;
  }
}

#else

#define P_SYS_ERRNO (errno)

typedef int process_handle_t;
#define PROCESS_INVALID_HANDLE 0

const int PROCESS_EINVAL = -EINVAL;
const int PROCESS_ENOMEM = -ENOMEM;
const int PROCESS_EPIPE = -EPIPE;
const int PROCESS_EWOULDBLOCK = -EWOULDBLOCK;

const int PROCESS_SIGTERM = SIGTERM;
const int PROCESS_SIGINT = SIGINT;
const int PROCESS_SIGKILL = SIGKILL;

static void close_handle(process_handle_t *handle) {
  if (*handle != 0) {
    close(*handle);
    *handle = 0;
  }
}

#endif

struct process_s {
  bool running, detached;
  int returncode, deadline;
  long pid;
  process_handle_t pipes[3][2];

#if _WIN32
    PROCESS_INFORMATION pi;
    OVERLAPPED overlapped[3];
    bool reading[3];
    // keeps track of how much you can read from buffer
    int remaining[3];
    char buffer[3][READ_BUF_SIZE];
#endif
};

#ifdef _WIN32

static volatile long pipe_serial = 0;

typedef struct {
  wchar_t *key;
  wchar_t *key_eq;
  int len;
} required_env_t;

#define E(KEY) { L##KEY, L##KEY "=", sizeof(KEY) - 1 }

static const required_env_t REQUIRED_ENV[] = {
  E("HOMEDRIVE"),
  E("HOMEPATH"),
  E("LOGONSERVER"),
  E("PATH"),
  E("SYSTEMDRIVE"),
  E("SYSTEMROOT"),
  E("TEMP"),
  E("USERDOMAIN"),
  E("USERNAME"),
  E("USERPROFILE"),
  E("WINDIR"),
};

#else

// use _NSGetEnviron() to get the env var on Apple devices
// this is normally avaiable via extern
// refer to https://github.com/dcreager/libcork/blob/a89596ce224438c136ef0336a81c51262cad9cd3/src/libcork/posix/env.c#L23
#if defined(__APPLE__)
    #pragma message "environ is unavailable. " \
                    "workaround: use _NSGetEnviron()"
    #include <crt_externs.h>
    #define environ (*_NSGetEnviron())
#else
    extern char **environ;
#endif

// use a custom implementation of clearenv(3) if it is unavailable
// refer to https://github.com/dcreager/libcork/blob/a89596ce224438c136ef0336a81c51262cad9cd3/src/libcork/posix/env.c#L190
#if (defined(__APPLE__) || (defined(BSD) && (BSD >= 199103)) || \
    (defined(__CYGWIN__) && CYGWIN_VERSION_API_MINOR < 326)) && \
    !defined(__GNU__)
    #pragma message "clearenv() is unavailable. " \
                    "workaround: self-implemented clearenv()"

    static void clearenv() {
        *environ = NULL;
    }
#endif

#endif

process_t *process_new(void) {
  process_t *self = malloc(sizeof(process_t));
  if (self != NULL) {
    memset(self, 0, sizeof(process_t));
    for (int i = 0; i < 3; i++) {
      self->pipes[i][0] = PROCESS_INVALID_HANDLE;
      self->pipes[i][1] = PROCESS_INVALID_HANDLE;
    }
  }
  return self;
}

#ifdef _WIN32
static int create_lpcmdline(wchar_t *cmdline, const char **argv, bool verbatim) {
  // for lpcmdline, this is 32767 at max
  wchar_t argument[32767];
  int r, arg_len, args_len;
  arg_len = args_len = 0;

  for (int i = 0; argv[i] != NULL; i++) {
    if ((r = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS | MB_PRECOMPOSED,
                                argv[i], -1, argument, 32767)) != 0) {
      // this number includes the trailing \0 characters (assume as space)
      arg_len = r;
      if (!verbatim && wcspbrk(argument, L" \t\n\v\"") != NULL) {
        // argument needs to be quoted
        arg_len += 2;

        int backslashes;
        for (int i = 0; i < r; i++) {
          backslashes = 0;

          // if character is backslash, count number of backslashes after it
          while (i < r && argument[i] == L'\\') {
            backslashes++;
            i++;
          }

          if (argument[i] == L'"')
            arg_len += 2 * backslashes + 1; // 2 * backslashes + 1 backslash
          else
            arg_len += backslashes; // backslashes only
          arg_len++; // the character itself
        }
      }

      if (args_len + arg_len > 32767)
        return 0; // cannot fit in cmdline, abort

      // escape the thing for real this time
      // r includes the trailing \0, now we don't need it anymore
      r--;
      if (!verbatim && wcspbrk(argument, L" \t\n\v\"") != NULL) {

        cmdline[args_len++] = L'"';

        int backslashes;
        for (int i = 0; i < r; i++) {
          backslashes = 0;

          // if character is backslash, count number of backslashes after it
          while (i < r && argument[i] == L'\\') {
            backslashes++;
            i++;
          }

          // insert backslashes
          for (int j = 0; j < (argument[i] == L'"' ? backslashes * 2 + 1 : backslashes); j++)
            cmdline[args_len++] = L'\\';
          cmdline[args_len++] = argument[i];
        }
        cmdline[args_len++] = L'"';
      } else {
        wcsncpy(cmdline + args_len, argument, r);
        args_len += r;
      }
      cmdline[args_len++] = L' ';
    } else {
      return 0;
    }
  }
  // terminate the string
  cmdline[args_len - 1] = L'\0';

  return args_len;
}

static int find_key_len(wchar_t *env) {
  if (env[0] == L'='
      && iswalpha(env[1])
      && env[2] == L':'
      && env[3] == L'=')
  {
    // https://unix.stackexchange.com/a/251215
    return 3;
  } else {
    wchar_t *eq_pos;
    if ((eq_pos = wcschr(env, L'=')) != NULL)
      return eq_pos - env;
    return 0;
  }
}

static int compare_env(wchar_t *a, wchar_t *b) {
  wchar_t a_upper[32767], b_upper[32767];
  wchar_t *a_upper_ptr, *b_upper_ptr;
  int a_key_len, b_key_len;

  a_key_len = find_key_len(a);
  b_key_len = find_key_len(b);
  // the env must include a = as well, so it can't be 32767
  if (a_key_len >= 32767 || b_key_len >= 32767)
    return 0;
  if (LCMapStringW(LOCALE_INVARIANT, LCMAP_UPPERCASE,
                  a, a_key_len, a_upper, a_key_len) == 0)
    return 0;
  if (LCMapStringW(LOCALE_INVARIANT, LCMAP_UPPERCASE,
                  b, b_key_len, b_upper, b_key_len) == 0)
    return 0;
  a_upper[a_key_len] = L'\0';
  b_upper[b_key_len] = L'\0';

  a_upper_ptr = a_upper;
  b_upper_ptr = b_upper;
  for (;;) {
    if (*a_upper_ptr < *b_upper_ptr)
      return -1;
    else if (*a_upper_ptr > *b_upper_ptr)
      return 1;
    else if (!(*a_upper_ptr) && !(*b_upper_ptr))
      return 0;
    a_upper_ptr++;
    b_upper_ptr++;
  }
}

static int find_env(wchar_t *needle, wchar_t **haystack, size_t haystack_size) {
  size_t low = 0, high = haystack_size - 1;
  if (haystack_size == 0) return -1;
  while (low <= high) {
    size_t mid = low + (high - low) / 2;
    int cmp = compare_env(haystack[mid], needle);

    if (cmp == 0)
      return mid;
    else if (cmp < 0)
      low = mid + 1;
    else
      high = mid - 1;
  }
  return -1;
}

static wchar_t *create_lpenvironment(const char **env, bool extend) {
  /**
   * The maximum size of a user-defined environment variable is 32,767 characters.
   * There is no technical limitation on the size of the environment block.
   *
   * Windows Server 2003 and Windows XP: The maximum size of the environment block for
   * the process is 32,767 characters. Starting with Windows Vista
   * and Windows Server 2008, there is no technical limitation on the size of the environment block.
   *
   * TL;DR: an envvar has the maximum size of 32767, the entire block itself (multiple envvar)
   * has no limits.
   */
  wchar_t **env_block = NULL;
  wchar_t *output = NULL;
  wchar_t *parent_env = NULL;
  int r;
  bool fail;
  size_t env_block_len = 0;
  size_t env_block_capacity = 11;
  size_t env_str_len = 0;

  // this code moves the last element to the correct place and resizes
  // the array
#define PUSH_ENV()                                       \
  do {                                                   \
    env_block_len++;                                     \
    for (size_t i = env_block_len - 1; i > 0; i--) {     \
      if (compare_env(env_block[i-1], env_block[i]) < 0) \
        break;                                           \
      wchar_t *tmp = env_block[i-1];                     \
      env_block[i-1] = env_block[i];                     \
      env_block[i] = tmp;                                \
    }                                                    \
    if (env_block_len >= env_block_capacity) {           \
      env_block_capacity *= 1.5;                         \
      wchar_t **_new_env_block = realloc(env_block, env_block_capacity * sizeof(wchar_t*)); \
      if (_new_env_block == NULL)                        \
        goto FAIL;                                       \
      env_block = _new_env_block;                        \
    }                                                    \
  } while (0)

  env_block = malloc(env_block_capacity * sizeof(wchar_t *));
  if (env_block == NULL)
    goto FAIL;

  // copy user envs
  for (size_t i = 0; env[i] != NULL; i++) {
    if ((r = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS | MB_PRECOMPOSED,
                                env[i], -1, NULL, 0)) != 0) {
      if (r > 32767)
        goto FAIL;

      env_block[env_block_len] = malloc(r * sizeof(wchar_t));
      if (env_block[env_block_len] == NULL)
        goto FAIL;

      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS | MB_PRECOMPOSED,
                          env[i], -1, env_block[env_block_len], r);
      if (wcschr(env_block[env_block_len], '=') == NULL) {
        // let FAIL free the newly allocated memory
        env_block_len++;
        goto FAIL; 
      }

      env_str_len += r;
      PUSH_ENV();
    } else {
      goto FAIL;
    }
  }

  // copy parent env
  if (extend) {
    parent_env = GetEnvironmentStringsW();
    wchar_t *parent_env_ptr = parent_env;

    while ((r = wcslen(parent_env_ptr)) > 0) {
      if (find_env(parent_env_ptr, env_block, env_block_len) == -1) {
        // don't have it, copy
        env_block[env_block_len] = malloc((r + 1) * sizeof(wchar_t));
        if (env_block[env_block_len] == NULL)
          goto FAIL;
        // copy (including nul character)
        wcsncpy(env_block[env_block_len], parent_env_ptr, r + 1);
        env_str_len += r + 1;
        PUSH_ENV();
      }
      parent_env_ptr += r + 1;
    }
  }

  // copy the required env too
  for (int i = 0; i < (sizeof(REQUIRED_ENV)/sizeof(*REQUIRED_ENV)); i++) {
    if (find_env(REQUIRED_ENV[i].key_eq, env_block, env_block_len) == -1) {
      if ((r = GetEnvironmentVariableW(REQUIRED_ENV[i].key, NULL, 0)) != 0) {
        r += REQUIRED_ENV[i].len + 1; // key len and the equal sign

        env_block[env_block_len] = malloc(r * sizeof(wchar_t));
        if (env_block[env_block_len] == NULL)
          goto FAIL;

        // copy the key
        wcsncpy(env_block[env_block_len], REQUIRED_ENV[i].key_eq, REQUIRED_ENV[i].len + 1);
        // copy the value
        GetEnvironmentVariableW(REQUIRED_ENV[i].key, env_block[env_block_len] + REQUIRED_ENV[i].len + 1, r);
        env_str_len += r;
        PUSH_ENV();
      } else {
        goto FAIL;
      }
    }
  }

  // copy them into a string
  output = malloc(env_str_len * sizeof(wchar_t));
  if (output == NULL)
    goto FAIL;

  wchar_t *output_ptr = output;
  for (size_t i = 0; i < env_block_len; i++) {
    r = wcslen(env_block[i]) + 1;
    wcsncpy(output_ptr, env_block[i], r);
    output_ptr += r;
  }
  *(output_ptr++) = L'\0';
  goto CLEANUP;

FAIL:
  fail = true;
CLEANUP:
  if (parent_env != NULL)
    FreeEnvironmentStringsW(parent_env);
  for (size_t i = 0; i < env_block_len; i++)
    free(env_block[i]);
  free(env_block);
  if (fail) {
    free(output);
    output = NULL;
  }
  return output;
}
#endif

int process_start(process_t *self,
                  const char **argv, const char *cwd,
                  const char **env, process_env_action_t action,
                  process_redirect_t pipe_redirect[3], int timeout,
                  bool detach, bool verbatim_arguments) {
  int retval = 0;
  process_redirect_t redirect[3];

#ifdef _WIN32
  STARTUPINFOW si;
  wchar_t wcs_cwd[MAX_PATH];
  wchar_t cmdline[32767];
  wchar_t *environment = NULL;
#else
  int env_len = 0;
  int status_pipe[2] = {0};
  char **env_keys = NULL, **env_values = NULL;
#endif

  P_ASSERT_ERR(PROCESS_EINVAL, self != NULL);
  P_ASSERT_ERR(PROCESS_EINVAL, argv != NULL);
  P_ASSERT_ERR(PROCESS_EINVAL, action >= PROCESS_ENV_EXTEND && action <= PROCESS_ENV_REPLACE);
  P_ASSERT_ERR(PROCESS_EINVAL, timeout > PROCESS_DEADLINE);

  self->deadline = timeout;
  self->detached = detach;
  memset(redirect, PROCESS_REDIRECT_DEFAULT, sizeof(redirect));

  if (pipe_redirect != NULL)
    memcpy(redirect, pipe_redirect, sizeof(redirect));

  // normalize
  redirect[PROCESS_STDIN] = redirect[PROCESS_STDIN] == PROCESS_REDIRECT_DEFAULT ? PROCESS_REDIRECT_PIPE : redirect[PROCESS_STDIN];
  redirect[PROCESS_STDOUT] = redirect[PROCESS_STDOUT] == PROCESS_REDIRECT_DEFAULT ? PROCESS_REDIRECT_PIPE : redirect[PROCESS_STDOUT];
  redirect[PROCESS_STDERR] = redirect[PROCESS_STDERR] == PROCESS_REDIRECT_DEFAULT ? PROCESS_REDIRECT_PARENT : redirect[PROCESS_STDERR];

#ifdef _WIN32

  for (int i = 0; i < 3; i++) {
    switch (redirect[i]) {

      case PROCESS_REDIRECT_PARENT:
        switch (i) {
          case PROCESS_STDIN: self->pipes[i][0] = GetStdHandle(STD_INPUT_HANDLE); break;
          case PROCESS_STDOUT: self->pipes[i][1] = GetStdHandle(STD_OUTPUT_HANDLE); break;
          case PROCESS_STDERR: self->pipes[i][1] = GetStdHandle(STD_ERROR_HANDLE); break;
        }
        self->pipes[i][i == PROCESS_STDIN ? 1 : 0] = INVALID_HANDLE_VALUE;
        break;

      case PROCESS_REDIRECT_DISCARD:
        self->pipes[i][0] = self->pipes[i][1] = INVALID_HANDLE_VALUE;
        break;

      case PROCESS_REDIRECT_STDOUT:
        P_ASSERT_ERR(PROCESS_EINVAL, i == PROCESS_STDERR);
        self->pipes[PROCESS_STDERR][0] = self->pipes[PROCESS_STDOUT][0];
        self->pipes[PROCESS_STDERR][1] = self->pipes[PROCESS_STDOUT][1];
        break;

      case PROCESS_REDIRECT_PIPE: {
        char pipe_name[MAX_PATH];
        snprintf(pipe_name, MAX_PATH, "\\\\.\\pipe\\LiteXLProc.%08lx.%08lx", GetCurrentProcessId(), InterlockedIncrement(&pipe_serial));
        self->pipes[i][0] = CreateNamedPipeA(pipe_name,
                                            PIPE_ACCESS_INBOUND
                                              | FILE_FLAG_OVERLAPPED
                                              | FILE_FLAG_FIRST_PIPE_INSTANCE,
                                            PIPE_TYPE_BYTE | PIPE_WAIT,
                                            1,
                                            READ_BUF_SIZE, READ_BUF_SIZE,
                                            0,
                                            NULL);
        P_ASSERT_SYS(self->pipes[i][0] != INVALID_HANDLE_VALUE);

        self->pipes[i][1] = CreateFileA(pipe_name,
                                        GENERIC_WRITE,
                                        0,
                                        NULL,
                                        OPEN_EXISTING,
                                        FILE_ATTRIBUTE_NORMAL,
                                        NULL);
        P_ASSERT_SYS(self->pipes[i][1] != INVALID_HANDLE_VALUE);

        P_ASSERT_SYS(SetHandleInformation(self->pipes[i][i == PROCESS_STDIN ? 1 : 0], HANDLE_FLAG_INHERIT, 0)
                      && SetHandleInformation(self->pipes[i][i == PROCESS_STDIN ? 0 : 1], HANDLE_FLAG_INHERIT, 1));
        break;

      default:
        P_ASSERT_ERR(PROCESS_EINVAL, false);
        break;

      }
    }
  }

  memset(&si, 0, sizeof(STARTUPINFOW));
  si.cb = sizeof(STARTUPINFOW);
  si.dwFlags |= STARTF_USESTDHANDLES;
  si.hStdInput = self->pipes[PROCESS_STDIN][0];
  si.hStdOutput = self->pipes[PROCESS_STDOUT][1];
  si.hStdError = self->pipes[PROCESS_STDERR][1];

  P_ASSERT_ERR(PROCESS_EINVAL, create_lpcmdline(cmdline, argv, verbatim_arguments));

  if (env != NULL)
    P_ASSERT_ERR(PROCESS_EINVAL, 
                (environment = create_lpenvironment(env, action == PROCESS_ENV_EXTEND)) != NULL);

  if (cwd != NULL)
    P_ASSERT_SYS(MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS | MB_PRECOMPOSED,
                                    cwd, -1, wcs_cwd, MAX_PATH) == 0);

  P_ASSERT_SYS(CreateProcessW(NULL,
                              cmdline,
                              NULL, NULL,
                              TRUE,
                              CREATE_UNICODE_ENVIRONMENT
                                | (detach ? DETACHED_PROCESS : CREATE_NO_WINDOW),
                              env != NULL ? environment : NULL,
                              cwd != NULL ? wcs_cwd : NULL,
                              &si, &self->pi));

  self->pid = self->pi.dwProcessId;
  CloseHandle(self->pi.hThread);

  if (detach)
    CloseHandle(self->pi.hProcess);

#else

#define P_CHILD_ASSERT_SYS(COND) \
  do { \
    if ((!COND)) { \
      write(status_pipe[1], &errno, sizeof(errno)); \
      _exit(errno); \
    } \
  } while (0)

  // copy all the envs
  for (const char **envp = env; *envp != NULL; envp++)
    env_len++;

  env_keys = calloc(env_len, sizeof(char *));
  env_values = calloc(env_len,  sizeof(char *));
  P_ASSERT_ERR(PROCESS_ENOMEM, env_keys != NULL && env_values != NULL);

  for (int i = 0; i < env_len; i++) {
    // TODO: env must be valid
    env_keys[i] = strdup(env[i]);
    env_values[i] = strdup(strchr(env[i], '=') + 1);
    P_ASSERT_ERR(PROCESS_ENOMEM, env_keys[i] != NULL && env_values[i] != NULL);
  }

  // create the pipe for sending errno
  P_ASSERT_SYS(pipe(status_pipe) == 0 && fcntl(status_pipe[1], F_SETFD, O_CLOEXEC) == 0);

  // create pipes for all the things
  for (int i = 0; i < 3; i++) {
    P_ASSERT_SYS(pipe(self->pipes[i]) == 0
                  && fcntl(self->pipes[i][i == PROCESS_STDIN ? 1 : 0], F_SETFL, O_NONBLOCK) == 0);
  }

  self->pid = fork();
  P_ASSERT_SYS(self->pid >= 0);
  if (self->pid == 0) {

    // child process
    if (detach)
      // set child as its own process group
      P_CHILD_ASSERT_SYS(setsid() == 0);
    else
      // join parent's process group
      P_CHILD_ASSERT_SYS(setpgid(0, 0) == 0);

    if (cwd != NULL)
      P_CHILD_ASSERT_SYS(chdir(cwd) == 0);

    for (int i = 0; i < 3; i++) {
      if (redirect[i] == PROCESS_REDIRECT_DISCARD) {
        // close the stream
        P_CHILD_ASSERT_SYS(close(self->pipes[i][i == PROCESS_STDIN ? 0 : 1]) == 0);
        // close child's stdin/out/err
        P_CHILD_ASSERT_SYS(close(i) == 0);
      } else if (redirect[i] != PROCESS_REDIRECT_PARENT) {
        // not inheriting fds, use our fd as stdin/out/err
        P_CHILD_ASSERT_SYS(dup2(self->pipes[i][i == PROCESS_STDIN ? 0 : 1], i) == 0);
      }
      // close parent side of the stream
      P_CHILD_ASSERT_SYS(close(self->pipes[i][i == PROCESS_STDIN ? 1 : 0]) == 0);
    }

    if (action == PROCESS_ENV_REPLACE)
      clearenv();

    for (int i = 0; i < env_len; i++) {
      P_CHILD_ASSERT_SYS(setenv(env_keys[i], env_values[i], true) == 0);
    }

    execvp(argv[0], (char *const *) argv);
    P_CHILD_ASSERT_SYS(false);

  } else if (self->pid > 0) {

    // parent process
    size_t r;

    // this pipe must be closed to receive data from child
    P_CHILD_ASSERT_SYS(close(status_pipe[1]));

    // keep polling the pipe until the child process returns something
    while ((r = read(status_pipe[0], &retval, sizeof(errno))) == -1) {
      if (errno == EPIPE)
        break; // success, pipe closed due to CLOEXEC
      P_ASSERT_SYS(errno != EINTR);
    }

    // child process returned an error code
    if (r == sizeof(errno))
      P_ASSERT_ERR(-retval, false);
  }

#undef P_CHILD_ASSERT_SYS

#endif

  self->running = true;

CLEANUP:
#ifdef _WIN32

  free(environment);

#else

  if (env_keys != NULL)
    for (char **envp = env_keys; *envp != NULL; envp++) free(*envp);
  if (env_values != NULL)
    for (char **envp = env_values; *envp != NULL; envp++) free(*envp);
  free(env_keys);
  free(env_values);

#endif

  for (int i = 0; i < 3; i++) {
    process_handle_t *handle = &self->pipes[i][i == PROCESS_STDIN ? 0 : 1];
    close_handle(handle);

    // if failed, clean up the parent side as well
    if (retval != 0 && i != PROCESS_STDIN) {
      close_handle(&self->pipes[i][0]);
    }
  }

  return retval;
}

int process_read(process_t *self, process_stream_t stream, char *buf, int buf_size) {
  int retval = 0;

  P_ASSERT_ERR(PROCESS_EINVAL, self != NULL);
  P_ASSERT_ERR(PROCESS_EINVAL, self->running);
  P_ASSERT_ERR(PROCESS_EINVAL, stream == PROCESS_STDOUT || stream == PROCESS_STDERR);
  P_ASSERT_ERR(PROCESS_EINVAL, buf != NULL);
  P_ASSERT_ERR(PROCESS_EINVAL, buf_size > 0);

  buf_size = P_MIN(buf_size, READ_BUF_SIZE);

#ifdef _WIN32
  DWORD read;

  if (!self->remaining[stream] && !self->reading[stream]) {
    // no more data from previous read; initialize a read
    if (ReadFile(self->pipes[stream][0],
                self->buffer[stream], buf_size, &read,
                &self->overlapped[stream])) {
      // read something without going into overlapped
      self->remaining[stream] = read;
    } else if (GetLastError() == ERROR_IO_PENDING) {
      // going into overlapped
      self->reading[stream] = true;
    } else {
      // other errors
      return -GetLastError();
    }
  }

  if (self->reading[stream]
      && GetOverlappedResult(self->pipes[stream][0],
                              &self->overlapped[stream],
                              &read,
                              FALSE)) {
    // overlapped is completed, get size so we can read them
    self->reading[stream] = false;
    self->remaining[stream] = self->overlapped[stream].InternalHigh;
  } else if (GetLastError() == ERROR_IO_INCOMPLETE) {
    // io still processing
    return PROCESS_EWOULDBLOCK;
  } else {
    // other errors
    return -GetLastError();
  }

  if (self->remaining[stream]) {
    // we still have leftovers, return them!
    retval = P_MIN(buf_size, self->remaining[stream]);
    memcpy(buf, self->buffer[stream], retval);
    self->remaining[stream] -= retval;
  } else {
    // it would block
    return PROCESS_EWOULDBLOCK;
  }
#endif

CLEANUP:
  return retval;
}

int process_write(process_t *self, char *buf, int buf_size) {
  int retval = 0;

  P_ASSERT_ERR(PROCESS_EINVAL, self != NULL);
  P_ASSERT_ERR(PROCESS_EINVAL, self->running);
  P_ASSERT_ERR(PROCESS_EINVAL, buf != NULL);
  P_ASSERT_ERR(PROCESS_EINVAL, buf_size > 0);

#ifdef _WIN32
  /**
   * there is no way to safely know if a pipe would block on windows.
   * NtQueryInformationFile can do this but this is prone to race conditions.
   * we workaround this by copying data to our buffer and declare that it is done.
   * On subsequent writes, we will return EWOULDBLOCK until the write is done.
   */
  DWORD write;
  if (self->reading[PROCESS_STDIN]) {
    // check if the overlap read(actually write) is done.
    if (GetOverlappedResult(self->pipes[PROCESS_STDIN][1],
                            &self->overlapped[PROCESS_STDIN],
                            &write,
                            FALSE)) {
      // done writing
      self->reading[PROCESS_STDIN] = false;
    } else if (GetLastError() == ERROR_IO_INCOMPLETE) {
      //  still writing
      return PROCESS_EWOULDBLOCK;
    } else {
      // unknown error
      return -GetLastError();
    }
  }
  // copy data to buffer and prepare for writing
  retval = P_MIN(buf_size, READ_BUF_SIZE);
  memcpy(self->buffer[PROCESS_STDIN], buf, retval);

  if (!WriteFile(self->pipes[PROCESS_STDIN][1],
                self->buffer[PROCESS_STDIN], retval, &write,
                &self->overlapped[PROCESS_STDIN])) {
    if (GetLastError() == ERROR_IO_PENDING) {
      // going into overlap
      self->reading[PROCESS_STDIN] = true;
    } else {
      // other errors
      return -GetLastError();
    }
  }
#endif

CLEANUP:
  return retval;
}

int process_signal(process_t *self, int sig) {
  int retval = 0;

  P_ASSERT_ERR(PROCESS_EINVAL, self != NULL);
  P_ASSERT_ERR(PROCESS_EINVAL, self->running);

#ifdef _WIN32
  switch (sig) {
    case PROCESS_SIGTERM: P_ASSERT_SYS(GenerateConsoleCtrlEvent(CTRL_BREAK_EVENT, self->pid)); break;
    case PROCESS_SIGINT: P_ASSERT_SYS(DebugBreakProcess(self->pi.hProcess)); break;
    case PROCESS_SIGKILL: P_ASSERT_SYS(TerminateProcess(self->pi.hProcess, 137)); break;
    default: P_ASSERT_ERR(PROCESS_EINVAL, false);
  }
#endif

CLEANUP:
  return retval;
}

int process_returncode(process_t *self) {
  int retval = 0;

  P_ASSERT_ERR(PROCESS_EINVAL, self != NULL);
  P_ASSERT_ERR(PROCESS_EINVAL, !self->running);

  return self->returncode;

CLEANUP:
  return retval;
}

