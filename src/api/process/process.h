#ifndef PROCESS_H
#define PROCESS_H

#include <stdbool.h>

typedef struct process_s process_t;

typedef enum {
  PROCESS_ENV_EXTEND,
  PROCESS_ENV_REPLACE,
} process_env_action_t;

typedef enum {
  PROCESS_REDIRECT_DEFAULT,
  PROCESS_REDIRECT_PIPE,
  PROCESS_REDIRECT_PARENT,
  PROCESS_REDIRECT_DISCARD,
  PROCESS_REDIRECT_STDOUT,
} process_redirect_t;

typedef enum {
  PROCESS_STDIN,
  PROCESS_STDOUT,
  PROCESS_STDERR,
} process_stream_t;

typedef enum {
  PROCESS_INFINITE = -1,
  PROCESS_DEADLINE = -2
} process_wait_type_t;

extern const int PROCESS_SIGTERM;
extern const int PROCESS_SIGKILL;
extern const int PROCESS_SIGINT;

extern const int PROCESS_EINVAL;
extern const int PROCESS_ENOMEM;
extern const int PROCESS_EPIPE;
extern const int PROCESS_EWOULDBLOCK;

process_t *process_new(void);
int process_start(process_t *proc,
                  const char **argv, const char *cwd,
                  const char **env, process_env_action_t action,
                  process_redirect_t pipe[3], int timeout,
                  bool detach, bool verbatim_arguments);
int process_read(process_t *proc, process_stream_t stream,
                char *buf, int buf_size);
int process_write(process_t *proc, char *buf, int buf_size);
int process_signal(process_t *proc, int sig);
int process_returncode(process_t *proc);
int process_poll(process_t *proc, int timeout);
void process_free(process_t *proc);

char *process_strerror(int err);
void *process_strerror_free(char *err);

#endif
