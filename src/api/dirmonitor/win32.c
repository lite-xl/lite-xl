#include <stdbool.h>
#include <windows.h>

struct dirmonitor {
  HANDLE handle;
  char buffer[8192];
  OVERLAPPED overlapped;
  bool running;
};

struct dirmonitor* init_dirmonitor_win32() {
  struct dirmonitor* monitor = calloc(sizeof(struct dirmonitor), 1);

  return monitor;
}

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

void deinit_dirmonitor_win32(struct dirmonitor* monitor) {
  close_monitor_handle(monitor);
  free(monitor);
}

int check_dirmonitor_win32(struct dirmonitor* monitor, int (*change_callback)(int, const char*, void*), void* data) {
  if (!monitor->running) {
    if (ReadDirectoryChangesW(monitor->handle, monitor->buffer, sizeof(monitor->buffer), TRUE,  FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME, NULL, &monitor->overlapped, NULL) == 0) {
      return GetLastError();
    }
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
}

int add_dirmonitor_win32(struct dirmonitor* monitor, const char* path) {
  close_monitor_handle(monitor);
  monitor->handle = CreateFileA(path, FILE_LIST_DIRECTORY, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, NULL);
  if (monitor->handle && monitor->handle != INVALID_HANDLE_VALUE) {
    return 1;
  }
  monitor->handle = NULL;
  return -1;
}

void remove_dirmonitor_win32(struct dirmonitor* monitor, int fd) {
  close_monitor_handle(monitor);
}