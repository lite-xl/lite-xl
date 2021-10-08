#include <stdio.h>
#include <string.h>

#include <SDL.h>

#define DMON_IMPL
#include "dmon.h"
#include "dmon_extra.h"

#include "dirmonitor.h"

static void send_sdl_event(dmon_watch_id watch_id, dmon_action action, const char *filepath) {
  SDL_Event ev;
  const int size = strlen(filepath) + 1;
  /* The string allocated below should be deallocated as soon as the event is
     treated in the SDL main loop. */
  char *new_filepath = malloc(size);
  if (!new_filepath) return;
  memcpy(new_filepath, filepath, size);
#ifdef _WIN32
  for (int i = 0; i < size; i++) {
    if (new_filepath[i] == '/') {
      new_filepath[i] = '\\';
    }
  }
#endif
  SDL_zero(ev);
  ev.type = SDL_USEREVENT;
  ev.user.code = ((watch_id.id & 0xffff) << 16) | (action & 0xffff);
  ev.user.data1 = new_filepath;
  SDL_PushEvent(&ev);
}

void dirmonitor_init() {
  dmon_init();
  /* In theory we should register our user event but since we
     have just one type of user event this is not really needed. */
  /* sdl_dmon_event_type = SDL_RegisterEvents(1); */
}

void dirmonitor_deinit() {
  dmon_deinit();
}

void dirmonitor_watch_callback(dmon_watch_id watch_id, dmon_action action, const char *rootdir,
  const char *filepath, const char *oldfilepath, void *user)
{
  (void) rootdir;
  (void) user;
  switch (action) {
  case DMON_ACTION_MOVE:
    send_sdl_event(watch_id, DMON_ACTION_DELETE, oldfilepath);
    send_sdl_event(watch_id, DMON_ACTION_CREATE, filepath);
    break;
  default:
    send_sdl_event(watch_id, action, filepath);
  }
}

