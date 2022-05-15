#include <sys/inotify.h>
#include <sys/select.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>


struct dirmonitor_internal {
  int fd;
  // a pipe is used to wake the thread in case of exit
  int sig[2];
};


struct dirmonitor_internal* init_dirmonitor() {
  struct dirmonitor_internal* monitor = calloc(sizeof(struct dirmonitor_internal), 1);
  monitor->fd = inotify_init();
  pipe(monitor->sig);
  fcntl(monitor->sig[0], F_SETFD, FD_CLOEXEC);
  fcntl(monitor->sig[1], F_SETFD, FD_CLOEXEC);
  return monitor;
}


void deinit_dirmonitor(struct dirmonitor_internal* monitor) {
  close(monitor->fd);
  close(monitor->sig[0]);
  close(monitor->sig[1]);
}


int get_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int length) {
  fd_set set;
  FD_ZERO(&set);
  FD_SET(monitor->fd, &set);
  FD_SET(monitor->sig[0], &set);
  select(FD_SETSIZE, &set, NULL, NULL, NULL);
  return read(monitor->fd, buffer, length);
}


int translate_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int length, int (*change_callback)(int, const char*, void*), void* data) {
  for (struct inotify_event* info = (struct inotify_event*)buffer; (char*)info < buffer + length; info = (struct inotify_event*)((char*)info + sizeof(struct inotify_event)))
    change_callback(info->wd, NULL, data);
  return 0;
}


int add_dirmonitor(struct dirmonitor_internal* monitor, const char* path) {
  return inotify_add_watch(monitor->fd, path, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MODIFY | IN_MOVED_TO);
}


void remove_dirmonitor(struct dirmonitor_internal* monitor, int fd) {
  inotify_rm_watch(monitor->fd, fd);
}
