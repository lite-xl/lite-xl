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
#include <fcntl.h>
#include <sys/types.h>
#include <sys/wait.h>
#endif

#define READ_BUF_SIZE 4096

#ifdef _WIN32

typedef HANDLE process_handle_t;
#define PROCESS_INVALID_HANDLE INVALID_HANDLE_VALUE

int PROCESS_EINVAL = -ERROR_INVALID_PARAMETER;
int PROCESS_ENOMEM = -ERROR_NOT_ENOUGH_MEMORY;

static void close_handle(process_handle_t *handle) {
  if (*handle != INVALID_HANDLE_VALUE) {
    CloseHandle(*handle);
    *handle = INVALID_HANDLE_VALUE;
  }
}

#else

typedef int process_handle_t;
#define PROCESS_INVALID_HANDLE 0

int PROCESS_EINVAL = -EINVAL;
int PROCESS_ENOMEM = -ENOMEM;

static void close_handle(process_handle_t *handle) {
  if (*handle != INVALID_HANDLE_VALUE) {
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
    OVERLAPPED overlapped[2];
    bool reading[2];
    char buffer[2][READ_BUF_SIZE];
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

  self->deadline = timeout;  
  self->detached = detach;

  process_redirect_t redirect[3];
  if (pipe_redirect[PROCESS_STDIN] == PROCESS_REDIRECT_STDOUT)
    return PROCESS_EINVAL;
  if (pipe_redirect[PROCESS_STDOUT] == PROCESS_REDIRECT_STDOUT)
    return PROCESS_EINVAL;

  // normalize
  redirect[PROCESS_STDIN] = pipe_redirect[PROCESS_STDIN] == PROCESS_REDIRECT_DEFAULT ? PROCESS_REDIRECT_PIPE : redirect[PROCESS_STDIN];
  redirect[PROCESS_STDOUT] = pipe_redirect[PROCESS_STDOUT] == PROCESS_REDIRECT_DEFAULT ? PROCESS_REDIRECT_PIPE : redirect[PROCESS_STDOUT];
  redirect[PROCESS_STDERR] = pipe_redirect[PROCESS_STDERR] == PROCESS_REDIRECT_DEFAULT ? PROCESS_REDIRECT_PARENT : redirect[PROCESS_STDERR];

#ifdef _WIN32
  STARTUPINFOW si;
  wchar_t wcs_cwd[MAX_PATH];
  wchar_t cmdline[32767];
  wchar_t *environment = NULL;

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
        if (self->pipes[i][0] == INVALID_HANDLE_VALUE)
          goto FAIL;

        self->pipes[i][1] = CreateFileA(pipe_name,
                                        GENERIC_WRITE,
                                        0,
                                        NULL,
                                        OPEN_EXISTING,
                                        FILE_ATTRIBUTE_NORMAL,
                                        NULL);
        if (self->pipes[i][1] == INVALID_HANDLE_VALUE)
          goto FAIL;

        if (!SetHandleInformation(self->pipes[i][i == PROCESS_STDIN ? 1 : 0], HANDLE_FLAG_INHERIT, 0) ||
            !SetHandleInformation(self->pipes[i][i == PROCESS_STDIN ? 0 : 1], HANDLE_FLAG_INHERIT, 1))
          goto FAIL;
      }
      break;

      default:
        goto FAIL;
    }
  }


  memset(&si, 0, sizeof(STARTUPINFOW));
  si.cb = sizeof(STARTUPINFOW);
  si.dwFlags |= STARTF_USESTDHANDLES;
  si.hStdInput = self->pipes[PROCESS_STDIN][1];
  si.hStdOutput = self->pipes[PROCESS_STDOUT][0];
  si.hStdError = self->pipes[PROCESS_STDERR][0];


  if (!create_lpcmdline(cmdline, argv, verbatim_arguments))
    goto FAIL;

  if (env != NULL
      && (environment = create_lpenvironment(env, action == PROCESS_ENV_EXTEND)) == NULL)
    goto FAIL;

  if (cwd != NULL
      && MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS | MB_PRECOMPOSED,
                            cwd, -1, wcs_cwd, MAX_PATH) == 0)
    goto FAIL;

  if (!CreateProcessW(NULL,
                      cmdline,
                      NULL, NULL,
                      TRUE,
                      CREATE_UNICODE_ENVIRONMENT
                        | (detach ? DETACHED_PROCESS : CREATE_NO_WINDOW),
                      env != NULL ? environment : NULL,
                      cwd != NULL ? wcs_cwd : NULL,
                      &si, &self->pi))
    goto FAIL;

  self->pid = self->pi.dwProcessId;
  CloseHandle(self->pi.hThread);
  if (detach)
    CloseHandle(self->pi.hProcess);
#endif

  goto CLEANUP;

FAIL:
#ifdef _WIN32
  retval = -GetLastError();
#else
  retval = -errno;
#endif

CLEANUP:
#ifdef _WIN32
  free(environment);
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
