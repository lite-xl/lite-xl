#ifndef DEFINES_H
#define DEFINES_H

#ifdef __GNUC__
#define UNUSED __attribute__((__unused__))
#else
#define UNUSED
#endif

#ifdef _WIN32
  #define realpath(x, y) _wfullpath(y, x, MAX_PATH)
#endif

#endif