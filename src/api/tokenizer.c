/*
 * C core for the syntax tokenizer.
 *
 * tokenizer.lua is the reference implementation and the plugin-facing API.
 * This module provides one function, `tokenizer_c.tokenize(syntax, text,
 * state)`, that reproduces `tokenizer.tokenize` byte-for-byte for the common
 * case -- a line that neither continues nor enters a subsyntax -- by running
 * the whole per-position scan in C instead of crossing into Lua at every
 * position. Lines that touch a subsyntax, or a `resume`, are declined
 * (returns false) and tokenizer.lua handles them itself.
 *
 * The syntax table is snapshotted into `csyntax` once and cached on the table
 * (field `_ctok`) as a __gc userdata; the snapshot is rebuilt if the pattern
 * count changes.
 */

#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#include <lua.h>
#include <lauxlib.h>

#include "utf8.h"

#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

/* -- interned type strings ------------------------------------------------- *
 * Token types are a tiny closed set ("normal", "keyword", "comment", ...).
 * Intern them so push_token's merge check is a pointer compare, matching the
 * Lua `prev_type == type` string compare. Process-lifetime; never freed. */

#define INTERN_CAP 256
static struct { char *s; } g_intern[INTERN_CAP];
static int g_intern_n = 0;
static const char *g_normal;   /* interned "normal", the hot default */

static const char *intern(const char *s, size_t n) {
  for (int i = 0; i < g_intern_n; i++)
    if (strlen(g_intern[i].s) == n && memcmp(g_intern[i].s, s, n) == 0)
      return g_intern[i].s;
  if (g_intern_n == INTERN_CAP) return NULL; /* pathological; caller falls back */
  char *c = malloc(n + 1);
  if (!c) return NULL;
  memcpy(c, s, n); c[n] = 0;
  g_intern[g_intern_n].s = c;
  return g_intern[g_intern_n++].s;
}

/* -- compiled syntax snapshot ------------------------------------------------ */

typedef struct {
  int is_regex;
  int whole_line;
  char *lua;            /* '^'-stripped Lua pattern body (is_regex == 0) */
  size_t lua_len;
  pcre2_code *rx;       /* borrowed from the Lua _compiled userdata (is_regex) */
} delim;

typedef struct {
  int disabled;
  int is_subsyntax;    /* entry has `.syntax` -- C core bails if this matches */
  int is_pair;         /* pattern/regex is a {open, close} table */
  int usable;          /* 0 -> any use of this pattern makes the C core bail */
  delim open;
  int has_close;
  delim close;
  int has_esc;
  int esc_byte;
  int type_is_table;
  int ntypes;
  const char **types;  /* interned; entry may be NULL ("normal") */
  const char *type0;   /* interned; when type is a plain string */
} cpattern;

typedef struct {
  lua_State *L;
  int npat;
  cpattern *pat;
  int symbols_ref;     /* registry ref to syntax.symbols, or LUA_NOREF */
  int has_any_subsyntax;
  int unusable;        /* snapshot hit something we don't model -> always bail */
} csyntax;

static void free_delim(delim *d) { free(d->lua); d->lua = NULL; }

static void free_csyntax(csyntax *cs) {
  if (!cs) return;
  for (int i = 0; i < cs->npat; i++) {
    free_delim(&cs->pat[i].open);
    free_delim(&cs->pat[i].close);
    free(cs->pat[i].types);
  }
  free(cs->pat);
  if (cs->symbols_ref != LUA_NOREF && cs->L)
    luaL_unref(cs->L, LUA_REGISTRYINDEX, cs->symbols_ref);
  cs->pat = NULL; cs->npat = 0;
}

/* Read _compiled[which] (1 = open, 2 = close) into `d`. Returns 0 and sets
   *bail on anything unmodelled. Expects _compiled at the top of the stack. */
