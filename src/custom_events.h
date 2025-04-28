#ifndef CUSTOM_EVENTS_H
#define CUSTOM_EVENTS_H

#include <stdbool.h>
#include <stdint.h>

typedef enum {
  CUSTOM_EVENT_DIRMONITOR = 0,
  CUSTOM_EVENT_DIALOG,
  CUSTOM_EVENT_LAST,
} CustomEventTypes;

bool register_custom_events();
uint32_t get_custom_event(CustomEventTypes type);

#endif // CUSTOM_EVENTS_H
