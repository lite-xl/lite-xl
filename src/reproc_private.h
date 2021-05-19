/**
 * @copyright Daan De Meyer
 * @license MIT
 * @link https://github.com/DaanDeMeyer/reproc Source code.
 * @note Amalgamation by Jefferson Gonzalez
 */

#pragma once

#include <assert.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <wchar.h>

#include "reproc.h"

//
// macro.h
//
#define ARRAY_SIZE(x) (sizeof(x) / sizeof((x)[0]))

#define MIN(a, b) (a) < (b) ? (a) : (b)

#if defined(_WIN32) && !defined(__MINGW32__)
  #define THREAD_LOCAL __declspec(thread)
#else
  #define THREAD_LOCAL __thread
#endif

//
// clock.h
//
int64_t now(void);

//
// error.h
//
#define ASSERT(expression) assert(expression)

// Avoid unused assignment warnings in release mode when the result of an
// assignment is only used in an assert statement.
#define ASSERT_UNUSED(expression)                                              \
  do {                                                                         \
    (void) !(expression);                                                      \
    ASSERT((expression));                                                      \
  } while (0)

// Returns `r` if `expression` is false.
#define ASSERT_RETURN(expression, r)                                           \
  do {                                                                         \
    if (!(expression)) {                                                       \
      return (r);                                                              \
    }                                                                          \
  } while (0)

#define ASSERT_EINVAL(expression) ASSERT_RETURN(expression, REPROC_EINVAL)

const char *error_string(int error);

//
// handle.h
//
#if defined(_WIN32)
typedef void *handle_type; // `HANDLE`
#else
typedef int handle_type; // fd
#endif

extern const handle_type HANDLE_INVALID;

// Sets the `FD_CLOEXEC` flag on the file descriptor. POSIX only.
int handle_cloexec(handle_type handle, bool enable);

// Closes `handle` if it is not an invalid handle and returns an invalid handle.
// Does not overwrite the last system error if an error occurs while closing
// `handle`.
handle_type handle_destroy(handle_type handle);

//
// init.h
//
int init(void);

void deinit(void);

//
// options.h
//
reproc_stop_actions parse_stop_actions(reproc_stop_actions stop);

int parse_options(reproc_options *options, const char *const *argv);

//
// pipe.h
//
#ifdef _WIN64
typedef uint64_t pipe_type; // `SOCKET`
#elif _WIN32
typedef uint32_t pipe_type; // `SOCKET`
#else
typedef int pipe_type; // fd
#endif

extern const pipe_type PIPE_INVALID;

extern const short PIPE_EVENT_IN;
extern const short PIPE_EVENT_OUT;

typedef struct {
  pipe_type pipe;
  short interests;
  short events;
} pipe_event_source;

// Creates a new anonymous pipe. `parent` and `child` are set to the parent and
// child endpoint of the pipe respectively.
int pipe_init(pipe_type *read, pipe_type *write);

// Sets `pipe` to nonblocking mode.
int pipe_nonblocking(pipe_type pipe, bool enable);

// Reads up to `size` bytes into `buffer` from the pipe indicated by `pipe` and
// returns the amount of bytes read.
int pipe_read(pipe_type pipe, uint8_t *buffer, size_t size);

// Writes up to `size` bytes from `buffer` to the pipe indicated by `pipe` and
// returns the amount of bytes written.
int pipe_write(pipe_type pipe, const uint8_t *buffer, size_t size);

// Polls the given event sources for events.
int pipe_poll(pipe_event_source *sources, size_t num_sources, int timeout);

int pipe_shutdown(pipe_type pipe);

pipe_type pipe_destroy(pipe_type pipe);

//
// process.h
//
#if defined(_WIN32)
typedef void *process_type; // `HANDLE`
#else
typedef int process_type; // `pid_t`
#endif

extern const process_type PROCESS_INVALID;

struct process_options {
  // If `NULL`, the child process inherits the environment of the current
  // process.
  struct {
    REPROC_ENV behavior;
    const char *const *extra;
  } env;
  // If not `NULL`, the working directory of the child process is set to
  // `working_directory`.
  const char *working_directory;
  // The standard streams of the child process are redirected to the `in`, `out`
  // and `err` handles. If a handle is `HANDLE_INVALID`, the corresponding child
  // process standard stream is closed. The `exit` handle is simply inherited by
  // the child process.
  struct {
    handle_type in;
    handle_type out;
    handle_type err;
    handle_type exit;
  } handle;
};

// Spawns a child process that executes the command stored in `argv`.
//
// If `argv` is `NULL` on POSIX, `exec` is not called after fork and this
// function returns 0 in the child process and > 0 in the parent process. On
// Windows, if `argv` is `NULL`, an error is returned.
//
// The process handle of the new child process is assigned to `process`.
int process_start(process_type *process,
                  const char *const *argv,
                  struct process_options options);

// Returns the process ID associated with the given handle. On posix systems the
// handle is the process ID and so its returned directly. On WIN32 the process
// ID is returned from GetProcessId on the pointer.
int process_pid(process_type process);

// Returns the process's exit status if it has finished running.
int process_wait(process_type process);

// Sends the `SIGTERM` (POSIX) or `CTRL-BREAK` (Windows) signal to the process
// indicated by `process`.
int process_terminate(process_type process);

// Sends the `SIGKILL` signal to `process` (POSIX) or calls `TerminateProcess`
// on `process` (Windows).
int process_kill(process_type process);

process_type process_destroy(process_type process);

//
// redirect.h
//
int redirect_init(pipe_type *parent,
                  handle_type *child,
                  REPROC_STREAM stream,
                  reproc_redirect redirect,
                  bool nonblocking,
                  handle_type out);

handle_type redirect_destroy(handle_type child, REPROC_REDIRECT type);

// Internal prototypes

int redirect_parent(handle_type *child, REPROC_STREAM stream);

int redirect_discard(handle_type *child, REPROC_STREAM stream);

int redirect_file(handle_type *child, FILE *file);

int redirect_path(handle_type *child, REPROC_STREAM stream, const char *path);

//
// strv.h
//
#define STRV_FOREACH(s, l) for ((s) = (l); (s) && *(s); (s)++)

char **strv_concat(char *const *a, const char *const *b);

char **strv_free(char **l);

//
// utf.h
//

// `size` represents the entire size of `string`, including NUL-terminators. We
// take the entire size because strings like the environment string passed to
// CreateProcessW includes multiple NUL-terminators so we can't always rely on
// `strlen` to calculate the string length for us. See the lpEnvironment
// documentation of CreateProcessW:
// https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw
// Pass -1 as the size to have `utf16_from_utf8` calculate the size until (and
// including) the first NUL terminator.
wchar_t *utf16_from_utf8(const char *string, int size);
