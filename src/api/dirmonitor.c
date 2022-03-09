#include "api.h"
#include <stdlib.h>
#ifdef _WIN32
  #include <windows.h>
#elif __linux__
  #include <sys/inotify.h>
  #include <limits.h>
#else
  #include <sys/event.h>
#endif
#include <unistd.h>
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <string.h>
#include <stdbool.h>

/*
This is *slightly* a clusterfuck. Normally, we'd
have windows wait on a list of handles like inotify,
however, MAXIMUM_WAIT_OBJECTS is 64. Yes, seriously.

So, for windows, we are recursive.
*/
struct dirmonitor {
  int fd;
  #if _WIN32
    HANDLE handle;
    char buffer[8192];
    OVERLAPPED overlapped;
    bool running;
  #endif
};

struct dirmonitor* init_dirmonitor() {
  struct dirmonitor* monitor = calloc(sizeof(struct dirmonitor), 1);
  #ifndef _WIN32
    #if __linux__
      monitor->fd = inotify_init1(IN_NONBLOCK);
    #else
      monitor->fd = kqueue();
    #endif
  #endif
  return monitor;
}

#if _WIN32
static void close_monitor_handle(struct dirmonitor* monitor) {
  if (monitor->handle) {
      if (monitor->running) {
        BOOL result = CancelIoEx(monitor->handle, &monitor->overlapped);
        DWORD error = GetLastError();
        if (result == TRUE || error != ERROR_NOT_FOUND) {
          DWORD bytes_transferred;
          GetOverlappedResult( monitor->handle, &monitor->overlapped, &bytes_transferred, TRUE );
        }
        monitor->running = false;
      }
      CloseHandle(monitor->handle);
    }
  monitor->handle = NULL;
}
#endif

void deinit_dirmonitor(struct dirmonitor* monitor) {
  #if _WIN32
    close_monitor_handle(monitor);
  #else
    close(monitor->fd);
  #endif
  free(monitor);
}

int check_dirmonitor(struct dirmonitor* monitor, int (*change_callback)(int, const char*, void*), void* data) {
  #if _WIN32
    if (!monitor->running) {
      if (ReadDirectoryChangesW(monitor->handle, monitor->buffer, sizeof(monitor->buffer), TRUE,  FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME, NULL, &monitor->overlapped, NULL) == 0)
        return GetLastError();
      monitor->running = true;
    }
    DWORD bytes_transferred;
    if (!GetOverlappedResult(monitor->handle, &monitor->overlapped, &bytes_transferred, FALSE)) {
      int error = GetLastError();
      return error == ERROR_IO_PENDING || error == ERROR_IO_INCOMPLETE ? 0 : error;
    }
    monitor->running = false;
    for (FILE_NOTIFY_INFORMATION* info = (FILE_NOTIFY_INFORMATION*)monitor->buffer; (char*)info < monitor->buffer + sizeof(monitor->buffer); info = (FILE_NOTIFY_INFORMATION*)((char*)info) + info->NextEntryOffset) {
      change_callback(info->FileNameLength, (char*)info->FileName, data);
      if (!info->NextEntryOffset)
        break;
    }
    monitor->running = false;
    return 0;
  #elif __linux__
    char buf[PATH_MAX + sizeof(struct inotify_event)];
    ssize_t offset = 0;
    while (1) {
      ssize_t len = read(monitor->fd, &buf[offset], sizeof(buf) - offset);
      if (len == -1 && errno != EAGAIN)
        return errno;
      if (len <= 0)
        return 0;
      while (len > sizeof(struct inotify_event) && len >= ((struct inotify_event*)buf)->len + sizeof(struct inotify_event)) {
        change_callback(((const struct inotify_event *)buf)->wd, NULL, data);
        len -= sizeof(struct inotify_event) + ((struct inotify_event*)buf)->len;
        memmove(buf, &buf[sizeof(struct inotify_event) + ((struct inotify_event*)buf)->len], len);
        offset = len;
      }
    }
  #else
    struct kevent event;
    while (1) {
      struct timespec tm = {0};
      int nev = kevent(monitor->fd, NULL, 0, &event, 1, &tm);
      if (nev == -1)
        return errno;
      if (nev <= 0)
        return 0;
      change_callback(event.ident, NULL, data);
    }
  #endif
}

