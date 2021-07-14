#ifndef DIRMONITOR_H
#define DIRMONITOR_H

#include <stdint.h>

#include "dmon.h"

void dirmonitor_init();
void dirmonitor_deinit();
void dirmonitor_push_event(dmon_watch_id watch_id, dmon_action action, const char *filepath,
  const char *oldfilepath);

#endif

