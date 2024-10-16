/**
 * Wrappers to provide Unicode (UTF-8) support on Windows.
 *
 * Copyright (c) 2018 Peter Wu <peter@lekensteyn.nl>
 * SPDX-License-Identifier: (GPL-2.0-or-later OR MIT)
 */

#ifdef _WIN32
#include <windows.h>    /* for MultiByteToWideChar */
#include <wchar.h>      /* for _wrename */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>

// A environment variable has the maximum length of 32767 characters
// including the terminator.
#define MAX_ENV_SIZE    32767
// Set a high limit in case long paths are enabled.
#define MAX_PATH_SIZE   4096
#define MAX_MODE_SIZE   128
// cmd.exe argument length is reportedly limited to 8192.
#define MAX_CMD_SIZE    8192

static char env_value[MAX_ENV_SIZE];

FILE *fopen_utf8(const char *pathname, const char *mode) {
    wchar_t pathname_w[MAX_PATH_SIZE];
    wchar_t mode_w[MAX_MODE_SIZE];
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, pathname, -1, pathname_w, MAX_PATH_SIZE) ||
        !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, mode, -1, mode_w, MAX_MODE_SIZE)) {
        errno = EINVAL;
        return NULL;
    }
    return _wfopen(pathname_w, mode_w);
}

FILE *freopen_utf8(const char *pathname, const char *mode, FILE *stream) {
    wchar_t pathname_w[MAX_PATH_SIZE];
    wchar_t mode_w[MAX_MODE_SIZE];
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, pathname, -1, pathname_w, MAX_PATH_SIZE) ||
        !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, mode, -1, mode_w, MAX_MODE_SIZE)) {
        // Close stream as documented for the error case.
        fclose(stream);
        errno = EINVAL;
        return NULL;
    }
    return _wfreopen(pathname_w, mode_w, stream);
}

int remove_utf8(const char *pathname) {
    wchar_t pathname_w[MAX_PATH_SIZE];
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, pathname, -1, pathname_w, MAX_PATH_SIZE)) {
        errno = EINVAL;
        return -1;
    }
    return _wremove(pathname_w);
}

int rename_utf8(const char *oldpath, const char *newpath) {
    wchar_t oldpath_w[MAX_PATH_SIZE];
    wchar_t newpath_w[MAX_PATH_SIZE];
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, oldpath, -1, oldpath_w, MAX_PATH_SIZE) ||
        !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, newpath, -1, newpath_w, MAX_PATH_SIZE)) {
        errno = EINVAL;
        return -1;
    }
    return _wrename(oldpath_w, newpath_w);
}

FILE *popen_utf8(const char *command, const char *mode) {
    wchar_t command_w[MAX_CMD_SIZE];
    wchar_t mode_w[MAX_MODE_SIZE];
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, command, -1, command_w, MAX_CMD_SIZE) ||
        !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, mode, -1, mode_w, MAX_MODE_SIZE)) {
        errno = EINVAL;
        return NULL;
    }
    return _wpopen(command_w, mode_w);
}

int system_utf8(const char *command) {
    wchar_t command_w[MAX_CMD_SIZE];
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, command, -1, command_w, MAX_CMD_SIZE)) {
        errno = EINVAL;
        return -1;
    }
    return _wsystem(command_w);
}

DWORD GetModuleFileNameA_utf8(HMODULE hModule, LPSTR lpFilename, DWORD nSize) {
    wchar_t filename_w[MAX_PATH + 1];
    if (!GetModuleFileNameW(hModule, filename_w, MAX_PATH + 1)) {
        return 0;
    }
    return WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, filename_w, -1, lpFilename, nSize, NULL, NULL);
}

HMODULE LoadLibraryExA_utf8(LPCSTR lpLibFileName, HANDLE hFile, DWORD dwFlags) {
    wchar_t pathname_w[MAX_PATH_SIZE];
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, lpLibFileName, -1, pathname_w, MAX_PATH_SIZE)) {
        SetLastError(ERROR_INVALID_NAME);
        return NULL;
    }
    return LoadLibraryExW(pathname_w, hFile, dwFlags);
}

char* getenv_utf8(const char *varname) {
  /** This implementation is not thread safe.
   * The string is only valid until the next call to getenv.
   * This behavior is allowed per POSIX.1-2017 where it was said that:
   * > The returned string pointer might be invalidated or the string content might be overwritten by a subsequent call to getenv(), setenv(), unsetenv(), or (if supported) putenv() but they shall not be affected by a call to any other function in this volume of POSIX.1-2017.
   * > The returned string pointer might also be invalidated if the calling thread is terminated.
   * > The getenv() function need not be thread-safe.
   */
  wchar_t *value_w;
  wchar_t varname_w[MAX_ENV_SIZE];

  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, varname, -1, varname_w, MAX_ENV_SIZE))
    return NULL;
  value_w = _wgetenv((const wchar_t *) varname_w);
  if (!value_w)
    return NULL;

  if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value_w, -1, env_value, MAX_ENV_SIZE, NULL, NULL))
    return NULL;

  return env_value;
}
#endif
