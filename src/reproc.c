/**
 * @copyright Daan De Meyer
 * @license MIT
 * @link https://github.com/DaanDeMeyer/reproc Source code.
 * @note Amalgamation by Jefferson Gonzalez
 */

#include "reproc_private.h"

//
// drain.c
//
int reproc_drain(reproc_t *process, reproc_sink out, reproc_sink err)
{
  ASSERT_EINVAL(process);
  ASSERT_EINVAL(out.function);
  ASSERT_EINVAL(err.function);

  const uint8_t initial = 0;
  int r = -1;

  // A single call to `read` might contain multiple messages. By always calling
  // both sinks once with no data before reading, we give them the chance to
  // process all previous output one by one before reading from the child
  // process again.

  r = out.function(REPROC_STREAM_IN, &initial, 0, out.context);
  if (r != 0) {
    return r;
  }

  r = err.function(REPROC_STREAM_IN, &initial, 0, err.context);
  if (r != 0) {
    return r;
  }

  uint8_t buffer[4096];

  for (;;) {
    reproc_event_source source = { process, REPROC_EVENT_OUT | REPROC_EVENT_ERR,
                                   0 };

    r = reproc_poll(&source, 1, REPROC_INFINITE);
    if (r < 0) {
      r = r == REPROC_EPIPE ? 0 : r;
      break;
    }

    if (source.events & REPROC_EVENT_DEADLINE) {
      r = REPROC_ETIMEDOUT;
      break;
    }

    REPROC_STREAM stream = source.events & REPROC_EVENT_OUT ? REPROC_STREAM_OUT
                                                            : REPROC_STREAM_ERR;

    r = reproc_read(process, stream, buffer, ARRAY_SIZE(buffer));
    if (r < 0 && r != REPROC_EPIPE) {
      break;
    }

    size_t bytes_read = r == REPROC_EPIPE ? 0 : (size_t) r;
    reproc_sink sink = stream == REPROC_STREAM_OUT ? out : err;

    r = sink.function(stream, buffer, bytes_read, sink.context);
    if (r != 0) {
      break;
    }
  }

  return r;
}

static int sink_string(REPROC_STREAM stream,
                       const uint8_t *buffer,
                       size_t size,
                       void *context)
{
  (void) stream;

  char **string = (char **) context;
  size_t string_size = *string == NULL ? 0 : strlen(*string);

  char *r = (char *) realloc(*string, string_size + size + 1);
  if (r == NULL) {
    return REPROC_ENOMEM;
  }

  *string = r;
  memcpy(*string + string_size, buffer, size);
  (*string)[string_size + size] = '\0';

  return 0;
}

reproc_sink reproc_sink_string(char **output)
{
  return (reproc_sink){ sink_string, output };
}

static int sink_discard(REPROC_STREAM stream,
                        const uint8_t *buffer,
                        size_t size,
                        void *context)
{
  (void) stream;
  (void) buffer;
  (void) size;
  (void) context;

  return 0;
}

reproc_sink reproc_sink_discard(void)
{
  return (reproc_sink){ sink_discard, NULL };
}

const reproc_sink REPROC_SINK_NULL = { sink_discard, NULL };

void *reproc_free(void *ptr)
{
  free(ptr);
  return NULL;
}

//
// options.c
//
static bool redirect_is_set(reproc_redirect redirect)
{
  return redirect.type || redirect.handle || redirect.file || redirect.path;
}

