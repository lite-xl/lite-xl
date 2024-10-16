/**
 * Wrappers to provide Unicode (UTF-8) support on Windows.
 *
 * Copyright (c) 2018 Peter Wu <peter@lekensteyn.nl>
 * SPDX-License-Identifier: (GPL-2.0-or-later OR MIT)
 */

#ifdef _WIN32

#if defined(loadlib_c) || defined(lauxlib_c) || defined(liolib_c) || defined(luac_c)
#include <stdio.h>  /* for loadlib_c */
FILE *fopen_utf8(const char *pathname, const char *mode);
#define fopen               fopen_utf8
#endif

#ifdef lauxlib_c
#include <stdio.h>
FILE *freopen_utf8(const char *pathname, const char *mode, FILE *stream);
#define freopen             freopen_utf8
#endif

#ifdef liolib_c
FILE *popen_utf8(const char *command, const char *mode);
#define _popen              popen_utf8
#endif

#ifdef loslib_c
#include <stdio.h>
int remove_utf8(const char *pathname);
int rename_utf8(const char *oldpath, const char *newpath);
int system_utf8(const char *command);
char *getenv_utf8(const char *varname);
#define remove              remove_utf8
#define rename              rename_utf8
#define system              system_utf8
#define getenv              getenv_utf8
#endif

#ifdef loadlib_c
#include <windows.h>
DWORD GetModuleFileNameA_utf8(HMODULE hModule, LPSTR lpFilename, DWORD nSize);
HMODULE LoadLibraryExA_utf8(LPCSTR lpLibFileName, HANDLE hFile, DWORD dwFlags);
#define GetModuleFileNameA  GetModuleFileNameA_utf8
#define LoadLibraryExA      LoadLibraryExA_utf8
#endif
#endif
