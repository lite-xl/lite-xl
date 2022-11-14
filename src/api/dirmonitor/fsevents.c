#include <SDL.h>
#include <CoreServices/CoreServices.h>

struct dirmonitor_internal {
  SDL_mutex* lock;
  char** changes;
  size_t count;
  FSEventStreamRef stream;
};

CFRunLoopRef main_run_loop;


struct dirmonitor_internal* init_dirmonitor() {
  static bool mainloop_registered = false;
  if (!mainloop_registered) {
    main_run_loop = CFRunLoopGetCurrent();
    mainloop_registered = true;
  }

  struct dirmonitor_internal* monitor = malloc(sizeof(struct dirmonitor_internal));
  monitor->stream = NULL;
  monitor->changes = NULL;
  monitor->count = 0;
  monitor->lock = NULL;

  return monitor;
}


static void stop_monitor_stream(struct dirmonitor_internal* monitor) {
  if (monitor->stream) {
    FSEventStreamStop(monitor->stream);
    FSEventStreamUnscheduleFromRunLoop(
      monitor->stream, main_run_loop, kCFRunLoopDefaultMode
    );
    FSEventStreamInvalidate(monitor->stream);
    FSEventStreamRelease(monitor->stream);
    monitor->stream = NULL;

    SDL_LockMutex(monitor->lock);
    if (monitor->count > 0) {
      for (size_t i = 0; i<monitor->count; i++) {
        free(monitor->changes[i]);
      }
      free(monitor->changes);
      monitor->changes = NULL;
      monitor->count = 0;
    }
    SDL_UnlockMutex(monitor->lock);
    SDL_DestroyMutex(monitor->lock);
  }
}


void deinit_dirmonitor(struct dirmonitor_internal* monitor) {
  stop_monitor_stream(monitor);
}


static void stream_callback(
  ConstFSEventStreamRef streamRef,
  void* monitor_ptr,
  size_t numEvents,
  void* eventPaths,
  const FSEventStreamEventFlags eventFlags[],
  const FSEventStreamEventId eventIds[]
)
{
  if (numEvents <= 0) {
    return;
  }

  struct dirmonitor_internal* monitor = monitor_ptr;
  char** path_list = eventPaths;

  SDL_LockMutex(monitor->lock);
  size_t total = 0;
  if (monitor->count == 0) {
    total = numEvents;
    monitor->changes = calloc(numEvents, sizeof(char*));
  } else {
    total = monitor->count + numEvents;
    monitor->changes = realloc(
      monitor->changes,
      sizeof(char*) * total
    );
  }
  for (size_t idx = monitor->count; idx < total; idx++) {
    size_t pidx = idx - monitor->count;
    monitor->changes[idx] = malloc(strlen(path_list[pidx])+1);
    strcpy(monitor->changes[idx], path_list[pidx]);
  }
  monitor->count = total;
  SDL_UnlockMutex(monitor->lock);
}


int get_changes_dirmonitor(
  struct dirmonitor_internal* monitor,
  char* buffer,
  int buffer_size
) {
  FSEventStreamFlushSync(monitor->stream);

  size_t results = 0;
  SDL_LockMutex(monitor->lock);
  results = monitor->count;
  SDL_UnlockMutex(monitor->lock);

  return results;
}


int translate_changes_dirmonitor(
  struct dirmonitor_internal* monitor,
  char* buffer,
  int buffer_size,
  int (*change_callback)(int, const char*, void*),
  void* L
) {
  SDL_LockMutex(monitor->lock);
  if (monitor->count > 0) {
    for (size_t i = 0; i<monitor->count; i++) {
      change_callback(strlen(monitor->changes[i]), monitor->changes[i], L);
      free(monitor->changes[i]);
    }
    free(monitor->changes);
    monitor->changes = NULL;
    monitor->count = 0;
  }
  SDL_UnlockMutex(monitor->lock);
  return 0;
}


int add_dirmonitor(struct dirmonitor_internal* monitor, const char* path) {
  stop_monitor_stream(monitor);

  monitor->lock = SDL_CreateMutex();

  FSEventStreamContext context = {
    .info = monitor,
    .retain = NULL,
    .release = NULL,
    .copyDescription = NULL,
    .version = 0
  };

  CFStringRef paths[] = {
    CFStringCreateWithCString(NULL, path, kCFStringEncodingUTF8)
  };

  monitor->stream = FSEventStreamCreate(
    NULL,
    stream_callback,
    &context,
    CFArrayCreate(NULL, (const void **)&paths, 1, NULL),
    kFSEventStreamEventIdSinceNow,
    10000,
    kFSEventStreamCreateFlagNone
      | kFSEventStreamCreateFlagWatchRoot
      | kFSEventStreamCreateFlagFileEvents
  );

  FSEventStreamScheduleWithRunLoop(
    monitor->stream, main_run_loop, kCFRunLoopDefaultMode
  );

  if (!FSEventStreamStart(monitor->stream)) {
    stop_monitor_stream(monitor);
    return -1;
  }

  return 1;
}


void remove_dirmonitor(struct dirmonitor_internal* monitor, int fd) {
  stop_monitor_stream(monitor);
}


int get_mode_dirmonitor() { return 1; }
