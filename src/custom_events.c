#include "custom_events.h"
#include <stdbool.h>
#include <stddef.h>
#include <SDL3/SDL_events.h>

uint32_t custom_events[CUSTOM_EVENT_LAST];

bool register_custom_events() {
  uint32_t base_event = SDL_RegisterEvents(CUSTOM_EVENT_LAST);
  if (base_event == 0) {
    return false;
  }

  for (size_t i = 0; i < CUSTOM_EVENT_LAST; i++) {
    custom_events[i] = base_event + i;
  }
  return true;
}

uint32_t get_custom_event(CustomEventTypes type) {
  if (type >= CUSTOM_EVENT_LAST) {
    return 0;
  }
  return custom_events[type];
}
