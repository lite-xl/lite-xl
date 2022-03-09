// fuck you, Windows.

#ifndef WIN32_UTIL_H
#define WIN32_UTIL_H

#ifdef _WIN32

#include <windows.h>

#include "lua.h"
#include "lauxlib.h"


static wchar_t *utftowcs(const char *str) {
    wchar_t *wstr = NULL;
    DWORD r = 0;

    r = MultiByteToWideChar(
            CP_UTF8,
            0,
            str,
            -1,
            NULL,
            0
            );
    if (r == 0) return NULL;

    wstr = (wchar_t *) malloc(r * sizeof(wchar_t));
    if (!wstr) return NULL;

    r = MultiByteToWideChar(
            CP_UTF8,
            0,
            str,
            -1,
            wstr,
            r
            );
    if (r == 0) return NULL;

    return wstr;
}


static char *wcstoutf(const wchar_t *wstr) {
    char *str = NULL;
    DWORD r = 0;

    r = WideCharToMultiByte(
            CP_UTF8,
            0,
            wstr,
            -1,
            NULL,
            0,
            NULL,
            NULL
    );
    if (r == 0) return NULL;

    str = (char *) malloc(r * sizeof(char));
    if (!str) return NULL;

    r = WideCharToMultiByte(
            CP_UTF8,
            0,
            wstr,
            -1,
            str,
            r * sizeof(char),
            NULL,
            NULL
    );
    if (r == 0) return NULL;

    return str;
}


static int l_win32error(lua_State *L, DWORD e) {
  char *err = NULL;
  FormatMessageA(
          FORMAT_MESSAGE_ALLOCATE_BUFFER
          | FORMAT_MESSAGE_FROM_SYSTEM
          | FORMAT_MESSAGE_IGNORE_INSERTS,
          NULL,
          e,
          MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
          (LPSTR) &err,
          0,
          NULL
          );
  lua_pushnil(L);
  lua_pushstring(L, err ? err : "Unknown error");
  if (err) LocalFree(err);
  return 2;
}


static time_t filetime_to_unix(FILETIME ft) {
  ULARGE_INTEGER ull;
  ull.LowPart = ft.dwLowDateTime;
  ull.HighPart = ft.dwHighDateTime;
  return ull.QuadPart / 10000000ULL - 11644473600ULL;
}

#endif

#endif //LITE_XL_WIN32_UTIL_H
