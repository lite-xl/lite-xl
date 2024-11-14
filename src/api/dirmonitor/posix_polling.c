#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <time.h>
#include <SDL.h>

#define EVENT_MODIFIED (1 << 0)

#if _BSD_SOURCE || _SVID_SOURCE || _XOPEN_SOURCE > 700 || _POSIX_C_SOURCE >= 200809L
#define STAT_HAS_TIM
#endif

struct file_info {
  int fd;
  dev_t dev;
  ino_t ino;
  struct timespec mtim;
  int events;
};

struct dirmonitor_internal {
  struct file_info* fds;
  size_t fd_count;
};

  
struct dirmonitor_internal* init_dirmonitor() {
  struct dirmonitor_internal* monitor = calloc(1, sizeof(struct dirmonitor_internal));

  monitor->fd_count = 0;
  monitor->fds = NULL;
  return monitor;
}

void deinit_dirmonitor(struct dirmonitor_internal* monitor) {
  for (size_t i = 0; i < monitor->fd_count; ++i)
    close(monitor->fds[i].fd);
  free(monitor->fds);
}

int get_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int len)
{
  struct stat new_stat;
  int c = 0;

  for (size_t i = 0; i < monitor->fd_count; ++i) {
    if (monitor->fds[i].fd < 0)
      continue;

    fstat(monitor->fds[i].fd, &new_stat);

    if (
      new_stat.st_mtime > monitor->fds[i].mtim.tv_sec ||
#ifdef STAT_HAS_TIM
      (new_stat.st_mtim.tv_sec == monitor->fds[i].mtim.tv_sec && new_stat.st_mtim.tv_nsec > monitor->fds[i].mtim.tv_nsec) ||
#endif
      new_stat.st_dev != monitor->fds[i].dev || // device changed
      new_stat.st_ino != monitor->fds[i].ino || // inode changed
      0
    ) {
      monitor->fds[i].mtim.tv_sec = new_stat.st_mtime;
#ifdef STAT_HAS_TIM
      monitor->fds[i].mtim.tv_nsec = new_stat.st_mtim.tv_nsec;
#endif
      monitor->fds[i].dev = new_stat.st_dev;
      monitor->fds[i].ino = new_stat.st_ino;
      monitor->fds[i].events |= EVENT_MODIFIED;
      c += 1;
    }
  }

  if (!c)
    SDL_Delay(100);

  return c;
}

int translate_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int count, int (*change_callback)(int, const char*, void*), void* data) {
  for (size_t i = 0; i < monitor->fd_count; ++i) {
    if (monitor->fds[i].events & EVENT_MODIFIED) {
      --count;
      monitor->fds[i].events = monitor->fds[i].events & ~ EVENT_MODIFIED;
      change_callback(monitor->fds[i].fd, NULL, data);
    }
  }

  return 0;
}

int add_dirmonitor(struct dirmonitor_internal* monitor, const char* path)
{
  int fd = open(path, O_RDONLY | O_NOFOLLOW);
  if (fd == -1)
    return -1;

  // Check if there is any space we can reuse
  for (size_t i = 0; i < monitor->fd_count; ++i) {
    if (monitor->fds[i].fd == -1) {
      monitor->fds[i].fd = fd;
      monitor->fds[i].mtim.tv_sec = 0;
      return fd;
    }
  }

  // There is no empty space, add a new entry;
  // Prepare a new list before switching it to prevent race conditions
  struct file_info* old_fds = monitor->fds;
  struct file_info* new_fds;
  new_fds = malloc(sizeof(*new_fds) * (monitor->fd_count + 1));
  if (old_fds)
    memcpy(new_fds, old_fds, sizeof(*new_fds) * (monitor->fd_count));

  new_fds[monitor->fd_count].fd = fd;
  new_fds[monitor->fd_count].mtim.tv_sec = 0;

  monitor->fds = new_fds;
  free(old_fds);

  monitor->fd_count++;

  return fd;
}

void remove_dirmonitor(struct dirmonitor_internal* monitor, int fd)
{
  for (size_t i = 0; i < monitor->fd_count; ++i) {
    if (monitor->fds[i].fd == fd) {
      int fd = monitor->fds[i].fd;

      monitor->fds[i].fd = -1;
      monitor->fds[i].events = 0;
      close(fd);
      return;
    }
  }
}

int get_mode_dirmonitor() {
  return 2;
}
