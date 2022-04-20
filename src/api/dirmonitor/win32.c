#include <windows.h>


struct dirmonitor_internal {
  HANDLE handle;
};


int get_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int buffer_size) {
  DWORD bytes_transferred;
  if (ReadDirectoryChangesW(monitor->handle, buffer, buffer_size, TRUE,  FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME, &bytes_transferred, NULL, NULL) == 0)
    return -1;
  return bytes_transferred;
}


struct dirmonitor* init_dirmonitor() {
  return calloc(sizeof(struct dirmonitor_internal), 1);
}


static void close_monitor_handle(struct dirmonitor_internal* monitor) {
  CloseHandle(monitor->handle);
}


void deinit_dirmonitor(struct dirmonitor_internal* monitor) {
  close_monitor_handle(monitor);
}


int translate_changes_dirmonitor(struct dirmonitor_internal* monitor, char* buffer, int buffer_size, int (*change_callback)(int, const char*, void*), void* data) {
  for (FILE_NOTIFY_INFORMATION* info = (FILE_NOTIFY_INFORMATION*)buffer; (char*)info < buffer + buffer_size; info = (FILE_NOTIFY_INFORMATION*)(((char*)info) + info->NextEntryOffset)) {
    char transform_buffer[PATH_MAX*4];
    int count = WideCharToMultiByte(CP_UTF8, 0, (WCHAR*)info->FileName, info->FileNameLength, transform_buffer, PATH_MAX*4 - 1, NULL, NULL);
    change_callback(info->FileNameLength / sizeof(WCHAR), buffer, data);
    if (!info->NextEntryOffset)
      break;
  }
  return 0;
}


int add_dirmonitor(struct dirmonitor_internal* monitor, const char* path) {
  close_monitor_handle(monitor);
  monitor->handle = CreateFileA(path, FILE_LIST_DIRECTORY, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, NULL);
  return !monitor->handle || monitor->handle == INVALID_HANDLE_VALUE ? -1 : 1;
}


void remove_dirmonitor(struct dirmonitor_internal* monitor, int fd) {
  close_monitor_handle(monitor);
}
