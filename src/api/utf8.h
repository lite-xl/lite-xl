#ifndef LITE_API_UTF8_H
#define LITE_API_UTF8_H

#include <stddef.h>
#include "lua.h"

int luaopen_utf8extra(lua_State *L);

/* Internal entry point to the Lua-pattern matcher (the engine behind
   string.ufind / string.umatch), for callers that need to run it many times
   without going through the Lua stack -- i.e. the syntax tokenizer's C core.
   The pattern is matched exactly as string.ufind would match it. */

#ifndef LITE_PATTERN_MAXCAPTURES
#define LITE_PATTERN_MAXCAPTURES 32
#endif

typedef struct {
  int n;                                  /* number of captures */
  long start[LITE_PATTERN_MAXCAPTURES];    /* byte offset of each capture */
  long len[LITE_PATTERN_MAXCAPTURES];      /* byte length, or -1 for a
                                             position capture "()" */
} lite_pattern_captures;

/* Search `subject[0 .. subject_len)` for `pattern[0 .. pattern_len)` beginning
   at byte offset `from`. `pattern` must have had a leading '^' already removed;
   pass `anchored` non-zero to try only at `from` (what '^' or an at-start match
   means). `pattern` and `subject` must be NUL-terminated (Lua strings are).

   On a match: returns 1, writes the match span as byte offsets to *match_start
   / *match_end, and fills `caps` (may be NULL).
   On no match: returns 0.
   A malformed pattern raises a Lua error through `L`, exactly as string.ufind
   would, so call it only from a protected context. */
int lite_lua_pattern_match(lua_State *L,
    const char *subject, size_t subject_len,
    const char *pattern, size_t pattern_len,
    size_t from, int anchored,
    long *match_start, long *match_end,
    lite_pattern_captures *caps);

#endif