static int parse_redirect(reproc_redirect *redirect,
                          REPROC_STREAM stream,
                          bool parent,
                          bool discard,
                          FILE *file,
                          const char *path)
{
  ASSERT(redirect);

  if (file) {
    ASSERT_EINVAL(!redirect_is_set(*redirect));
    ASSERT_EINVAL(!parent && !discard && !path);
    redirect->type = REPROC_REDIRECT_FILE;
    redirect->file = file;
  }

  if (path) {
    ASSERT_EINVAL(!redirect_is_set(*redirect));
    ASSERT_EINVAL(!parent && !discard && !file);
    redirect->type = REPROC_REDIRECT_PATH;
    redirect->path = path;
  }

  if (redirect->type == REPROC_REDIRECT_HANDLE || redirect->handle) {
    ASSERT_EINVAL(redirect->type == REPROC_REDIRECT_DEFAULT ||
                  redirect->type == REPROC_REDIRECT_HANDLE);
    ASSERT_EINVAL(redirect->handle);
    ASSERT_EINVAL(!redirect->file && !redirect->path);
    redirect->type = REPROC_REDIRECT_HANDLE;
  }

  if (redirect->type == REPROC_REDIRECT_FILE || redirect->file) {
    ASSERT_EINVAL(redirect->type == REPROC_REDIRECT_DEFAULT ||
                  redirect->type == REPROC_REDIRECT_FILE);
    ASSERT_EINVAL(redirect->file);
    ASSERT_EINVAL(!redirect->handle && !redirect->path);
    redirect->type = REPROC_REDIRECT_FILE;
  }

  if (redirect->type == REPROC_REDIRECT_PATH || redirect->path) {
    ASSERT_EINVAL(redirect->type == REPROC_REDIRECT_DEFAULT ||
                  redirect->type == REPROC_REDIRECT_PATH);
    ASSERT_EINVAL(redirect->path);
    ASSERT_EINVAL(!redirect->handle && !redirect->file);
    redirect->type = REPROC_REDIRECT_PATH;
  }

  if (redirect->type == REPROC_REDIRECT_DEFAULT) {
    if (parent) {
      ASSERT_EINVAL(!discard);
      redirect->type = REPROC_REDIRECT_PARENT;
    } else if (discard) {
      ASSERT_EINVAL(!parent);
      redirect->type = REPROC_REDIRECT_DISCARD;
    } else {
      redirect->type = stream == REPROC_STREAM_ERR ? REPROC_REDIRECT_PARENT
                                                   : REPROC_REDIRECT_PIPE;
    }
  }

  return 0;
}

reproc_stop_actions parse_stop_actions(reproc_stop_actions stop)
{
  bool is_noop = stop.first.action == REPROC_STOP_NOOP &&
                 stop.second.action == REPROC_STOP_NOOP &&
                 stop.third.action == REPROC_STOP_NOOP;

  if (is_noop) {
    stop.first.action = REPROC_STOP_WAIT;
    stop.first.timeout = REPROC_DEADLINE;
    stop.second.action = REPROC_STOP_TERMINATE;
    stop.second.timeout = REPROC_INFINITE;
  }

  return stop;
}

int parse_options(reproc_options *options, const char *const *argv)
{
  ASSERT(options);

  int r = -1;

  r = parse_redirect(&options->redirect.in, REPROC_STREAM_IN,
                     options->redirect.parent, options->redirect.discard, NULL,
                     NULL);
  if (r < 0) {
    return r;
  }

  r = parse_redirect(&options->redirect.out, REPROC_STREAM_OUT,
                     options->redirect.parent, options->redirect.discard,
                     options->redirect.file, options->redirect.path);
  if (r < 0) {
    return r;
  }

  r = parse_redirect(&options->redirect.err, REPROC_STREAM_ERR,
                     options->redirect.parent, options->redirect.discard,
                     options->redirect.file, options->redirect.path);
  if (r < 0) {
    return r;
  }

  if (options->input.data != NULL || options->input.size > 0) {
    ASSERT_EINVAL(options->input.data != NULL);
    ASSERT_EINVAL(options->input.size > 0);
    ASSERT_EINVAL(options->redirect.in.type == REPROC_REDIRECT_PIPE);
  }

  if (options->fork) {
    ASSERT_EINVAL(argv == NULL);
  } else {
    ASSERT_EINVAL(argv != NULL && argv[0] != NULL);
  }

  if (options->deadline == 0) {
    options->deadline = REPROC_INFINITE;
  }

  options->stop = parse_stop_actions(options->stop);

  return 0;
}

//
// redirect.c
//
static int redirect_pipe(pipe_type *parent,
                         handle_type *child,
                         REPROC_STREAM stream,
                         bool nonblocking)
{
  ASSERT(parent);
  ASSERT(child);

  pipe_type pipe[] = { PIPE_INVALID, PIPE_INVALID };
  int r = -1;

  r = pipe_init(&pipe[0], &pipe[1]);
  if (r < 0) {
    goto finish;
  }

  r = pipe_nonblocking(stream == REPROC_STREAM_IN ? pipe[1] : pipe[0],
                       nonblocking);
  if (r < 0) {
    goto finish;
  }

  *parent = stream == REPROC_STREAM_IN ? pipe[1] : pipe[0];
  *child = stream == REPROC_STREAM_IN ? (handle_type) pipe[0]
                                      : (handle_type) pipe[1];

finish:
  if (r < 0) {
    pipe_destroy(pipe[0]);
    pipe_destroy(pipe[1]);
  }

  return r;
}

