#ifndef UTIL_H
#define UTIL_H

#ifdef _WIN32
#include <windows.h>

typedef DWORD util_error_t;
#else
typedef int util_error_t;
#endif

int util_wstoutf(char **utfstr, wchar_t *wstr);
int util_utftows(wchar_t **wstr, const char *utfstr);

char *util_strerror(util_error_t e);
void util_errorfree(char *msg);

#endif
