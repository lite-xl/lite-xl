#include <stdio.h>
#include <string.h>

#include <SDL.h>

#define DMON_IMPL
#include "dmon.h"

#include "dirmonitor.h"

static void send_sdl_event(dmon_watch_id watch_id, dmon_action action, const char *filepath) {
  SDL_Event ev;
  const int size = strlen(filepath) + 1;
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
  fprintf(stderr, "DEBUG: send watch_id: %d action; %d\n", watch_id.id, action); fflush(stderr);
  ev.user.code = ((watch_id.id & 0xffff) << 16) | (action & 0xffff);
  ev.user.data1 = new_filepath;
  SDL_PushEvent(&ev);
}

void dirmonitor_init() {
  dmon_init();
  /* FIXME: not needed ? */
  /* sdl_dmon_event_type = SDL_RegisterEvents(1); */
}

void dirmonitor_deinit() {
  dmon_deinit();
}

void dirmonitor_push_event(dmon_watch_id watch_id, dmon_action action, const char *filepath,
  const char *oldfilepath)
{
  switch (action) {
  case DMON_ACTION_MOVE:
    send_sdl_event(watch_id, DMON_ACTION_DELETE, oldfilepath);
    send_sdl_event(watch_id, DMON_ACTION_CREATE, filepath);
    break;
  case DMON_ACTION_MODIFY:
    break;
  default:
    send_sdl_event(watch_id, action, filepath);
  }
}

