#include <sys/event.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

struct dirmonitor {
  int fd;
};

struct dirmonitor* init_dirmonitor_kqueue() {
  struct dirmonitor* monitor = calloc(sizeof(struct dirmonitor), 1);
  monitor->fd = kqueue();
  return monitor;
}

void deinit_dirmonitor_kqueue(struct dirmonitor* monitor) {
  close(monitor->fd);
  free(monitor);
}

int check_dirmonitor_kqueue(struct dirmonitor* monitor, int (*change_callback)(int, const char*, void*), void* data) {
  struct kevent event;
  while (1) {
    struct timespec tm = {0};
    int nev = kevent(monitor->fd, NULL, 0, &event, 1, &tm);

    if (nev == -1) {
      return errno;
    }

    if (nev <= 0) {
      return 0;
    }

    change_callback(event.ident, NULL, data);
  }
}

int add_dirmonitor_kqueue(struct dirmonitor* monitor, const char* path) {
  int fd = open(path, O_RDONLY);
  struct kevent change;

  EV_SET(&change, fd, EVFILT_VNODE, EV_ADD | EV_CLEAR, NOTE_DELETE | NOTE_EXTEND | NOTE_WRITE | NOTE_ATTRIB | NOTE_LINK | NOTE_RENAME, 0, (void*)path);
  kevent(monitor->fd, &change, 1, NULL, 0, NULL);

  return fd;
}

void remove_dirmonitor_kqueue(struct dirmonitor* monitor, int fd) {
  close(fd);
}