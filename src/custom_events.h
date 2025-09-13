#ifndef CUSTOM_EVENTS_H
#define CUSTOM_EVENTS_H

#include <lua.h>
#include <SDL3/SDL_events.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct {
  SDL_WindowID windowID;
  int32_t code;
  void *data1;
  void *data2;
} CustomEvent;

typedef int (*CustomEventCallback)(lua_State *L, SDL_Event *);

bool init_custom_events(void);

// Only call this function after all returned callback functions/strings are
// not needed anymore, as they will get freed.
void free_custom_events(void);

// Registers a custom event, identified by the provided name.
//
// The name must be unique and must not start with '#'.
// If the event already exists, its callback will be overridden.
// The callback can be NULL.
bool register_custom_event(const char *name, CustomEventCallback callback);

// Pushes an event with the given name.
// When this event is received by the event loop, the registered callback will be called.
bool push_custom_event(const char *name, CustomEvent *event);

// Returns the registered callback of the given event_type.
//
// Returns NULL only if the event doesn't exist.
// If the event didn't have a callback, a noop callback will be returned.
CustomEventCallback get_custom_event_callback_by_type(uint32_t event_type);

// Returns the registered callback of the given name.
//
// Returns NULL only if the event doesn't exist.
// If the event didn't have a callback, a noop callback will be returned.
CustomEventCallback get_custom_event_callback_by_name(const char *name);

// Returns the name of the given registered event_type.
//
// Returns NULL if the event doesn't exist.
const char *get_custom_event_name(uint32_t event_type);

#endif // CUSTOM_EVENTS_H
