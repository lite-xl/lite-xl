#ifndef MBSEC_H
#define MBSEC_H

#ifdef _WIN32

#include <stdlib.h>
#include <windows.h>

#define UTFCONV_ERROR_INVALID_CONVERSION "Input contains invalid byte sequences."

LPWSTR utfconv_utf8towc(const char *str) {
  LPWSTR output;
  int len;

  // len includes \0
  len = MultiByteToWideChar(CP_UTF8, 0, str, -1, NULL, 0);
  if (len == 0)
    return NULL;

  output = (LPWSTR) malloc(sizeof(WCHAR) * len);
  if (output == NULL)
    return NULL;

  len = MultiByteToWideChar(CP_UTF8, 0, str, -1, output, len);
  if (len == 0) {
    free(output);
    return NULL;
  }

  return output;
}

char *utfconv_wctoutf8(LPCWSTR str) {
  char *output;
  int len;

  // len includes \0
  len = WideCharToMultiByte(CP_UTF8, 0, str, -1, NULL, 0, NULL, NULL);
  if (len == 0)
    return NULL;

  output = (char *) malloc(sizeof(char) * len);
  if (output == NULL)
    return NULL;

  len = WideCharToMultiByte(CP_UTF8, 0, str, -1, output, len, NULL, NULL);
  if (len == 0) {
    free(output);
    return NULL;
  }

  return output;
}

#endif

#endif
