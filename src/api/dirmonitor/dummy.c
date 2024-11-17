#include <stdlib.h>

#include "dirmonitor.h"

static struct dirmonitor_internal* init_dirmonitor() { return NULL; }
static void deinit_dirmonitor(struct dirmonitor_internal* monitor) { }
static int get_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int len) { return -1; }
static int translate_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int size, int (*callback)(int, const char*, void*), void* data) { return -1; }
static int add_dirmonitor(struct dirmonitor_internal* monitor, const char* path) { return -1; }
static void remove_dirmonitor(struct dirmonitor_internal* monitor, int fd) { }
static int get_mode_dirmonitor() { return 1; }

struct dirmonitor_backend dirmonitor_dummy = {
  .name = "dummy",
  .init = init_dirmonitor,
  .deinit = deinit_dirmonitor,
  .get_changes = get_changes_dirmonitor,
  .translate_changes = translate_changes_dirmonitor,
  .add = add_dirmonitor,
  .remove = remove_dirmonitor,
  .get_mode = get_mode_dirmonitor,
};
