#ifndef PROCESS_H
#define PROCESS_H

#include <stdbool.h>

typedef struct process_s process_t;

typedef enum {
  PROCESS_ENV_EXTEND,
  PROCESS_ENV_CLEAR,
} process_env_action_t;

typedef enum {
  PROCESS_REDIRECT_DEFAULT,
  PROCESS_REDIRECT_PIPE,
  PROCESS_REDIRECT_PARENT,
  PROCESS_REDIRECT_DISCARD,
  PROCESS_REDIRECT_STDOUT,
} process_redirect_t;

typedef enum {
  PROCESS_STDOUT,
  PROCESS_STDERR,
  PROCESS_STDIN,
} process_stream_t;

extern int PROCESS_SIGTERM;
extern int PROCESS_SIGKILL;
extern int PROCESS_SIGINT;

process_t *process_new(void);
int process_start(process_t *proc,
                  const char **argv, const char *cwd,
                  const char *env, process_env_action_t action,
                  process_redirect_t pipe[3], int timeout,
                  bool detach, bool verbatim_arguments);
int process_read(process_t *proc, process_stream_t stream,
                char *buf, int buf_size);
int process_write(process_t *proc, char *buf, int buf_size);
int process_signal(process_t *proc, int sig);
int process_poll(process_t *proc);
void process_free(process_t *proc);

char *process_strerror(int err);
void *process_strerror_free(char *err);

#endif
