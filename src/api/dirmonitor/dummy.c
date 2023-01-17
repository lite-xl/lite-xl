#include <stdlib.h>

struct dirmonitor_internal* init_dirmonitor() { return NULL; }
void deinit_dirmonitor(struct dirmonitor_internal* monitor) { }
int get_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int len) { return -1; }
int translate_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int size, int (*callback)(int, const char*, void*), void* data) { return -1; }
int add_dirmonitor(struct dirmonitor_internal* monitor, const char* path) { return -1; }
void remove_dirmonitor(struct dirmonitor_internal* monitor, int fd) { }
int get_mode_dirmonitor() { return 1; }