static int read_delim(lua_State *L, int compiled_idx, int which, delim *d,
                      int *bail) {
  lua_rawgeti(L, compiled_idx, which);          /* delim table | nil */
  if (lua_type(L, -1) != LUA_TTABLE) { lua_pop(L, 1); *bail = 1; return 0; }
  int di = lua_gettop(L);

  lua_getfield(L, di, "regex");
  d->is_regex = lua_toboolean(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, di, "whole_line");
  d->whole_line = lua_toboolean(L, -1);
  lua_pop(L, 1);

  if (d->is_regex) {
    lua_getfield(L, di, "rx");                   /* {[1]=lightuserdata} */
    if (lua_type(L, -1) == LUA_TTABLE) {
      lua_rawgeti(L, -1, 1);
      d->rx = (pcre2_code *)lua_touserdata(L, -1);
      lua_pop(L, 1);
    }
    lua_pop(L, 1);
    if (!d->rx) *bail = 1;
  } else {
    lua_getfield(L, di, "lua");
    size_t n = 0;
    const char *s = lua_tolstring(L, -1, &n);
    if (s) { d->lua = malloc(n + 1); if (d->lua) { memcpy(d->lua, s, n + 1); d->lua_len = n; } }
    lua_pop(L, 1);
    if (!d->lua) *bail = 1;
  }
  lua_pop(L, 1);                                 /* delim table */
  return 1;
}

/* Build a csyntax from the syntax table at `synidx`. */
static csyntax *build_csyntax(lua_State *L, int synidx) {
  csyntax *cs = calloc(1, sizeof *cs);
  if (!cs) return NULL;
  cs->L = L;
  cs->symbols_ref = LUA_NOREF;

  lua_getfield(L, synidx, "patterns");
  int patterns = lua_gettop(L);
  int np = (int)lua_rawlen(L, patterns);
  cs->npat = np;
  cs->pat = calloc(np > 0 ? np : 1, sizeof(cpattern));
  if (!cs->pat) { lua_pop(L, 1); free(cs); return NULL; }

  for (int n = 1; n <= np; n++) {
    cpattern *cp = &cs->pat[n - 1];
    cp->usable = 1;
    lua_rawgeti(L, patterns, n);                 /* entry */
    int ei = lua_gettop(L);

    lua_getfield(L, ei, "disabled");
    cp->disabled = lua_toboolean(L, -1);
    lua_pop(L, 1);

    lua_getfield(L, ei, "syntax");
    if (!lua_isnil(L, -1)) { cp->is_subsyntax = 1; cs->has_any_subsyntax = 1; }
    lua_pop(L, 1);
    /* A subsyntax pattern is still compiled: the C core matches it to notice
       it should hand the line to Lua, but never processes past it. */

    /* is_pair: pattern or regex value is a table */
    lua_getfield(L, ei, "pattern");
    int has_pat = !lua_isnil(L, -1);
    int pat_is_table = lua_type(L, -1) == LUA_TTABLE;
    lua_pop(L, 1);
    lua_getfield(L, ei, "regex");
    int rgx_is_table = lua_type(L, -1) == LUA_TTABLE;
    lua_pop(L, 1);
    cp->is_pair = pat_is_table || rgx_is_table;
    (void)has_pat;

    if (!cp->disabled) {
      lua_getfield(L, ei, "_compiled");
      if (lua_type(L, -1) != LUA_TTABLE) { cp->usable = 0; lua_pop(L, 1); }
      else {
        int ci = lua_gettop(L);
        int bail = 0;
        read_delim(L, ci, 1, &cp->open, &bail);
        lua_rawgeti(L, ci, 2);
        cp->has_close = lua_type(L, -1) == LUA_TTABLE;
        lua_pop(L, 1);
        if (cp->has_close) read_delim(L, ci, 2, &cp->close, &bail);
        lua_getfield(L, ci, "esc_byte");        /* precompile stores an int ... */
        if (lua_isnumber(L, -1)) { cp->has_esc = 1; cp->esc_byte = (int)lua_tointeger(L, -1); }
        lua_pop(L, 1);
        if (!cp->has_esc) {                     /* ... or the escape string */
          lua_getfield(L, ci, "esc");
          size_t en = 0; const char *es = lua_tolstring(L, -1, &en);
          if (es && en == 1) { cp->has_esc = 1; cp->esc_byte = (unsigned char)es[0]; }
          else if (es && en > 1) cp->usable = 0;   /* multi-byte escape: bail */
          lua_pop(L, 1);
        }
        lua_getfield(L, ci, "err");
        if (!lua_isnil(L, -1)) cp->usable = 0;
        lua_pop(L, 1);
        if (bail) cp->usable = 0;
        lua_pop(L, 1);                            /* _compiled */
      }
    }

    /* type: string, or array of strings */
    lua_getfield(L, ei, "type");
    if (lua_type(L, -1) == LUA_TTABLE) {
      cp->type_is_table = 1;
      int nt = (int)lua_rawlen(L, -1);
      cp->ntypes = nt;
      cp->types = calloc(nt > 0 ? nt : 1, sizeof(const char *));
      for (int t = 1; t <= nt; t++) {
        lua_rawgeti(L, -1, t);
        size_t sl = 0; const char *s = lua_tolstring(L, -1, &sl);
        cp->types[t - 1] = s ? intern(s, sl) : NULL;
        lua_pop(L, 1);
      }
    } else if (lua_type(L, -1) == LUA_TSTRING) {
      size_t sl = 0; const char *s = lua_tolstring(L, -1, &sl);
      cp->type0 = intern(s, sl);
      cp->ntypes = 1;
    } else {
      cp->type0 = intern("normal", 6);
      cp->ntypes = 1;
    }
    lua_pop(L, 1);                                /* type */
    if (!cp->type0 && cp->ntypes == 1 && !cp->type_is_table)
      cs->unusable = 1;   /* interning pool exhausted -- give up on this syntax */

    lua_pop(L, 1);                                /* entry */
  }
  lua_pop(L, 1);                                  /* patterns */

  lua_getfield(L, synidx, "symbols");
  if (lua_type(L, -1) == LUA_TTABLE) {
    lua_pushnil(L);
    int empty = (lua_next(L, -2) == 0);
    if (!empty) lua_pop(L, 2);                     /* key, value from lua_next */
    /* only keep a ref if there's something to look up */
    cs->symbols_ref = empty ? (lua_pop(L, 1), LUA_NOREF)
                            : luaL_ref(L, LUA_REGISTRYINDEX);
  } else {
    lua_pop(L, 1);
  }

  return cs;
}

