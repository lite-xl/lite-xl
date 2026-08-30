#include <SDL3/SDL.h>
#include <sys/inotify.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>


struct dirmonitor_internal {
  int fd;
  // a pipe is used to wake the thread in case of exit
  int sig[2];
};


struct dirmonitor_internal* init_dirmonitor() {
  struct dirmonitor_internal* monitor = SDL_calloc(1, sizeof(struct dirmonitor_internal));
  if (!monitor)
    return NULL;
  monitor->fd = inotify_init();
  // keep the fds at -1 when unavailable so deinit_dirmonitor() doesn't
  // close(0)/close(1) if inotify_init() or pipe() fails
  if (pipe(monitor->sig) != 0) {
    monitor->sig[0] = monitor->sig[1] = -1;
  } else {
    fcntl(monitor->sig[0], F_SETFD, FD_CLOEXEC);
    fcntl(monitor->sig[1], F_SETFD, FD_CLOEXEC);
  }
  return monitor;
}


void deinit_dirmonitor(struct dirmonitor_internal* monitor) {
  // fds are -1 rather than 0 when inotify_init()/pipe() failed, so this
  // never closes stdin/stdout by accident
  if (monitor->fd >= 0) close(monitor->fd);
  if (monitor->sig[0] >= 0) close(monitor->sig[0]);
  if (monitor->sig[1] >= 0) close(monitor->sig[1]);
}


int get_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int length) {
  struct pollfd fds[2] = { { .fd = monitor->fd, .events = POLLIN | POLLERR, .revents = 0 }, { .fd = monitor->sig[0], .events = POLLIN | POLLERR, .revents = 0 } };
  poll(fds, 2, -1);
  return read(monitor->fd, buffer, length);
}


int translate_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int length, int (*change_callback)(int, const char*, void*), void* data) {
  for (struct inotify_event* info = (struct inotify_event*)buffer; (char*)info < buffer + length; info = (struct inotify_event*)((char*)info + sizeof(struct inotify_event))) {
    if ((info->mask & (~IN_IGNORED)) > 0)
      change_callback(info->wd, NULL, data);
  }
  return 0;
}


int add_dirmonitor(struct dirmonitor_internal* monitor, const char* path) {
  return inotify_add_watch(monitor->fd, path, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MODIFY | IN_MOVED_TO);
}


void remove_dirmonitor(struct dirmonitor_internal* monitor, int fd) {
  inotify_rm_watch(monitor->fd, fd);
}


int get_mode_dirmonitor() { return 2; }