int redirect_init(pipe_type *parent,
                  handle_type *child,
                  REPROC_STREAM stream,
                  reproc_redirect redirect,
                  bool nonblocking,
                  handle_type out)
{
  ASSERT(parent);
  ASSERT(child);

  int r = REPROC_EINVAL;

  switch (redirect.type) {

    case REPROC_REDIRECT_DEFAULT:
      ASSERT(false);
      break;

    case REPROC_REDIRECT_PIPE:
      r = redirect_pipe(parent, child, stream, nonblocking);
      break;

    case REPROC_REDIRECT_PARENT:
      r = redirect_parent(child, stream);
      if (r == REPROC_EPIPE) {
        // Discard if the corresponding parent stream is closed.
        r = redirect_discard(child, stream);
      }

      if (r < 0) {
        break;
      }

      *parent = PIPE_INVALID;

      break;

    case REPROC_REDIRECT_DISCARD:
      r = redirect_discard(child, stream);
      if (r < 0) {
        break;
      }

      *parent = PIPE_INVALID;

      break;

    case REPROC_REDIRECT_HANDLE:
      ASSERT(redirect.handle);

      r = 0;

      *child = redirect.handle;
      *parent = PIPE_INVALID;

      break;

    case REPROC_REDIRECT_FILE:
      ASSERT(redirect.file);

      r = redirect_file(child, redirect.file);
      if (r < 0) {
        break;
      }

      *parent = PIPE_INVALID;

      break;

    case REPROC_REDIRECT_STDOUT:
      ASSERT(stream == REPROC_STREAM_ERR);
      ASSERT(out != HANDLE_INVALID);

      r = 0;

      *child = out;
      *parent = PIPE_INVALID;

      break;

    case REPROC_REDIRECT_PATH:
      ASSERT(redirect.path);

      r = redirect_path(child, stream, redirect.path);
      if (r < 0) {
        break;
      }

      *parent = PIPE_INVALID;

      break;
  }

  return r;
}

handle_type redirect_destroy(handle_type child, REPROC_REDIRECT type)
{
  if (child == HANDLE_INVALID) {
    return HANDLE_INVALID;
  }

  switch (type) {
    case REPROC_REDIRECT_DEFAULT:
      ASSERT(false);
      break;
    case REPROC_REDIRECT_PIPE:
      // We know `handle` is a pipe if `REDIRECT_PIPE` is used so the cast is
      // safe. This little hack prevents us from having to introduce a generic
      // handle type.
      pipe_destroy((pipe_type) child);
      break;
    case REPROC_REDIRECT_DISCARD:
    case REPROC_REDIRECT_PATH:
      handle_destroy(child);
      break;
    case REPROC_REDIRECT_PARENT:
    case REPROC_REDIRECT_FILE:
    case REPROC_REDIRECT_HANDLE:
    case REPROC_REDIRECT_STDOUT:
      break;
  }

  return HANDLE_INVALID;
}

//
// reproc.c
//
struct reproc_t {
  process_type handle;

  struct {
    pipe_type in;
    pipe_type out;
    pipe_type err;
    pipe_type exit;
  } pipe;

  int status;
  reproc_stop_actions stop;
  int64_t deadline;
  bool nonblocking;

  struct {
    pipe_type out;
    pipe_type err;
  } child;
};

enum {
  STATUS_NOT_STARTED = -1,
  STATUS_IN_PROGRESS = -2,
  STATUS_IN_CHILD = -3,
};

#define SIGOFFSET 128

const int REPROC_SIGKILL = SIGOFFSET + 9;
const int REPROC_SIGTERM = SIGOFFSET + 15;

const int REPROC_INFINITE = -1;
const int REPROC_DEADLINE = -2;

