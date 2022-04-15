#include <SDL.h>
#include <sys/inotify.h>
#include <limits.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <aio.h>
#include <signal.h>

enum EState {
  MONITOR_STATE_READY,
  MONITOR_STATE_WAITING,
  MONITOR_STATE_COMPLETE
};

struct dirmonitor {
  struct aiocb cb;
  char buffer[(PATH_MAX + sizeof(struct inotify_event)) * 16];
  int buffer_length;
  enum EState state;
};

static unsigned int DIR_EVENT_TYPE = 0;
static void dirmonitor_notify(int sig, siginfo_t * info, void * udata) {
  struct dirmonitor* monitor = info->si_ptr;
  monitor->state = MONITOR_STATE_COMPLETE;
  ssize_t len = aio_return(&monitor->cb);
  if (len >= 0) {
    monitor->buffer_length += len;
    SDL_Event event = { .type = DIR_EVENT_TYPE };
    SDL_PushEvent(&event);
  } else
    monitor->buffer_length = 0;
}


struct dirmonitor* init_dirmonitor_inotify() {
  struct dirmonitor* monitor = calloc(sizeof(struct dirmonitor), 1);
  if (DIR_EVENT_TYPE == 0)
    DIR_EVENT_TYPE = SDL_RegisterEvents(1);
  monitor->cb.aio_fildes = inotify_init();
  monitor->cb.aio_sigevent.sigev_notify = SIGEV_SIGNAL;
  monitor->cb.aio_sigevent.sigev_signo = SIGUSR1;
  monitor->cb.aio_sigevent.sigev_value.sival_ptr = monitor;
  struct sigaction sigac = {0};
  sigac.sa_flags = SA_SIGINFO;
  sigac.sa_sigaction = dirmonitor_notify;
  sigaction(SIGUSR1, &sigac, NULL);
  return monitor;
}

void deinit_dirmonitor_inotify(struct dirmonitor* monitor) {
  close(monitor->cb.aio_fildes);
  free(monitor);
}

int check_dirmonitor_inotify(struct dirmonitor* monitor, int (*change_callback)(int, const char*, void*), void* data) {
  if (monitor->state == MONITOR_STATE_WAITING) 
    return 0;
  if (monitor->state == MONITOR_STATE_COMPLETE) {
    while (monitor->buffer_length > sizeof(struct inotify_event) && monitor->buffer_length >= ((struct inotify_event*)monitor->buffer)->len + sizeof(struct inotify_event)) {
      change_callback(((const struct inotify_event *)monitor->buffer)->wd, NULL, data);
      monitor->buffer_length -= sizeof(struct inotify_event) + ((struct inotify_event*)monitor->buffer)->len;
      memmove(monitor->buffer, &monitor->buffer[sizeof(struct inotify_event) + ((struct inotify_event*)monitor->buffer)->len], monitor->buffer_length);
    }
    monitor->state = MONITOR_STATE_READY;
  }
  monitor->cb.aio_buf = &monitor->buffer[monitor->buffer_length];
  monitor->cb.aio_nbytes = sizeof(monitor->buffer) - monitor->buffer_length;
  if (aio_read(&monitor->cb) == 0) {
    monitor->state = MONITOR_STATE_WAITING;
    return 0;
  }
  return errno;
}

int add_dirmonitor_inotify(struct dirmonitor* monitor, const char* path) {
  return inotify_add_watch(monitor->cb.aio_fildes, path, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO);
}

void remove_dirmonitor_inotify(struct dirmonitor* monitor, int fd) {
  inotify_rm_watch(monitor->cb.aio_fildes, fd);
}
