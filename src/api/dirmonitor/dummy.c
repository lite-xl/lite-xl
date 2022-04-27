#include <stdlib.h>

struct dirmonitor_internal* init_dirmonitor() { return NULL; }
void deinit_dirmonitor(struct dirmonitor_internal*) { }
int get_changes_dirmonitor(struct dirmonitor_internal*, char*, size_t) { return -1; }
int translate_changes_dirmonitor(struct dirmonitor_internal*, char*, int, int (*)(int, const char*, void*), void*) { return -1; }
int add_dirmonitor(struct dirmonitor_internal*, const char*) { return -1; }
void remove_dirmonitor(struct dirmonitor_internal*, int) { }
