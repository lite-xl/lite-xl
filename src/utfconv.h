#ifndef MBSEC_H
#define MBSEC_H

#ifdef __GNUC__
#define UNUSED __attribute__((__unused__))
#else
#define UNUSED
#endif

#ifdef _WIN32

#include <stdlib.h>
#include <windows.h>

#include "arena_allocator.h"

#define UTFCONV_ERROR_INVALID_CONVERSION "Input contains invalid byte sequences."

#define utfconv_fromutf8(A, str) utfconv_fromlutf8(A, str, -1)

static UNUSED LPWSTR utfconv_fromlutf8(lxl_arena *A, const char *str, int len) {
  int output_len = MultiByteToWideChar(CP_UTF8, 0, str, len, NULL, 0);
  if (!output_len) return NULL;
  LPWSTR output = lxl_arena_malloc(A, sizeof(WCHAR) * output_len);
  if (!output) return NULL;
  output_len = MultiByteToWideChar(CP_UTF8, 0, str, len, output, output_len);
  if (!output_len) return (lxl_arena_free(A, output), NULL);
  return output;
}

#define utfconv_fromwstr(A, str) utfconv_fromlwstr(A, str, -1)

static UNUSED const char *utfconv_fromlwstr(lxl_arena *A, LPWSTR str, int len) {
  int output_len = WideCharToMultiByte(CP_UTF8, 0, str, len, NULL, 0, NULL, NULL);
  if (!output_len) return NULL;
  char *output = lxl_arena_malloc(A, sizeof(char) * output_len);
  if (!output) return NULL;
  output_len = WideCharToMultiByte(CP_UTF8, 0, str, len, output, output_len, NULL, NULL);
  if (!output_len) return (lxl_arena_free(A, output), NULL);
  return (const char *) output;
}

static UNUSED LPWSTR utfconv_utf8towc(const char *str) {
  LPWSTR output;
  int len;

  // len includes \0
  len = MultiByteToWideChar(CP_UTF8, 0, str, -1, NULL, 0);
  if (len == 0)
    return NULL;

  output = (LPWSTR) SDL_malloc(sizeof(WCHAR) * len);
  if (output == NULL)
    return NULL;

  len = MultiByteToWideChar(CP_UTF8, 0, str, -1, output, len);
  if (len == 0) {
    SDL_free(output);
    return NULL;
  }

  return output;
}

static UNUSED char *utfconv_wctoutf8(LPCWSTR str) {
  char *output;
  int len;

  // len includes \0
  len = WideCharToMultiByte(CP_UTF8, 0, str, -1, NULL, 0, NULL, NULL);
  if (len == 0)
    return NULL;

  output = (char *) SDL_malloc(sizeof(char) * len);
  if (output == NULL)
    return NULL;

  len = WideCharToMultiByte(CP_UTF8, 0, str, -1, output, len, NULL, NULL);
  if (len == 0) {
    SDL_free(output);
    return NULL;
  }

  return output;
}

#endif

#endif
