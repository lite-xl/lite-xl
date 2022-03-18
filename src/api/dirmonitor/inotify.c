#include <sys/inotify.h>
#include <limits.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>

struct dirmonitor {
  int fd;
};

struct dirmonitor* init_dirmonitor_inotify() {
  struct dirmonitor* monitor = calloc(sizeof(struct dirmonitor), 1);

  monitor->fd = inotify_init();
  fcntl(monitor->fd, F_SETFL, O_NONBLOCK);


  return monitor;
}

void deinit_dirmonitor_inotify(struct dirmonitor* monitor) {
  close(monitor->fd);
  free(monitor);
}

int check_dirmonitor_inotify(struct dirmonitor* monitor, int (*change_callback)(int, const char*, void*), void* data) {
  char buf[PATH_MAX + sizeof(struct inotify_event)];
  ssize_t offset = 0;

  while (1) {
    ssize_t len = read(monitor->fd, &buf[offset], sizeof(buf) - offset);

    if (len == -1 && errno != EAGAIN) {
      return errno;
    }

    if (len <= 0) {
      return 0;
    }

    while (len > sizeof(struct inotify_event) && len >= ((struct inotify_event*)buf)->len + sizeof(struct inotify_event)) {
      change_callback(((const struct inotify_event *)buf)->wd, NULL, data);
      len -= sizeof(struct inotify_event) + ((struct inotify_event*)buf)->len;
      memmove(buf, &buf[sizeof(struct inotify_event) + ((struct inotify_event*)buf)->len], len);
      offset = len;
    }
  }
}

int add_dirmonitor_inotify(struct dirmonitor* monitor, const char* path) {
  return inotify_add_watch(monitor->fd, path, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO);
}

void remove_dirmonitor_inotify(struct dirmonitor* monitor, int fd) {
  inotify_rm_watch(monitor->fd, fd);
}