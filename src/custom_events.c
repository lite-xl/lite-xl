#include "custom_events.h"
#include <SDL3/SDL.h>
#include <stdbool.h>
#include <stddef.h>

#define TYPENAME_MARKER '#'

// We use an SDL property to keep track of custom events, identified by their name.
//
// The name is mapped to a CustomEventData object, which contains the CustomEventCallback
// called when the event is pulled by the event loop.
// The name cannot start with '#'.
//
// We also map the event type to the event name using a name generated from the
// event type. The generated name starts with '#'.
// We map this event type using the same property as above to avoid races, as SDL
// doesn't currently have a way to lock multiple properties at once.
// This mapping is needed to retrieve the CustomEventData associated with the event type.
//
// The CustomEventCallback receives the Lua state and the event data.
// The callback shall return the number of elements pushed to the Lua stack
// that will be returned to the event handler.
// The first element should be the event name, followed by any extra value needed.
// If 0 is returned, nothing is sent to the event handler.

typedef struct {
  uint32_t type;
  CustomEventCallback callback;
} CustomEventData;

// The event type is uint32_t, 2^32 in base 36 is 7 characters, plus initial #, plus NULL terminator
typedef char EventTypeName[9];

SDL_PropertiesID custom_events_property;

static int noop(lua_State *L, SDL_Event *event) {
  return 0;
}

bool init_custom_events(void) {
  custom_events_property = SDL_CreateProperties();
  return custom_events_property != 0;
}

void free_custom_events(void) {
  SDL_DestroyProperties(custom_events_property);
}

// Automatically called by SDL to free CustomEventData when it is cleared
static void cleanup_property_callback(void *userdata, void *value) {
  SDL_free(value);
}

static void type_to_typename(uint32_t event_type, EventTypeName typename) {
  typename[0] = TYPENAME_MARKER;
  // Using base36 to reduce waste
  // 36 is the max it supports
  SDL_itoa(event_type, &typename[1], 36);
}

bool register_custom_event(const char *name, CustomEventCallback callback) {
  bool res = false;
  if (name == NULL || name[0] == '\0') {
    SDL_SetError("Invalid event name");
    return false;
  }

  if (name[0] == TYPENAME_MARKER) {
    SDL_SetError("Invalid event name, can't start with #");
    return false;
  }

  if (!SDL_LockProperties(custom_events_property)) {
    return false;
  }

  CustomEventData *ced = SDL_GetPointerProperty(custom_events_property, name, NULL);
  if (ced != NULL) {
    // Overriding callback
    ced->callback = callback;
    res = true;
    goto end;
  }

  ced = SDL_malloc(sizeof(CustomEventData));
  if (ced == NULL) {
    goto end;
  }

  ced->callback = callback;
  ced->type = SDL_RegisterEvents(1);
  if (ced->type == 0) {
    SDL_free(ced);
    goto end;
  }

  // Let's generate a "name" from the id
  EventTypeName event_typename;
  type_to_typename(ced->type, event_typename);
  if (!SDL_SetStringProperty(custom_events_property, event_typename, name)) {
    SDL_free(ced);
    goto end;
  }

  // The cleanup function is also called if setting the property fails for any reason
  res = SDL_SetPointerPropertyWithCleanup(custom_events_property, name, ced, cleanup_property_callback, NULL);
  if (!res) {
    SDL_ClearProperty(custom_events_property, event_typename);
  }

end:
  SDL_UnlockProperties(custom_events_property);
  return res;
}

bool push_custom_event(const char *name, CustomEvent *event) {
  if (name == NULL || name[0] == '\0' || name[0] == TYPENAME_MARKER) {
    SDL_SetError("Invalid event name");
    return false;
  }

  CustomEventData *ced = SDL_GetPointerProperty(custom_events_property, name, NULL);
  if (ced == NULL) {
    SDL_SetError("Unknown custom event %s", name);
    return false;
  }

  SDL_Event sdl_event;
  SDL_zero(sdl_event);
  sdl_event.user.type = ced->type;
  sdl_event.user.windowID = event->windowID;
  sdl_event.user.code = event->code;
  sdl_event.user.data1 = event->data1;
  sdl_event.user.data2 = event->data2;

  return SDL_PushEvent(&sdl_event);
}

CustomEventCallback get_custom_event_callback_by_name(const char *name) {
  if (name == NULL || name[0] == '\0' || name[0] == TYPENAME_MARKER) {
    SDL_SetError("Invalid event name");
    return NULL;
  }

  CustomEventData *ce = SDL_GetPointerProperty(custom_events_property, name, NULL);
  if (ce == NULL) return NULL;
  return ce->callback != NULL ? ce->callback : noop;
}

CustomEventCallback get_custom_event_callback_by_type(uint32_t event_type) {
  EventTypeName event_typename;
  type_to_typename(event_type, event_typename);

  const char* name = SDL_GetStringProperty(custom_events_property, event_typename, NULL);
  if (name == NULL) {
    return NULL;
  }

  return get_custom_event_callback_by_name(name);
}

const char *get_custom_event_name(uint32_t event_type) {
  EventTypeName event_typename;
  type_to_typename(event_type, event_typename);

  return SDL_GetStringProperty(custom_events_property, event_typename, NULL);
}
