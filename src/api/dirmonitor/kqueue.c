#include <SDL3/SDL.h>
#include <sys/event.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>

struct dirmonitor_internal {
  int fd;
};


struct dirmonitor_internal* init_dirmonitor() {
  struct dirmonitor_internal* monitor = SDL_calloc(1, sizeof(struct dirmonitor_internal));
  monitor->fd = kqueue();
  return monitor;
}


void deinit_dirmonitor(struct dirmonitor_internal* monitor) {
  close(monitor->fd);
}


int get_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int buffer_size) {
  struct timespec ts = { 0, 100 * 1000000 }; // 100 ms

  int nev = kevent(monitor->fd, NULL, 0, (struct kevent*)buffer, buffer_size / sizeof(kevent), &ts);
  if (nev == -1)
    return -1;
  if (nev <= 0)
    return 0;
  return nev * sizeof(struct kevent);
}


int translate_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int buffer_size, int (*change_callback)(int, const char*, void*), void* data) {
  for (struct kevent* info = (struct kevent*)buffer; (char*)info < buffer + buffer_size; info = (struct kevent*)(((char*)info) + sizeof(kevent)))
    change_callback(info->ident, NULL, data);
  return 0;
}


int add_dirmonitor(struct dirmonitor_internal* monitor, const char* path) {
  int fd = open(path, O_RDONLY);
  struct kevent change;

  // a timeout of zero should make kevent return immediately
  struct timespec ts = { 0, 0 }; // 0 s

  EV_SET(&change, fd, EVFILT_VNODE, EV_ADD | EV_CLEAR, NOTE_DELETE | NOTE_EXTEND | NOTE_WRITE | NOTE_ATTRIB | NOTE_LINK | NOTE_RENAME, 0, (void*)path);
  kevent(monitor->fd, &change, 1, NULL, 0, &ts);

  return fd;
}


void remove_dirmonitor(struct dirmonitor_internal* monitor, int fd) {
  close(fd);
}


int get_mode_dirmonitor() { return 2; }