static int csyntax_gc(lua_State *L) {
  csyntax **p = lua_touserdata(L, 1);
  if (p && *p) { free_csyntax(*p); free(*p); *p = NULL; }
  return 0;
}

/* Return the cached (or freshly built) csyntax for the syntax table at
   `synidx`. NULL means "cannot model this syntax, fall back to Lua". */
static csyntax *get_csyntax(lua_State *L, int synidx) {
  synidx = lua_absindex(L, synidx);
  lua_getfield(L, synidx, "patterns");
  int np = (int)lua_rawlen(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, synidx, "_ctok");
  csyntax **box = lua_touserdata(L, -1);
  lua_pop(L, 1);
  if (box && *box && (*box)->npat == np)
    return *box;

  csyntax *cs = build_csyntax(L, synidx);
  if (!cs) return NULL;

  /* store a fresh box (the old one, if any, GC's itself) */
  csyntax **nb = lua_newuserdata(L, sizeof *nb);
  *nb = cs;
  if (luaL_newmetatable(L, "tokenizer.csyntax")) {
    lua_pushcfunction(L, csyntax_gc);
    lua_setfield(L, -2, "__gc");
  }
  lua_setmetatable(L, -2);
  lua_setfield(L, synidx, "_ctok");
  return cs;
}

/* -- the scan -------------------------------------------------------------- */

typedef struct { const char *type; long end; } tok;

typedef struct {
  const char *text;
  size_t len;
  tok *v;
  int n, cap;
  csyntax *cs;
  lua_State *L;
} builder;

static int is_ws_run(const char *s, long a, long b) {
  for (long i = a; i < b; i++) {
    char c = s[i];
    if (c != ' ' && c != '\t' && c != '\n' && c != '\v' && c != '\f' && c != '\r')
      return 0;
  }
  return 1;
}

/* push_token: append [a,b) as `type`, merging into the previous token when the
   previous type matches or the previous token is all whitespace. */
static void push_token(builder *B, const char *type, long a, long b) {
  if (b <= a) return;
  if (!type) type = g_normal;
  if (B->n > 0) {
    tok *prev = &B->v[B->n - 1];
    long pa = (B->n >= 2) ? B->v[B->n - 2].end : 0;
    if (prev->type == type || is_ws_run(B->text, pa, prev->end)) {
      prev->type = type;
      prev->end = b;
      return;
    }
  }
  if (B->n == B->cap) {
    B->cap = B->cap ? B->cap * 2 : 64;
    B->v = realloc(B->v, B->cap * sizeof(tok));
  }
  B->v[B->n].type = type;
  B->v[B->n].end = b;
  B->n++;
}