static int setup_input(pipe_type *pipe, const uint8_t *data, size_t size)
{
  if (data == NULL || size == 0) {
    ASSERT(data == NULL);
    ASSERT(size == 0);
    return 0;
  }

  ASSERT(pipe && *pipe != PIPE_INVALID);

  // `reproc_write` only needs the child process stdin pipe to be initialized.
  size_t written = 0;
  int r = -1;

  // Make sure we don't block indefinitely when `input` is bigger than the
  // size of the pipe.
  r = pipe_nonblocking(*pipe, true);
  if (r < 0) {
    return r;
  }

  while (written < size) {
    r = pipe_write(*pipe, data + written, size - written);
    if (r < 0) {
      return r;
    }

    ASSERT(written + (size_t) r <= size);
    written += (size_t) r;
  }

  *pipe = pipe_destroy(*pipe);

  return 0;
}

static int expiry(int timeout, int64_t deadline)
{
  if (timeout == REPROC_INFINITE && deadline == REPROC_INFINITE) {
    return REPROC_INFINITE;
  }

  if (deadline == REPROC_INFINITE) {
    return timeout;
  }

  int64_t n = now();

  if (n >= deadline) {
    return REPROC_DEADLINE;
  }

  // `deadline` exceeds `now` by at most a full `int` so the cast is safe.
  int remaining = (int) (deadline - n);

  if (timeout == REPROC_INFINITE) {
    return remaining;
  }

  return MIN(timeout, remaining);
}

static size_t find_earliest_deadline(reproc_event_source *sources,
                                     size_t num_sources)
{
  ASSERT(sources);
  ASSERT(num_sources > 0);

  size_t earliest = 0;
  int min = REPROC_INFINITE;

  for (size_t i = 0; i < num_sources; i++) {
    reproc_t *process = sources[i].process;

    if (process == NULL) {
      continue;
    }

    int current = expiry(REPROC_INFINITE, process->deadline);

    if (current == REPROC_DEADLINE) {
      return i;
    }

    if (min == REPROC_INFINITE || current < min) {
      earliest = i;
      min = current;
    }
  }

  return earliest;
}

reproc_t *reproc_new(void)
{
  reproc_t *process = malloc(sizeof(reproc_t));
  if (process == NULL) {
    return NULL;
  }

  *process = (reproc_t){ .handle = PROCESS_INVALID,
                         .pipe = { .in = PIPE_INVALID,
                                   .out = PIPE_INVALID,
                                   .err = PIPE_INVALID,
                                   .exit = PIPE_INVALID },
                         .child = { .out = PIPE_INVALID, .err = PIPE_INVALID },
                         .status = STATUS_NOT_STARTED,
                         .deadline = REPROC_INFINITE };

  return process;
}

