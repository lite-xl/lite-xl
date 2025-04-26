#include <SDL3/SDL.h>
#include <AK/NumericLimits.h>
#include <Kernel/API/InodeWatcherEvent.h>
#include <Kernel/API/InodeWatcherFlags.h>
#include <cstring>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>

extern "C" {
struct dirmonitor_internal* init_dirmonitor();
void deinit_dirmonitor(struct dirmonitor_internal*);
int get_changes_dirmonitor(struct dirmonitor_internal*, char*, int);
int translate_changes_dirmonitor(struct dirmonitor_internal*, char*, int, int (*)(int, const char*, void*), void*);
int add_dirmonitor(struct dirmonitor_internal*, const char*);
void remove_dirmonitor(struct dirmonitor_internal*, int);
int get_mode_dirmonitor();
}

struct dirmonitor_internal {
  int fd;
  // a pipe is used to wake the thread in case of exit
  int sig[2];
};


struct dirmonitor_internal* init_dirmonitor() {
  struct dirmonitor_internal* monitor = (struct dirmonitor_internal*)SDL_calloc(sizeof(struct dirmonitor_internal), 1);
  monitor->fd = create_inode_watcher(0);
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
  struct pollfd fds[2] = { { .fd = monitor->fd, .events = POLLIN | POLLERR, .revents = 0 }, { .fd = monitor->sig[0], .events = POLLIN | POLLERR, .revents = 0 } };
  poll(fds, 2, -1);
  return read(monitor->fd, buffer, length);
}


int translate_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int length, int (*change_callback)(int, const char*, void*), void* data) {
  InodeWatcherEvent* event = (InodeWatcherEvent*)buffer;
  change_callback(event->watch_descriptor, NULL, data);
  return 0;
}


int add_dirmonitor(struct dirmonitor_internal* monitor, const char* path) {
  return inode_watcher_add_watch(monitor->fd, path, strlen(path),
      static_cast<unsigned>(
        InodeWatcherEvent::Type::MetadataModified |
        InodeWatcherEvent::Type::ContentModified |
        InodeWatcherEvent::Type::Deleted |
        InodeWatcherEvent::Type::ChildCreated |
        InodeWatcherEvent::Type::ChildDeleted
      ));
}


void remove_dirmonitor(struct dirmonitor_internal* monitor, int fd) {
  inode_watcher_remove_watch(monitor->fd, fd);
}

int get_mode_dirmonitor() { return 2; }