int add_dirmonitor(struct dirmonitor* monitor, const char* path) {
  #if _WIN32
    close_monitor_handle(monitor);
    monitor->handle = CreateFileA(path, FILE_LIST_DIRECTORY, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, NULL);
    if (monitor->handle && monitor->handle != INVALID_HANDLE_VALUE)
      return 1;
    monitor->handle = NULL;
    return -1;
  #elif __linux__
    return inotify_add_watch(monitor->fd, path, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO);
  #else
    int fd = open(path, O_RDONLY);
    struct kevent change;
    EV_SET(&change, fd, EVFILT_VNODE, EV_ADD | EV_CLEAR, NOTE_DELETE | NOTE_EXTEND | NOTE_WRITE | NOTE_ATTRIB | NOTE_LINK | NOTE_RENAME, 0, (void*)path);
    kevent(monitor->fd, &change, 1, NULL, 0, NULL);
    return fd;
  #endif
}

void remove_dirmonitor(struct dirmonitor* monitor, int fd) {
  #if _WIN32
    close_monitor_handle(monitor);
  #elif __linux__
    inotify_rm_watch(monitor->fd, fd);
  #else
    close(fd);
  #endif
}

static int f_check_dir_callback(int watch_id, const char* path, void* L) {
  lua_pushvalue(L, -1);
  #if _WIN32
    char buffer[PATH_MAX*4];
    int count = WideCharToMultiByte(CP_UTF8, 0, (WCHAR*)path, watch_id, buffer, PATH_MAX*4 - 1, NULL, NULL);
    lua_pushlstring(L, buffer, count);
  #else
    lua_pushnumber(L, watch_id);
  #endif
  lua_call(L, 1, 1);
  int result = lua_toboolean(L, -1);
  lua_pop(L, 1);
  return !result;
}

static int f_dirmonitor_new(lua_State* L) {
  struct dirmonitor** monitor = lua_newuserdata(L, sizeof(struct dirmonitor**));
  *monitor = init_dirmonitor();
  luaL_setmetatable(L, API_TYPE_DIRMONITOR);
  return 1;
}

static int f_dirmonitor_gc(lua_State* L) {
  deinit_dirmonitor(*((struct dirmonitor**)luaL_checkudata(L, 1, API_TYPE_DIRMONITOR)));
  return 0;
}

static int f_dirmonitor_watch(lua_State *L) {
  lua_pushnumber(L, add_dirmonitor(*(struct dirmonitor**)luaL_checkudata(L, 1, API_TYPE_DIRMONITOR), luaL_checkstring(L, 2)));
  return 1;
}

static int f_dirmonitor_unwatch(lua_State *L) {
  remove_dirmonitor(*(struct dirmonitor**)luaL_checkudata(L, 1, API_TYPE_DIRMONITOR), luaL_checknumber(L, 2));
  return 0;
}

static int f_dirmonitor_check(lua_State* L) {
  lua_pushnumber(L, check_dirmonitor(*(struct dirmonitor**)luaL_checkudata(L, 1, API_TYPE_DIRMONITOR), f_check_dir_callback, L));
  return 1;
}
static const luaL_Reg dirmonitor_lib[] = {
  { "new",      f_dirmonitor_new         },
  { "__gc",     f_dirmonitor_gc          },
  { "watch",    f_dirmonitor_watch       },
  { "unwatch",  f_dirmonitor_unwatch     },
  { "check",    f_dirmonitor_check       },
  {NULL, NULL}
};

int luaopen_dirmonitor(lua_State* L) {
  luaL_newmetatable(L, API_TYPE_DIRMONITOR);
  luaL_setfuncs(L, dirmonitor_lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  return 1;
}
