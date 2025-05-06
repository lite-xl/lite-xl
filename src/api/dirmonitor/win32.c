#include <SDL3/SDL.h>
#include <windows.h>


struct dirmonitor_internal {
  HANDLE handle;
};


int get_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int buffer_size) {
  HANDLE handle = monitor->handle;
  if (handle && handle != INVALID_HANDLE_VALUE) {
    DWORD bytes_transferred;
    if (ReadDirectoryChangesW(handle, buffer, buffer_size, TRUE,  FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME, &bytes_transferred, NULL, NULL) == 0)
      return 0;
    return bytes_transferred;
  }
  return 0;
}


struct dirmonitor* init_dirmonitor() {
  return SDL_calloc(1, sizeof(struct dirmonitor_internal));
}


static void close_monitor_handle(struct dirmonitor_internal* monitor) {
  if (monitor->handle && monitor->handle != INVALID_HANDLE_VALUE) {
    HANDLE handle = monitor->handle;
    monitor->handle = NULL;
    CancelIoEx(handle, NULL);
    CloseHandle(handle);
  }
}


void deinit_dirmonitor(struct dirmonitor_internal* monitor) {
  close_monitor_handle(monitor);
}


int translate_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int buffer_size, int (*change_callback)(int, const char*, void*), void* data) {
  for (FILE_NOTIFY_INFORMATION* info = (FILE_NOTIFY_INFORMATION*)buffer; (char*)info < buffer + buffer_size; info = (FILE_NOTIFY_INFORMATION*)(((char*)info) + info->NextEntryOffset)) {
    char transform_buffer[MAX_PATH*4];
    int count = WideCharToMultiByte(CP_UTF8, 0, (WCHAR*)info->FileName, info->FileNameLength / 2, transform_buffer, MAX_PATH*4 - 1, NULL, NULL);
    change_callback(count, transform_buffer, data);
    if (!info->NextEntryOffset)
      break;
  }
  return 0;
}


int add_dirmonitor(struct dirmonitor_internal* monitor, const char* path) {
  close_monitor_handle(monitor);
  monitor->handle = CreateFileA(path, FILE_LIST_DIRECTORY, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
  return !monitor->handle || monitor->handle == INVALID_HANDLE_VALUE ? -1 : 1;
}


void remove_dirmonitor(struct dirmonitor_internal* monitor, int fd) {
  close_monitor_handle(monitor);
}


int get_mode_dirmonitor() { return 1; }
