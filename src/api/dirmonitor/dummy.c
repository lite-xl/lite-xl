#include <stdlib.h>

struct dirmonitor {
};

struct dirmonitor* init_dirmonitor_dummy() {
  return NULL;
}

void deinit_dirmonitor_dummy(struct dirmonitor* monitor) {
}

int check_dirmonitor_dummy(struct dirmonitor* monitor, int (*change_callback)(int, const char*, void*), void* data) {
  return -1;
}

int add_dirmonitor_dummy(struct dirmonitor* monitor, const char* path) {
  return -1;
}

void remove_dirmonitor_dummy(struct dirmonitor* monitor, int fd) {
}