int reproc_start(reproc_t *process,
                 const char *const *argv,
                 reproc_options options)
{
  ASSERT_EINVAL(process);
  ASSERT_EINVAL(process->status == STATUS_NOT_STARTED);

  struct {
    handle_type in;
    handle_type out;
    handle_type err;
    pipe_type exit;
  } child = { HANDLE_INVALID, HANDLE_INVALID, HANDLE_INVALID, PIPE_INVALID };
  int r = -1;

  r = init();
  if (r < 0) {
    return r; // Make sure we can always call `deinit` in `finish`.
  }

  r = parse_options(&options, argv);
  if (r < 0) {
    goto finish;
  }

  r = redirect_init(&process->pipe.in, &child.in, REPROC_STREAM_IN,
                    options.redirect.in, options.nonblocking, HANDLE_INVALID);
  if (r < 0) {
    goto finish;
  }

  r = redirect_init(&process->pipe.out, &child.out, REPROC_STREAM_OUT,
                    options.redirect.out, options.nonblocking, HANDLE_INVALID);
  if (r < 0) {
    goto finish;
  }

  r = redirect_init(&process->pipe.err, &child.err, REPROC_STREAM_ERR,
                    options.redirect.err, options.nonblocking, child.out);
  if (r < 0) {
    goto finish;
  }

  r = pipe_init(&process->pipe.exit, &child.exit);
  if (r < 0) {
    goto finish;
  }

  r = setup_input(&process->pipe.in, options.input.data, options.input.size);
  if (r < 0) {
    goto finish;
  }

  struct process_options process_options = {
    .env = { .behavior = options.env.behavior, .extra = options.env.extra },
    .working_directory = options.working_directory,
    .handle = { .in = child.in,
                .out = child.out,
                .err = child.err,
                .exit = (handle_type) child.exit }
  };

  r = process_start(&process->handle, argv, process_options);
  if (r < 0) {
    goto finish;
  }

  if (r > 0) {
    process->stop = options.stop;

    if (options.deadline != REPROC_INFINITE) {
      process->deadline = now() + options.deadline;
    }

    process->nonblocking = options.nonblocking;
  }

finish:
  // Either an error has ocurred or the child pipe endpoints have been copied to
  // the stdin/stdout/stderr streams of the child process. Either way, they can
  // be safely closed.
  redirect_destroy(child.in, options.redirect.in.type);

  // See `reproc_poll` for why we do this.

#ifdef _WIN32
  if (r < 0 || options.redirect.out.type != REPROC_REDIRECT_PIPE) {
    child.out = redirect_destroy(child.out, options.redirect.out.type);
  }

  if (r < 0 || options.redirect.err.type != REPROC_REDIRECT_PIPE) {
    child.err = redirect_destroy(child.err, options.redirect.err.type);
  }
#else
  child.out = redirect_destroy(child.out, options.redirect.out.type);
  child.err = redirect_destroy(child.err, options.redirect.err.type);
#endif

  pipe_destroy(child.exit);

  if (r < 0) {
    process->handle = process_destroy(process->handle);
    process->pipe.in = pipe_destroy(process->pipe.in);
    process->pipe.out = pipe_destroy(process->pipe.out);
    process->pipe.err = pipe_destroy(process->pipe.err);
    process->pipe.exit = pipe_destroy(process->pipe.exit);
    deinit();
  } else if (r == 0) {
    process->handle = PROCESS_INVALID;
    // `process_start` has already taken care of closing the handles for us.
    process->pipe.in = PIPE_INVALID;
    process->pipe.out = PIPE_INVALID;
    process->pipe.err = PIPE_INVALID;
    process->pipe.exit = PIPE_INVALID;
    process->status = STATUS_IN_CHILD;
  } else {
    process->child.out = (pipe_type) child.out;
    process->child.err = (pipe_type) child.err;
    process->status = STATUS_IN_PROGRESS;
  }

  return r;
}

enum { PIPES_PER_SOURCE = 4 };

static bool contains_valid_pipe(pipe_event_source *sources, size_t num_sources)
{
  for (size_t i = 0; i < num_sources; i++) {
    if (sources[i].pipe != PIPE_INVALID) {
      return true;
    }
  }

  return false;
}