/* symbols[text[a..b)] or fallback */
static const char *typed(builder *B, long a, long b, const char *fallback) {
  if (B->cs->symbols_ref == LUA_NOREF) return fallback;
  lua_State *L = B->L;
  lua_rawgeti(L, LUA_REGISTRYINDEX, B->cs->symbols_ref);
  lua_pushlstring(L, B->text + a, b - a);
  lua_rawget(L, -2);
  const char *r = fallback;
  if (lua_type(L, -1) == LUA_TSTRING) {
    size_t n = 0; const char *s = lua_tolstring(L, -1, &n);
    const char *in = intern(s, n);
    if (in) r = in;
  }
  lua_pop(L, 2);
  return r;
}

/* push_tokens: emit the span [a,b), split at the position captures in `caps`,
   each sub-span taking types[k] (NULL -> "normal"). */
static void push_tokens(builder *B, cpattern *cp, long a, long b,
                        long *pos, int npos) {
  if (npos == 0) {
    push_token(B, typed(B, a, b, cp->type0), a, b);
    return;
  }
  /* splits: a, pos[0..npos), b   -> npos+1 spans */
  long prev = a;
  for (int k = 0; k <= npos; k++) {
    long e = (k < npos) ? pos[k] : b;
    if (e > prev) {
      const char *ft = (k < cp->ntypes) ? cp->types[k] : NULL;
      push_token(B, typed(B, prev, e, ft), prev, e);
    }
    prev = e;
  }
}

/* find_text, in bytes. Returns 1 on a confirmed match with [*ms,*me) and the
   position captures in pos/npos; 0 on no match. `which`: 0 = open, 1 = close. */
static int find_text(builder *B, cpattern *cp, long from, int at_start,
                     int which, long *ms, long *me, long *pos, int *npos) {
  delim *d = (which == 1 && cp->has_close) ? &cp->close : &cp->open;
  int anchored = at_start || d->whole_line;
  long cur = from;
  *npos = 0;

  for (;;) {
    if (d->whole_line && cur > 0) return 0;

    long a, b;
    lite_pattern_captures caps;
    caps.n = 0;

    if (d->is_regex) {
      pcre2_match_data *md = pcre2_match_data_create_from_pattern(d->rx, NULL);
      int rc = pcre2_match(d->rx, (PCRE2_SPTR)B->text, B->len, (PCRE2_SIZE)cur,
                           anchored ? PCRE2_ANCHORED : 0, md, NULL);
      if (rc < 0) { pcre2_match_data_free(md); return 0; }
      PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
      if (ov[0] > ov[1]) { pcre2_match_data_free(md); return 0; }
      a = (long)ov[0]; b = (long)ov[1];
      caps.n = rc - 1;
      if (caps.n > LITE_PATTERN_MAXCAPTURES) caps.n = LITE_PATTERN_MAXCAPTURES;
      for (int i = 0; i < caps.n; i++) {
        PCRE2_SIZE gs = ov[2 * (i + 1)], ge = ov[2 * (i + 1) + 1];
        caps.start[i] = (long)gs;
        caps.len[i] = (gs == ge) ? -1 : (long)(ge - gs);
      }
      pcre2_match_data_free(md);
    } else {
      if (!lite_lua_pattern_match(B->L, B->text, B->len, d->lua, d->lua_len,
                                  (size_t)cur, anchored, &a, &b, &caps))
        return 0;
    }

    /* escape check: is the match preceded by an odd run of the escape byte? */
    if (cp->has_esc) {
      int count = 0;
      for (long i = a - 1; i >= 0; i--) {
        if ((unsigned char)B->text[i] != (unsigned char)cp->esc_byte) break;
        count++;
      }
      if (count % 2 != 0) {
        /* escaped: keep looking after this delimiter */
        if (at_start) return 0;
        cur = b;
        if (cur > (long)B->len) return 0;
        continue;
      }
    }

    /* collect position captures (value captures -> we don't model, bail up) */
    int np = 0;
    for (int i = 0; i < caps.n; i++) {
      if (caps.len[i] != -1) { *npos = -1; return 1; } /* signal: value capture */
      if (np >= 64) { *npos = -1; return 1; }          /* signal: too many */
      pos[np++] = caps.start[i];
    }
    *npos = np;
    *ms = a; *me = b;
    return 1;
  }
}

