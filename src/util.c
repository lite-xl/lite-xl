#include "util.h"

static char *error_unknown = "Unknown error";

int util_wstoutf(char **utfstr, wchar_t *wstr) {
#ifndef _WIN32
#error Do not use this function on non-Windows platforms
#endif
  int len;
  char *output = NULL;
  len = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
  if (len == 0) return -EINVAL;

  output = malloc(len * sizeof(char));
  if (output == NULL) return -ENOMEM;

  len = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, output, len, NULL, NULL);
  if (len == 0) return -EINVAL;

  *utfstr = output;
  return len - 1;
}


int util_utftows(wchar_t **wstr, const char *utfstr) {
#ifndef _WIN32
#error Do not use this function on non-Windows platforms
#endif
  int len;
  wchar_t *output = NULL;
  len = MultiByteToWideChar(CP_UTF8, 0, utfstr, -1, NULL, 0);
  if (len == 0) return -EINVAL;

  output = malloc(len * sizeof(wchar_t));
  if (output == NULL) return -ENOMEM;

  len = MultiByteToWideChar(CP_UTF8, 0, utfstr, -1, output, len);
  if (len == 0) return -EINVAL;

  *wstr = output;
  return len - 1;
}

char *util_strerror(util_error_t e) {
#ifdef _WIN32
  LPSTR error = NULL;
  FormatMessageA(
    FORMAT_MESSAGE_FROM_SYSTEM
    | FORMAT_MESSAGE_ALLOCATE_BUFFER
    | FORMAT_MESSAGE_IGNORE_INSERTS,
    NULL,
    e,
    MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
    (LPSTR) &error,
    0,
    NULL
  );

  return error == NULL ? error_unknown : error;
#else
  return strerror(e);
#endif
}


void util_errorfree(char *msg) {
#ifdef _WIN32
  if (msg != error_unknown)
    LocalFree(msg);
#endif
}