int reproc_poll(reproc_event_source *sources, size_t num_sources, int timeout)
{
  ASSERT_EINVAL(sources);
  ASSERT_EINVAL(num_sources > 0);

  size_t earliest = find_earliest_deadline(sources, num_sources);
  int64_t deadline = sources[earliest].process == NULL
                         ? REPROC_INFINITE
                         : sources[earliest].process->deadline;

  int first = expiry(timeout, deadline);
  size_t num_pipes = num_sources * PIPES_PER_SOURCE;
  int r = REPROC_ENOMEM;

  if (first == REPROC_DEADLINE) {
    for (size_t i = 0; i < num_sources; i++) {
      sources[i].events = 0;
    }

    sources[earliest].events = REPROC_EVENT_DEADLINE;
    return 1;
  }

  pipe_event_source *pipes = calloc(num_pipes, sizeof(pipe_event_source));
  if (pipes == NULL) {
    return r;
  }

  for (size_t i = 0; i < num_pipes; i++) {
    pipes[i].pipe = PIPE_INVALID;
  }

  for (size_t i = 0; i < num_sources; i++) {
    size_t j = i * PIPES_PER_SOURCE;
    reproc_t *process = sources[i].process;
    int interests = sources[i].interests;

    if (process == NULL) {
      continue;
    }

    bool in = interests & REPROC_EVENT_IN;
    pipes[j + 0].pipe = in ? process->pipe.in : PIPE_INVALID;
    pipes[j + 0].interests = PIPE_EVENT_OUT;

    bool out = interests & REPROC_EVENT_OUT;
    pipes[j + 1].pipe = out ? process->pipe.out : PIPE_INVALID;
    pipes[j + 1].interests = PIPE_EVENT_IN;

    bool err = interests & REPROC_EVENT_ERR;
    pipes[j + 2].pipe = err ? process->pipe.err : PIPE_INVALID;
    pipes[j + 2].interests = PIPE_EVENT_IN;

    bool exit = (interests & REPROC_EVENT_EXIT) ||
                (interests & REPROC_EVENT_OUT &&
                 process->child.out != PIPE_INVALID) ||
                (interests & REPROC_EVENT_ERR &&
                 process->child.err != PIPE_INVALID);
    pipes[j + 3].pipe = exit ? process->pipe.exit : PIPE_INVALID;
    pipes[j + 3].interests = PIPE_EVENT_IN;
  }

  if (!contains_valid_pipe(pipes, num_pipes)) {
    r = REPROC_EPIPE;
    goto finish;
  }

  r = pipe_poll(pipes, num_pipes, first);
  if (r < 0) {
    goto finish;
  }

  for (size_t i = 0; i < num_sources; i++) {
    sources[i].events = 0;
  }

  if (r == 0 && first != timeout) {
    // Differentiate between timeout and deadline expiry. Deadline expiry is an
    // event, timeouts are not.
    sources[earliest].events = REPROC_EVENT_DEADLINE;
    r = 1;
  } else if (r > 0) {
    // Convert pipe events to process events.
    for (size_t i = 0; i < num_pipes; i++) {
      if (pipes[i].pipe == PIPE_INVALID) {
        continue;
      }

      if (pipes[i].events > 0) {
        // Index in a set of pipes determines the process pipe and thus the
        // process event.
        // 0 = stdin pipe => REPROC_EVENT_IN
        // 1 = stdout pipe => REPROC_EVENT_OUT
        // ...
        int event = 1 << (i % PIPES_PER_SOURCE);
        sources[i / PIPES_PER_SOURCE].events |= event;
      }
    }

    r = 0;

    // Count the number of processes with events.
    for (size_t i = 0; i < num_sources; i++) {
      r += sources[i].events > 0;
    }

    // On Windows, when redirecting to sockets, we keep the child handles alive
    // in the parent process (see `reproc_start`). We do this because Windows
    // doesn't correctly flush redirected socket handles when a child process
    // exits. This can lead to data loss where the parent process doesn't
    // receive all output of the child process. To get around this, we keep an
    // extra handle open in the parent process which we close correctly when we
    // detect the child process has exited. Detecting whether a child process
    // has exited happens via another inherited socket, but here there's no
    // danger of data loss because no data is received over this socket.

    bool again = false;

    for (size_t i = 0; i < num_sources; i++) {
      if (!(sources[i].events & REPROC_EVENT_EXIT)) {
        continue;
      }

      reproc_t *process = sources[i].process;

      if (process->child.out == PIPE_INVALID &&
          process->child.err == PIPE_INVALID) {
        continue;
      }

      r = pipe_shutdown(process->child.out);
      if (r < 0) {
        goto finish;
      }

      r = pipe_shutdown(process->child.err);
      if (r < 0) {
        goto finish;
      }

      process->child.out = pipe_destroy(process->child.out);
      process->child.err = pipe_destroy(process->child.err);
      again = true;
    }

    // If we've closed handles, we poll again so we can include any new close
    // events that occurred because we closed handles.

    if (again) {
      r = reproc_poll(sources, num_sources, timeout);
      if (r < 0) {
        goto finish;
      }
    }
  }

finish:
  free(pipes);

  return r;
}

int reproc_read(reproc_t *process,
                REPROC_STREAM stream,
                uint8_t *buffer,
                size_t size)
{
  ASSERT_EINVAL(process);
  ASSERT_EINVAL(process->status != STATUS_IN_CHILD);
  ASSERT_EINVAL(stream == REPROC_STREAM_OUT || stream == REPROC_STREAM_ERR);
  ASSERT_EINVAL(buffer);

  pipe_type *pipe = stream == REPROC_STREAM_OUT ? &process->pipe.out
                                                : &process->pipe.err;
  pipe_type child = stream == REPROC_STREAM_OUT ? process->child.out
                                                : process->child.err;
  int r = -1;

  if (*pipe == PIPE_INVALID) {
    return REPROC_EPIPE;
  }

  // If we've kept extra handles open in the parent, make sure we use
  // `reproc_poll` which closes the extra handles we keep open when the child
  // process exits. If we don't, `pipe_read` will block forever because the
  // extra handles we keep open in the parent would never be closed.
  if (child != PIPE_INVALID) {
    int event = stream == REPROC_STREAM_OUT ? REPROC_EVENT_OUT
                                            : REPROC_EVENT_ERR;
    reproc_event_source source = { process, event, 0 };
    r = reproc_poll(&source, 1, process->nonblocking ? 0 : REPROC_INFINITE);
    if (r <= 0) {
      return r == 0 ? -REPROC_EWOULDBLOCK : r;
    }
  }

  r = pipe_read(*pipe, buffer, size);

  if (r == REPROC_EPIPE) {
    *pipe = pipe_destroy(*pipe);
  }

  return r;
}