/* Run the scan. Returns 1 on success (tokens/state built), 0 to decline. */
static int scan(builder *B, int state_byte, int *out_state) {
  csyntax *cs = B->cs;
  const char *text = B->text;
  long len = (long)B->len;
  long i = 0;
  int cur_pat = state_byte;   /* 1-based pattern index, or 0 */

  if (cur_pat < 0 || cur_pat > cs->npat) return 0;
  if (cur_pat > 0) {
    cpattern *cp = &cs->pat[cur_pat - 1];
    if (cp->is_subsyntax || cp->disabled || !cp->usable) return 0;
  }

  long pos[64];
  int npos;
  long ms, me;

  while (i < len) {
    /* continue an open pair from a previous line / earlier on this line */
    if (cur_pat > 0) {
      cpattern *cp = &cs->pat[cur_pat - 1];
      const char *mid = cp->type_is_table
        ? (cp->ntypes > 0 ? cp->types[0] : NULL) : cp->type0;
      int hit = find_text(B, cp, i, 0, 1, &ms, &me, pos, &npos);
      if (hit && npos < 0) return 0;               /* value capture */
      if (hit) {
        if (ms > i) push_token(B, mid, i, ms);
        push_tokens(B, cp, ms, me, pos, npos);
        cur_pat = 0;
        i = me;
      } else {
        push_token(B, mid, i, len);
        break;
      }
    }

    /* try every pattern anchored at i */
    int matched = 0;
    for (int n = 1; n <= cs->npat; n++) {
      cpattern *cp = &cs->pat[n - 1];
      if (cp->disabled) continue;
      if (!cp->usable) return 0;
      if (!find_text(B, cp, i, 1, 0, &ms, &me, pos, &npos)) continue;
      if (npos < 0) return 0;                      /* value capture */
      if (me <= ms) continue;                      /* matched nothing */
      if (cp->is_subsyntax) return 0;              /* would enter a subsyntax */
      if (npos == 0 && cp->type_is_table) return 0;/* type/capture mismatch */

      push_tokens(B, cp, ms, me, pos, npos);
      if (cp->is_pair) cur_pat = n;
      i = me;
      matched = 1;
      break;
    }

    if (!matched) {
      if (i >= len) break;   /* a pair just closed exactly at end of line */
      /* consume one character as "normal" */
      long j = i + 1;
      while (j < len && ((unsigned char)text[j] & 0xC0) == 0x80) j++;
      push_token(B, g_normal, i, j);
      i = j;
    }
  }

  *out_state = cur_pat;
  return 1;
}

/* -- Lua entry point ----------------------------------------------------- *
 * tokenizer_c.tokenize(syntax, text, state) ->
 *     true, tokens, new_state    (handled)
 *   | false                      (declined; caller uses the Lua path)     */

static int f_tokenize(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  size_t tlen = 0;
  const char *text = luaL_checklstring(L, 2, &tlen);
  size_t slen = 0;
  const char *state = lua_tolstring(L, 3, &slen);

  int state_byte = 0;
  if (state && slen >= 1) {
    if (slen > 1) { lua_pushboolean(L, 0); return 1; }  /* subsyntax depth */
    state_byte = (unsigned char)state[0];
  }

  csyntax *cs = get_csyntax(L, 1);
  if (!cs || cs->unusable) { lua_pushboolean(L, 0); return 1; }

  builder B = {0};
  B.text = text; B.len = tlen; B.cs = cs; B.L = L;

  int out_state = 0;
  int ok = scan(&B, state_byte, &out_state);
  if (!ok) { free(B.v); lua_pushboolean(L, 0); return 1; }

  lua_pushboolean(L, 1);
  lua_createtable(L, B.n * 2, 0);
  long start = 0;
  for (int k = 0; k < B.n; k++) {
    lua_pushstring(L, B.v[k].type);
    lua_rawseti(L, -2, k * 2 + 1);
    lua_pushlstring(L, text + start, B.v[k].end - start);
    lua_rawseti(L, -2, k * 2 + 2);
    start = B.v[k].end;
  }
  free(B.v);

  char sb = (char)out_state;
  lua_pushlstring(L, &sb, 1);
  return 3;
}

int luaopen_tokenizer_c(lua_State *L) {
  if (!g_normal) g_normal = intern("normal", 6);
  static const luaL_Reg lib[] = {
    { "tokenize", f_tokenize },
    { NULL, NULL }
  };
  luaL_newlib(L, lib);
  return 1;
}
