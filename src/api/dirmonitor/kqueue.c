#include <sys/event.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>

struct dirmonitor_internal {
  int fd;
};


struct dirmonitor* init_dirmonitor() {
  struct dirmonitor* monitor = calloc(sizeof(struct dirmonitor), 1);
  monitor->fd = kqueue();
  return monitor;
}


void deinit_dirmonitor(struct dirmonitor* monitor) {
  close(monitor->fd);
}


int get_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int buffer_size) {
  int nev = kevent(monitor->fd, NULL, 0, (kevent*)buffer, buffer_size / sizeof(kevent), NULL);
  if (nev == -1)
    return -1;
  if (nev <= 0)
    return 0;
  return nev * sizeof(kevent);
}


int translate_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int buffer_size, int (*change_callback)(int, const char*, void*), void* data) {
  for (kevent* info = (kevent*)buffer; (char*)info < buffer + buffer_size; info = (kevent*)(((char*)info) + sizeof(kevent)))
    change_callback(info->ident, NULL, data);
  return 0;
}


int add_dirmonitor(struct dirmonitor* monitor, const char* path) {
  int fd = open(path, O_RDONLY);
  struct kevent change;

  EV_SET(&change, fd, EVFILT_VNODE, EV_ADD | EV_CLEAR, NOTE_DELETE | NOTE_EXTEND | NOTE_WRITE | NOTE_ATTRIB | NOTE_LINK | NOTE_RENAME, 0, (void*)path);
  kevent(monitor->fd, &change, 1, NULL, 0, NULL);

  return fd;
}


void remove_dirmonitor(struct dirmonitor* monitor, int fd) {
  close(fd);
}