int reproc_write(reproc_t *process, const uint8_t *buffer, size_t size)
{
  ASSERT_EINVAL(process);
  ASSERT_EINVAL(process->status != STATUS_IN_CHILD);

  if (buffer == NULL) {
    // Allow `NULL` buffers but only if `size == 0`.
    ASSERT_EINVAL(size == 0);
    return 0;
  }

  if (process->pipe.in == PIPE_INVALID) {
    return REPROC_EPIPE;
  }

  int r = pipe_write(process->pipe.in, buffer, size);

  if (r == REPROC_EPIPE) {
    process->pipe.in = pipe_destroy(process->pipe.in);
  }

  return r;
}

int reproc_close(reproc_t *process, REPROC_STREAM stream)
{
  ASSERT_EINVAL(process);
  ASSERT_EINVAL(process->status != STATUS_IN_CHILD);

  switch (stream) {
    case REPROC_STREAM_IN:
      process->pipe.in = pipe_destroy(process->pipe.in);
      return 0;
    case REPROC_STREAM_OUT:
      process->pipe.out = pipe_destroy(process->pipe.out);
      return 0;
    case REPROC_STREAM_ERR:
      process->pipe.err = pipe_destroy(process->pipe.err);
      return 0;
  }

  return REPROC_EINVAL;
}

int reproc_wait(reproc_t *process, int timeout)
{
  ASSERT_EINVAL(process);
  ASSERT_EINVAL(process->status != STATUS_IN_CHILD);
  ASSERT_EINVAL(process->status != STATUS_NOT_STARTED);

  int r = -1;

  if (process->status >= 0) {
    return process->status;
  }

  if (timeout == REPROC_DEADLINE) {
    timeout = expiry(REPROC_INFINITE, process->deadline);
    // If the deadline has expired, `expiry` returns `REPROC_DEADLINE` which
    // means we'll only check if the process is still running.
    if (timeout == REPROC_DEADLINE) {
      timeout = 0;
    }
  }

  ASSERT(process->pipe.exit != PIPE_INVALID);

  pipe_event_source source = { .pipe = process->pipe.exit,
                               .interests = PIPE_EVENT_IN };

  r = pipe_poll(&source, 1, timeout);
  if (r <= 0) {
    return r == 0 ? REPROC_ETIMEDOUT : r;
  }

  r = process_wait(process->handle);
  if (r < 0) {
    return r;
  }

  process->pipe.exit = pipe_destroy(process->pipe.exit);

  return process->status = r;
}

int reproc_terminate(reproc_t *process)
{
  ASSERT_EINVAL(process);
  ASSERT_EINVAL(process->status != STATUS_IN_CHILD);
  ASSERT_EINVAL(process->status != STATUS_NOT_STARTED);

  if (process->status >= 0) {
    return 0;
  }

  return process_terminate(process->handle);
}

int reproc_kill(reproc_t *process)
{
  ASSERT_EINVAL(process);
  ASSERT_EINVAL(process->status != STATUS_IN_CHILD);
  ASSERT_EINVAL(process->status != STATUS_NOT_STARTED);

  if (process->status >= 0) {
    return 0;
  }

  return process_kill(process->handle);
}

