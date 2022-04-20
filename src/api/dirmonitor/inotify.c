#include <sys/inotify.h>
#include <stdlib.h>
#include <errno.h>
#include <unistd.h>


struct dirmonitor_internal {
  int fd;
};


struct dirmonitor_internal* init_dirmonitor() {
  struct dirmonitor_internal* monitor = calloc(sizeof(struct dirmonitor_internal), 1);
  monitor->fd = inotify_init();
  return monitor;
}


void deinit_dirmonitor(struct dirmonitor_internal* monitor) {
  close(monitor->fd);
}


int get_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int length) {
  return read(monitor->fd, buffer, length);
}


int translate_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int length, int (*change_callback)(int, const char*, void*), void* data) {
  for (struct inotify_event* info = (struct inotify_event*)buffer; (char*)info < buffer + length; info = (struct inotify_event*)((char*)info + sizeof(struct inotify_event)))
    change_callback(info->wd, NULL, data);
  return 0;
}


int add_dirmonitor(struct dirmonitor_internal* monitor, const char* path) {
  return inotify_add_watch(monitor->fd, path, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO);
}


void remove_dirmonitor(struct dirmonitor_internal* monitor, int fd) {
  inotify_rm_watch(monitor->fd, fd);
}
