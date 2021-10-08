#ifndef DIRMONITOR_H
#define DIRMONITOR_H

#include <stdint.h>

#include "dmon.h"
#include "dmon_extra.h"

void dirmonitor_init();
void dirmonitor_deinit();
void dirmonitor_watch_callback(dmon_watch_id watch_id, dmon_action action, const char *rootdir,
  const char *filepath, const char *oldfilepath, void *user);

#endif