int reproc_stop(reproc_t *process, reproc_stop_actions stop)
{
  ASSERT_EINVAL(process);
  ASSERT_EINVAL(process->status != STATUS_IN_CHILD);
  ASSERT_EINVAL(process->status != STATUS_NOT_STARTED);

  stop = parse_stop_actions(stop);

  reproc_stop_action actions[] = { stop.first, stop.second, stop.third };
  int r = -1;

  for (size_t i = 0; i < ARRAY_SIZE(actions); i++) {
    r = REPROC_EINVAL; // NOLINT

    switch (actions[i].action) {
      case REPROC_STOP_NOOP:
        r = 0;
        continue;
      case REPROC_STOP_WAIT:
        r = 0;
        break;
      case REPROC_STOP_TERMINATE:
        r = reproc_terminate(process);
        break;
      case REPROC_STOP_KILL:
        r = reproc_kill(process);
        break;
    }

    // Stop if `reproc_terminate` or `reproc_kill` fail.
    if (r < 0) {
      break;
    }

    r = reproc_wait(process, actions[i].timeout);
    if (r != REPROC_ETIMEDOUT) {
      break;
    }
  }

  return r;
}

int reproc_pid(reproc_t *process)
{
  ASSERT_EINVAL(process);
  ASSERT_EINVAL(process->status != STATUS_IN_CHILD);
  ASSERT_EINVAL(process->status != STATUS_NOT_STARTED);

  return process_pid(process->handle);
}

reproc_t *reproc_destroy(reproc_t *process)
{
  ASSERT_RETURN(process, NULL);

  if (process->status == STATUS_IN_PROGRESS) {
    reproc_stop(process, process->stop);
  }

  process_destroy(process->handle);
  pipe_destroy(process->pipe.in);
  pipe_destroy(process->pipe.out);
  pipe_destroy(process->pipe.err);
  pipe_destroy(process->pipe.exit);

  pipe_destroy(process->child.out);
  pipe_destroy(process->child.err);

  if (process->status != STATUS_NOT_STARTED) {
    deinit();
  }

  free(process);

  return NULL;
}

const char *reproc_strerror(int error)
{
  return error_string(error);
}

//
// run.c
//
int reproc_run(const char *const *argv, reproc_options options)
{
  if (!options.redirect.discard && !options.redirect.file &&
      !options.redirect.path) {
    options.redirect.parent = true;
  }

  return reproc_run_ex(argv, options, REPROC_SINK_NULL, REPROC_SINK_NULL);
}

int reproc_run_ex(const char *const *argv,
                  reproc_options options, // lgtm [cpp/large-parameter]
                  reproc_sink out,
                  reproc_sink err)
{
  reproc_t *process = NULL;
  int r = REPROC_ENOMEM;

  // There's no way for `reproc_run_ex` to inform the caller whether we're in
  // the forked process or the parent process so let's not allow forking when
  // using `reproc_run_ex`.
  ASSERT_EINVAL(!options.fork);

  process = reproc_new();
  if (process == NULL) {
    goto finish;
  }

  r = reproc_start(process, argv, options);
  if (r < 0) {
    goto finish;
  }

  r = reproc_drain(process, out, err);
  if (r < 0) {
    goto finish;
  }

  r = reproc_stop(process, options.stop);
  if (r < 0) {
    goto finish;
  }

finish:
  reproc_destroy(process);

  return r;
}

//
// strv.c
//
static char *str_dup(const char *s)
{
  ASSERT_RETURN(s, NULL);

  char *r = malloc(strlen(s) + 1);
  if (!r) {
    return NULL;
  }

  strcpy(r, s); // NOLINT

  return r;
}

char **strv_concat(char *const *a, const char *const *b)
{
  char *const *i = NULL;
  const char *const *j = NULL;
  size_t size = 1;
  size_t c = 0;

  STRV_FOREACH(i, a) {
    size++;
  }

  STRV_FOREACH(j, b) {
    size++;
  }

  char **r = calloc(size, sizeof(char *));
  if (!r) {
    goto finish;
  }

  STRV_FOREACH(i, a) {
    r[c] = str_dup(*i);
    if (!r[c]) {
      goto finish;
    }

    c++;
  }

  STRV_FOREACH(j, b) {
    r[c] = str_dup(*j);
    if (!r[c]) {
      goto finish;
    }

    c++;
  }

  r[c++] = NULL;

finish:
  if (c < size) {
    STRV_FOREACH(i, r) {
      free(*i);
    }

    free(r);

    return NULL;
  }

  return r;
}

char **strv_free(char **l)
{
  char **s = NULL;

  STRV_FOREACH(s, l) {
    free(*s);
  }

  free(l);

  return NULL;
}
