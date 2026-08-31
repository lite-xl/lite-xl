/*
 * C core for the syntax tokenizer.
 *
 * tokenizer.lua is the reference implementation and the plugin-facing API.
 * This module provides one function, `tokenizer_c.tokenize(syntax, text,
 * state, resume, budget)`, that reproduces `tokenizer.tokenize` byte-for-byte
 * by running the whole per-position scan -- subsyntax push/pop and the
 * byte-string state stack included -- in C instead of crossing into Lua at
 * every position. Like the Lua tokenizer it pauses on a pathological line
 * once `budget` seconds are up and returns a `resume` to be passed back. A
 * line the C core cannot model is declined (returns false) and tokenizer.lua
 * handles it itself.
 *
 * Each syntax table is snapshotted into a `csyntax` once, cached on the table
 * as a `__gc` userdata (`_ctok`), rebuilt if the pattern count changes.
 * Subsyntaxes are resolved lazily from a registry ref stored per pattern.
 */

#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <ctype.h>
#include <stdint.h>

#include <lua.h>
#include <lauxlib.h>
#include <SDL3/SDL.h>

#include "utf8.h"

#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

#define MAX_SYN_DEPTH 32          /* subsyntax nesting the C core will handle */
#define MAX_POS_CAPS  64          /* position captures per pattern */

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

/* -- symbols hash ------------------------------------------------------------ *
 * `syntax.symbols` is a small text -> token-type map. Snapshot it into C so the
 * per-token lookup in typed() costs no Lua calls. */

typedef struct { char *key; size_t klen; const char *type; } syment;
typedef struct { syment *slot; int mask; } symhash;   /* open addressing, cap = mask+1 */

static const char *sym_get(const symhash *h, const char *s, size_t n) {
  if (!h->slot) return NULL;
  uint64_t g = 1469598103934665603ULL;
  for (size_t k = 0; k < n; k++) g = (g ^ (unsigned char)s[k]) * 1099511628211ULL;
  int idx = (int)(g & h->mask);
  for (;;) {
    syment *e = &h->slot[idx];
    if (!e->key) return NULL;
    if (e->klen == n && memcmp(e->key, s, n) == 0) return e->type;
    idx = (idx + 1) & h->mask;
  }
}

static void sym_put(symhash *h, const char *s, size_t n, const char *type) {
  uint64_t g = 1469598103934665603ULL;
  for (size_t k = 0; k < n; k++) g = (g ^ (unsigned char)s[k]) * 1099511628211ULL;
  int idx = (int)(g & h->mask);
  while (h->slot[idx].key) idx = (idx + 1) & h->mask;
  char *c = malloc(n + 1);
  if (!c) return;
  memcpy(c, s, n); c[n] = 0;
  h->slot[idx].key = c;
  h->slot[idx].klen = n;
  h->slot[idx].type = type;
}

static void sym_free(symhash *h) {
  if (!h->slot) return;
  for (int i = 0; i <= h->mask; i++) free(h->slot[i].key);
  free(h->slot);
  h->slot = NULL;
}

/* -- first-byte index ---------------------------------------------------- *
 * A 256-bit set of bytes a pattern's open delimiter can begin a match on, so
 * the scan can skip patterns that can't match at the current byte. Anything
 * uncertain sets `fb_any` -> always try (never wrong, just not filtered). */

typedef struct {
  int is_regex;
  int whole_line;
  char *lua;            /* '^'-stripped Lua pattern body (is_regex == 0) */
  size_t lua_len;
  pcre2_code *rx;       /* borrowed from the Lua _compiled userdata (is_regex) */
} delim;

#define FB_SET(m, c)  ((m)[(unsigned char)(c) >> 3] |= (1u << ((unsigned char)(c) & 7)))
#define FB_HAS(m, c)  ((m)[(unsigned char)(c) >> 3] &  (1u << ((unsigned char)(c) & 7)))

static void fb_all(unsigned char *m) { memset(m, 0xff, 32); }

static void fb_class(unsigned char *m, char cl) {
  int lower = (cl >= 'a');
  char c = lower ? cl : (char)(cl + 32);
  for (int b = 0; b < 128; b++) {
    int in;
    switch (c) {
      case 'a': in = isalpha(b); break;
      case 'd': in = isdigit(b); break;
      case 's': in = isspace(b); break;
      case 'w': in = isalnum(b); break;
      case 'l': in = islower(b); break;
      case 'u': in = isupper(b); break;
      case 'p': in = ispunct(b); break;
      case 'x': in = isxdigit(b); break;
      case 'c': in = iscntrl(b); break;
      default: fb_all(m); return;
    }
    if (lower ? in : !in) FB_SET(m, b);
  }
  /* the matcher is Unicode-aware; any byte >= 0x80 might lead a multibyte
     char that lands in (or, for %A etc., out of) the class -- be safe */
  for (int b = 128; b < 256; b++) FB_SET(m, b);
}

static int fb_is_class(char c) {
  return c && strchr("acdlpsuwxACDLPSUWX", c) != NULL;
}

/* parse a positive [set]; *pp points just past '[', leaves it past ']' */
static void fb_set(unsigned char *m, const char **pp, const char *pe) {
  const char *p = *pp;
  int first = 1;
  while (p < pe) {
    char c = *p;
    if (c == ']' && !first) { *pp = p + 1; return; }
    first = 0;
    if (c == '%' && p + 1 < pe) {
      char cl = p[1];
      if (fb_is_class(cl)) fb_class(m, cl); else FB_SET(m, cl);
      p += 2;
      continue;
    }
    if (p + 2 < pe && p[1] == '-' && p[2] != ']') {
      for (int b = (unsigned char)c; b <= (unsigned char)p[2]; b++) FB_SET(m, b);
      p += 3;
      continue;
    }
    FB_SET(m, c);
    p++;
  }
  *pp = p;
}

/* first-byte set of the leading item of a Lua pattern body; 0 -> uncertain */
static int fb_lua_item(unsigned char *m, const char **pp, const char *pe) {
  const char *p = *pp;
  if (p >= pe) return 0;
  char c = *p++;
  if (c == '%') {
    if (p >= pe) return 0;
    char cl = *p++;
    if (cl == 'f') {                     /* %f[set]: current byte must be in set */
      if (p < pe && *p == '[') {
        p++;
        if (p < pe && *p == '^') return 0;
        *pp = p;
        fb_set(m, pp, pe);
        return 1;
      }
      return 0;
    }
    if (cl == 'b') {                     /* %bxy balanced: starts with x */
      if (p >= pe) return 0;
      FB_SET(m, *p);
      *pp = (p + 2 <= pe) ? p + 2 : pe;
      return 1;
    }
    *pp = p;
    if (fb_is_class(cl)) fb_class(m, cl); else FB_SET(m, cl);
    return 1;
  }
  if (c == '.') { fb_all(m); *pp = p; return 1; }
  if (c == '[') {
    if (p < pe && *p == '^') return 0;        /* negated set: give up */
    *pp = p;
    fb_set(m, pp, pe);
    return 1;
  }
  if (c == '(') {
    if (p < pe && *p == ')') { *pp = p + 1; return fb_lua_item(m, pp, pe); }
    return 0;                                 /* value capture: declined anyway */
  }
  if (c == '^' || c == '$' || c == ')' ||
      c == '*' || c == '+' || c == '-' || c == '?')
    return 0;
  FB_SET(m, c);
  *pp = p;
  return 1;
}

static void fb_compute(unsigned char *m, int *any, delim *d) {
  memset(m, 0, 32);
  *any = 1;
  if (d->is_regex) {
    if (!d->rx) return;
    const uint8_t *bitmap = NULL;
    if (pcre2_pattern_info(d->rx, PCRE2_INFO_FIRSTBITMAP, &bitmap) == 0 && bitmap) {
      memcpy(m, bitmap, 32); *any = 0; return;
    }
    /* pcre2_pattern_info returns 0 only when a fixed first code unit exists */
    uint32_t fcu = 0;
    if (pcre2_pattern_info(d->rx, PCRE2_INFO_FIRSTCODEUNIT, &fcu) == 0 && fcu < 256) {
      FB_SET(m, fcu); *any = 0;
    }
    return;
  }
  const char *p = d->lua, *pe = p + d->lua_len;
  if (p >= pe || *p == '^') return;
  if (!fb_lua_item(m, &p, pe)) { memset(m, 0, 32); return; }
  /* a *, - or ? on the leading item lets it match zero times -> the next item
     could start the match; too involved to chase, so give up */
  if (p < pe && (*p == '*' || *p == '-' || *p == '?')) { memset(m, 0, 32); return; }
  *any = 0;
}

/* Lazily cache require("core.syntax").get for resolving a subsyntax by name. */
static int g_syntax_get_ref = LUA_NOREF;
static int push_syntax_get(lua_State *L) {
  if (g_syntax_get_ref != LUA_NOREF) {
    lua_rawgeti(L, LUA_REGISTRYINDEX, g_syntax_get_ref);
    return lua_isfunction(L, -1) ? 1 : (lua_pop(L, 1), 0);
  }
  lua_getglobal(L, "require");
  if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return 0; }
  lua_pushstring(L, "core.syntax");
  if (lua_pcall(L, 1, 1, 0) != LUA_OK) { lua_pop(L, 1); return 0; }
  lua_getfield(L, -1, "get");
  lua_remove(L, -2);                       /* drop the module, keep .get */
  if (!lua_isfunction(L, -1)) { lua_pop(L, 1); return 0; }
  lua_pushvalue(L, -1);
  g_syntax_get_ref = luaL_ref(L, LUA_REGISTRYINDEX);
  return 1;
}

/* -- compiled syntax snapshot ------------------------------------------------ */

typedef struct {
  int disabled;
  int is_subsyntax;    /* entry has `.syntax` */
  int is_pair;         /* pattern/regex value is a {open, close} table */
  int usable;          /* 0 -> any use of this pattern makes the C core bail */
  int sub_ref;         /* registry ref to the resolved subsyntax table, or NOREF */
  delim open;
  int has_close;
  delim close;
  int has_esc;
  int esc_byte;
  int type_is_table;
  int ntypes;
  const char **types;  /* interned; entry may be NULL ("normal") */
  const char *type0;   /* interned; when type is a plain string */
  unsigned char fb[32];/* bytes the open delimiter can start a match on */
  int fb_any;          /* 1 -> fb is not usable, always try the pattern */
} cpattern;

typedef struct {
  lua_State *L;
  int npat;
  cpattern *pat;
  symhash sym;         /* snapshot of syntax.symbols */
  int unusable;        /* snapshot hit something we don't model -> always bail */
} csyntax;

static void free_delim(delim *d) { free(d->lua); d->lua = NULL; }

static void free_csyntax(csyntax *cs) {
  if (!cs) return;
  for (int i = 0; i < cs->npat; i++) {
    free_delim(&cs->pat[i].open);
    free_delim(&cs->pat[i].close);
    free(cs->pat[i].types);
    if (cs->pat[i].sub_ref != LUA_NOREF && cs->L)
      luaL_unref(cs->L, LUA_REGISTRYINDEX, cs->pat[i].sub_ref);
  }
  free(cs->pat);
  sym_free(&cs->sym);
  cs->pat = NULL; cs->npat = 0;
}

/* Read _compiled[which] (1 = open, 2 = close) into `d`. Sets *bail on anything
   unmodelled. Expects _compiled at stack index `compiled_idx`. */
static int read_delim(lua_State *L, int compiled_idx, int which, delim *d,
                      int *bail) {
  lua_rawgeti(L, compiled_idx, which);
  if (lua_type(L, -1) != LUA_TTABLE) { lua_pop(L, 1); *bail = 1; return 0; }
  int di = lua_gettop(L);

  lua_getfield(L, di, "regex");
  d->is_regex = lua_toboolean(L, -1);
  lua_pop(L, 1);

  lua_getfield(L, di, "whole_line");
  d->whole_line = lua_toboolean(L, -1);
  lua_pop(L, 1);

  if (d->is_regex) {
    lua_getfield(L, di, "rx");
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
  lua_pop(L, 1);
  return 1;
}

static csyntax *get_csyntax(lua_State *L, int synidx);   /* fwd */

/* Build a csyntax from the syntax table at `synidx`. */
static csyntax *build_csyntax(lua_State *L, int synidx) {
  synidx = lua_absindex(L, synidx);
  csyntax *cs = calloc(1, sizeof *cs);
  if (!cs) return NULL;
  cs->L = L;

  lua_getfield(L, synidx, "patterns");
  int patterns = lua_gettop(L);
  int np = (int)lua_rawlen(L, patterns);
  cs->npat = np;
  cs->pat = calloc(np > 0 ? np : 1, sizeof(cpattern));
  if (!cs->pat) { lua_pop(L, 1); free(cs); return NULL; }

  for (int n = 1; n <= np; n++) {
    cpattern *cp = &cs->pat[n - 1];
    cp->usable = 1;
    cp->sub_ref = LUA_NOREF;
    lua_rawgeti(L, patterns, n);
    int ei = lua_gettop(L);

    lua_getfield(L, ei, "disabled");
    cp->disabled = lua_toboolean(L, -1);
    lua_pop(L, 1);

    /* .syntax: a subsyntax table (inline) or a name to resolve later */
    lua_getfield(L, ei, "syntax");
    if (lua_istable(L, -1)) {
      cp->is_subsyntax = 1;
      cp->sub_ref = luaL_ref(L, LUA_REGISTRYINDEX);   /* pops it */
    } else if (lua_isstring(L, -1)) {
      cp->is_subsyntax = 1;
      if (push_syntax_get(L)) {                       /* stack: name, get */
        lua_insert(L, -2);                            /* stack: get, name */
        if (lua_pcall(L, 1, 1, 0) == LUA_OK && lua_istable(L, -1))
          cp->sub_ref = luaL_ref(L, LUA_REGISTRYINDEX);
        else { lua_pop(L, 1); cp->usable = 0; }
      } else { lua_pop(L, 1); cp->usable = 0; }
    } else {
      lua_pop(L, 1);
    }

    /* is_pair: pattern or regex value is a table */
    lua_getfield(L, ei, "pattern");
    int pat_is_table = lua_type(L, -1) == LUA_TTABLE;
    lua_pop(L, 1);
    lua_getfield(L, ei, "regex");
    int rgx_is_table = lua_type(L, -1) == LUA_TTABLE;
    lua_pop(L, 1);
    cp->is_pair = pat_is_table || rgx_is_table;

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
        lua_getfield(L, ci, "esc_byte");
        if (lua_isnumber(L, -1)) { cp->has_esc = 1; cp->esc_byte = (int)lua_tointeger(L, -1); }
        lua_pop(L, 1);
        if (!cp->has_esc) {
          lua_getfield(L, ci, "esc");
          size_t en = 0; const char *es = lua_tolstring(L, -1, &en);
          if (es && en == 1) { cp->has_esc = 1; cp->esc_byte = (unsigned char)es[0]; }
          else if (es && en > 1) cp->usable = 0;
          lua_pop(L, 1);
        }
        lua_getfield(L, ci, "err");
        if (!lua_isnil(L, -1)) cp->usable = 0;
        lua_pop(L, 1);
        if (bail) cp->usable = 0;
        lua_pop(L, 1);
      }
      fb_compute(cp->fb, &cp->fb_any, &cp->open);
    } else {
      cp->fb_any = 1;
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
    lua_pop(L, 1);
    if (!cp->type0 && cp->ntypes == 1 && !cp->type_is_table)
      cs->unusable = 1;

    lua_pop(L, 1);                                /* entry */
  }
  lua_pop(L, 1);                                  /* patterns */

  lua_getfield(L, synidx, "symbols");
  if (lua_type(L, -1) == LUA_TTABLE) {
    int count = 0;
    lua_pushnil(L);
    while (lua_next(L, -2)) { count++; lua_pop(L, 1); }
    if (count > 0) {
      int cap = 8;
      while (cap < count * 2) cap <<= 1;
      cs->sym.slot = calloc(cap, sizeof(syment));
      cs->sym.mask = cap - 1;
      lua_pushnil(L);
      while (lua_next(L, -2)) {
        if (lua_type(L, -2) == LUA_TSTRING && lua_type(L, -1) == LUA_TSTRING) {
          size_t kn = 0, vn = 0;
          const char *k = lua_tolstring(L, -2, &kn);
          const char *v = lua_tolstring(L, -1, &vn);
          const char *iv = intern(v, vn);
          if (!iv) cs->unusable = 1;
          else sym_put(&cs->sym, k, kn, iv);
        }
        lua_pop(L, 1);
      }
    }
  }
  lua_pop(L, 1);

  return cs;
}

static int csyntax_gc(lua_State *L) {
  csyntax **p = lua_touserdata(L, 1);
  if (p && *p) { free_csyntax(*p); free(*p); *p = NULL; }
  return 0;
}

/* Cached (or freshly built) csyntax for the syntax table at `synidx`.
   NULL means "cannot model", caller falls back to Lua. */
static csyntax *get_csyntax(lua_State *L, int synidx) {
  synidx = lua_absindex(L, synidx);
  if (lua_type(L, synidx) != LUA_TTABLE) return NULL;

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
  long start;             /* byte offset this call's scan began at (for merge) */
  tok *v;
  int n, cap;
  csyntax *base;
  lua_State *L;
  pcre2_match_data *md;   /* one per scan, reused across match attempts */
} builder;

static csyntax *resolve_sub(builder *B, cpattern *cp) {
  if (cp->sub_ref == LUA_NOREF) return NULL;
  lua_rawgeti(B->L, LUA_REGISTRYINDEX, cp->sub_ref);
  csyntax *sub = get_csyntax(B->L, -1);
  lua_pop(B->L, 1);
  return sub;
}

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
    long pa = (B->n >= 2) ? B->v[B->n - 2].end : B->start;
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

/* syn.symbols[text[a..b)] or fallback -- a pure C lookup */
static const char *typed(builder *B, csyntax *syn, long a, long b,
                         const char *fallback) {
  const char *t = sym_get(&syn->sym, B->text + a, b - a);
  return t ? t : fallback;
}

/* push_tokens: emit [a,b), split at the position captures in `pos`, each
   sub-span taking types[k] (NULL -> "normal"). */
static void push_tokens(builder *B, csyntax *syn, cpattern *cp, long a, long b,
                        long *pos, int npos) {
  if (npos == 0) {
    /* whole match, one token: a plain `type` string, or a `type` table's
       first entry (see push_tokens in tokenizer.lua) */
    const char *ft = cp->type0 ? cp->type0
                   : (cp->ntypes > 0 ? cp->types[0] : NULL);
    push_token(B, typed(B, syn, a, b, ft), a, b);
    return;
  }
  long prev = a;
  for (int k = 0; k <= npos; k++) {
    long e = (k < npos) ? pos[k] : b;
    if (e > prev) {
      const char *ft = (k < cp->ntypes) ? cp->types[k] : NULL;
      push_token(B, typed(B, syn, prev, e, ft), prev, e);
    }
    prev = e;
  }
}

/* find_text, in bytes. Returns 1 on a confirmed match with [*ms,*me) and the
   position captures in pos/npos; 0 on no match. npos < 0 signals a capture
   shape the C core cannot model (value capture, or too many) -> caller bails.
   `which`: 0 = open delimiter, 1 = close. */
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
      if (!B->md) B->md = pcre2_match_data_create(64, NULL);
      int rc = B->md
        ? pcre2_match(d->rx, (PCRE2_SPTR)B->text, B->len, (PCRE2_SIZE)cur,
                      anchored ? PCRE2_ANCHORED : 0, B->md, NULL)
        : PCRE2_ERROR_NOMEMORY;
      if (rc <= 0) return 0;   /* no match, or >63 groups (not a real syntax) */
      PCRE2_SIZE *ov = pcre2_get_ovector_pointer(B->md);
      if (ov[0] > ov[1]) return 0;
      a = (long)ov[0]; b = (long)ov[1];
      caps.n = rc - 1;
      if (caps.n > LITE_PATTERN_MAXCAPTURES) caps.n = LITE_PATTERN_MAXCAPTURES;
      for (int i = 0; i < caps.n; i++) {
        PCRE2_SIZE gs = ov[2 * (i + 1)], ge = ov[2 * (i + 1) + 1];
        caps.start[i] = (long)gs;
        caps.len[i] = (gs == ge) ? -1 : (long)(ge - gs);
      }
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
        if (at_start) return 0;
        cur = b;
        if (cur > (long)B->len) return 0;
        continue;
      }
    }

    int np = 0;
    for (int i = 0; i < caps.n; i++) {
      if (caps.len[i] != -1) { *npos = -1; return 1; } /* value capture */
      if (np >= MAX_POS_CAPS) { *npos = -1; return 1; }
      pos[np++] = caps.start[i];
    }
    *npos = np;
    *ms = a; *me = b;
    return 1;
  }
}

/* -- the state stack ----------------------------------------------------- *
 * A mirror of tokenize()'s locals. `st` is the byte-string state stack; the
 * rest is what retrieve_syntax_state() derives from it. The `csyntax` a `cs`
 * points at stays reachable (anchored on syntax tables and per-pattern
 * `sub_ref`s) and is only rebuilt when its pattern count changes -- which the
 * highlighter never does mid-line -- so the pointers hold for one scan(). */

typedef struct {
  unsigned char st[MAX_SYN_DEPTH + 1];
  int stlen;
  int level;                /* current_level (1-indexed write pos in st) */
  int depth;               /* subsyntax nesting, capped at MAX_SYN_DEPTH */
  csyntax *cur;            /* current_syntax */
  cpattern *ss_info;       /* subsyntax_info -- the .syntax pattern in the parent */
  int cur_pat;             /* current_pattern_idx, or 0 */
} sstate;

/* set_subsyntax_pattern_idx */
static void set_ss_pat(sstate *S, int pidx) {
  if (S->level > S->stlen) S->st[S->stlen++] = (unsigned char)pidx;
  else S->st[S->level - 1] = (unsigned char)pidx;
}

/* retrieve_syntax_state: (re)derive cur / ss_info / cur_pat / level / frames
   from S->st. Returns 0 to decline. */
static int retrieve(builder *B, sstate *S) {
  S->depth = 0;
  S->cur = B->base; S->ss_info = NULL;
  S->cur_pat = (S->stlen > 0) ? S->st[0] : 0;
  S->level = 1;

  if (S->cur_pat > 0 && S->cur_pat <= S->cur->npat) {
    for (int i = 1; i <= S->stlen; i++) {
      int target = S->st[i - 1];
      if (target == 0) break;
      if (target > S->cur->npat) return 0;
      cpattern *tp = &S->cur->pat[target - 1];
      if (tp->is_subsyntax) {
        csyntax *sub = resolve_sub(B, tp);
        if (!sub || sub->unusable || ++S->depth >= MAX_SYN_DEPTH) return 0;
        S->ss_info = tp; S->cur = sub; S->cur_pat = 0; S->level = i + 1;
      } else {
        S->cur_pat = target;
        break;
      }
    }
  } else if (S->cur_pat > 0) {
    return 0;   /* stale state byte: Lua would crash here */
  }
  return 1;
}

/* Run the scan from byte `start` to the end of the line, or until `deadline`
   (an SDL performance-counter value; 0 = no limit) is passed -- then it stops,
   sets *incomplete, and leaves *out_byte at the position reached so the caller
   can resume. Returns 1 on success (tokens + out_state built), 0 to decline. */
static int scan(builder *B, const unsigned char *state, int state_len,
                long start, Uint64 deadline,
                unsigned char *out_state, int *out_state_len,
                long *out_byte, int *incomplete) {
  sstate S;
  if (state_len > MAX_SYN_DEPTH) return 0;
  S.stlen = state_len;
  memcpy(S.st, state, state_len);
  if (S.stlen == 0) { S.st[0] = 0; S.stlen = 1; }   /* state = state or "\0" */

  if (!retrieve(B, &S)) return 0;

  long i = start, len = (long)B->len, checked = start;
  int checked_n = 0;
  const char *text = B->text;
  long pos[MAX_POS_CAPS], ms, me;
  int npos;
  *incomplete = 0;

  while (i < len) {
    if (deadline && (i - checked >= 512 || B->n - checked_n >= 2048)) {
      checked = i; checked_n = B->n;
      if (SDL_GetPerformanceCounter() >= deadline) { *incomplete = 1; break; }
    }
    /* --- continue an open pair --- */
    if (S.cur_pat > 0) {
      if (S.cur_pat > S.cur->npat) return 0;
      cpattern *cp = &S.cur->pat[S.cur_pat - 1];
      if (!cp->usable) return 0;
      const char *mid = cp->type_is_table
        ? (cp->ntypes > 0 ? cp->types[0] : NULL) : cp->type0;

      int hit = find_text(B, cp, i, 0, 1, &ms, &me, pos, &npos);
      if (hit && npos < 0) return 0;

      int cont = 1;
      if (S.ss_info) {
        long ss, se, sp[MAX_POS_CAPS]; int snp;
        int sshit = find_text(B, S.ss_info, i, 0, 1, &ss, &se, sp, &snp);
        if (sshit && snp < 0) return 0;
        if (sshit && (!hit || ss < ms)) {
          push_token(B, mid, i, ss);
          i = ss;
          cont = 0;
        }
      }
      if (cont) {
        if (hit) {
          if (ms > i) push_token(B, mid, i, ms);
          push_tokens(B, S.cur, cp, ms, me, pos, npos);
          set_ss_pat(&S, 0);
          S.cur_pat = 0;
          i = me;
        } else {
          push_token(B, mid, i, len);
          break;
        }
      }
    }

    /* --- end of the current subsyntax? (may pop several) --- */
    while (S.ss_info) {
      long s, e, p[MAX_POS_CAPS]; int np;
      int hit = find_text(B, S.ss_info, i, 1, 1, &s, &e, p, &np);
      if (hit && np < 0) return 0;
      if (!hit) break;
      push_tokens(B, S.cur, S.ss_info, s, e, p, np);
      /* pop_subsyntax */
      S.level--;
      S.stlen = S.level;
      set_ss_pat(&S, 0);
      if (!retrieve(B, &S)) return 0;
      i = e;
    }

    /* --- try every pattern of the current syntax anchored at i --- */
    int matched = 0;
    unsigned char c0 = (unsigned char)text[i];
    for (int n = 1; n <= S.cur->npat; n++) {
      cpattern *cp = &S.cur->pat[n - 1];
      if (cp->disabled) continue;
      if (!cp->usable) return 0;
      /* a match here would start at text[i]; skip patterns that can't */
      if (!cp->fb_any && !FB_HAS(cp->fb, c0)) continue;
      if (cp->open.whole_line && i > 0) continue;
      if (!find_text(B, cp, i, 1, 0, &ms, &me, pos, &npos)) continue;
      if (npos < 0) return 0;
      if (me <= ms) continue;                        /* matched nothing */

      push_tokens(B, S.cur, cp, ms, me, pos, npos);

      if (cp->is_pair) {
        if (cp->is_subsyntax) {
          csyntax *sub = resolve_sub(B, cp);
          if (!sub || sub->unusable || ++S.depth >= MAX_SYN_DEPTH) return 0;
          set_ss_pat(&S, n);
          S.level++;
          S.cur = sub; S.ss_info = cp; S.cur_pat = 0;
        } else {
          set_ss_pat(&S, n);
          S.cur_pat = n;
        }
      }
      i = me;
      matched = 1;
      break;
    }

    if (!matched) {
      if (i >= len) break;
      long j = i + 1;
      while (j < len && ((unsigned char)text[j] & 0xC0) == 0x80) j++;
      push_token(B, g_normal, i, j);
      i = j;
    }
  }

  memcpy(out_state, S.st, S.stlen);
  *out_state_len = S.stlen;
  *out_byte = i;
  return 1;
}

/* -- Lua entry point ----------------------------------------------------- *
 * tokenizer_c.tokenize(syntax, text, state, resume, budget) ->
 *     true, tokens, new_state, resume?   (handled; `resume` non-nil = paused)
 *   | false                              (declined; caller uses the Lua path)
 *
 * `budget` is the seconds a single call may spend before it pauses on a very
 * long line, emits a trailing "incomplete" token and returns a `resume` table
 *   { c = true, i = <byte offset>, state = <state string>, res = <tokens> }
 * to be passed straight back. `tokens` is accumulated across calls. */

static int pop_trailing_incomplete(lua_State *L, int t) {
  int n = (int)lua_rawlen(L, t);
  while (n >= 2) {
    lua_rawgeti(L, t, n - 1);
    int inc = lua_type(L, -1) == LUA_TSTRING
           && strcmp(lua_tostring(L, -1), "incomplete") == 0;
    lua_pop(L, 1);
    if (!inc) break;
    lua_pushnil(L); lua_rawseti(L, t, n);
    lua_pushnil(L); lua_rawseti(L, t, n - 1);
    n -= 2;
  }
  return n;
}

static int f_tokenize(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  size_t tlen = 0;
  const char *text = luaL_checklstring(L, 2, &tlen);

  int resuming = lua_type(L, 4) == LUA_TTABLE;
  double budget = luaL_optnumber(L, 5, 0.0);

  unsigned char st[MAX_SYN_DEPTH + 1];
  int stlen = 0;
  long start_byte = 0;

  if (resuming) {
    lua_getfield(L, 4, "i");
    start_byte = (long)lua_tointeger(L, -1);
    lua_pop(L, 1);
    lua_getfield(L, 4, "state");
    size_t n = 0; const char *rs = lua_tolstring(L, -1, &n);
    if (rs && n <= MAX_SYN_DEPTH) { memcpy(st, rs, n); stlen = (int)n; }
    lua_pop(L, 1);
  } else {
    size_t n = 0; const char *s = lua_tolstring(L, 3, &n);
    if (s && n <= MAX_SYN_DEPTH) { memcpy(st, s, n); stlen = (int)n; }
  }
  if (start_byte < 0 || start_byte > (long)tlen) start_byte = 0;

  csyntax *cs = get_csyntax(L, 1);
  if (!cs || cs->unusable) { lua_pushboolean(L, 0); return 1; }

  builder B = {0};
  B.text = text; B.len = tlen; B.base = cs; B.L = L; B.start = start_byte;

  Uint64 deadline = 0;
  if (budget > 0)
    deadline = SDL_GetPerformanceCounter()
             + (Uint64)(budget * (double)SDL_GetPerformanceFrequency());

  unsigned char out_state[MAX_SYN_DEPTH + 1];
  int out_len = 0, incomplete = 0;
  long out_byte = 0;
  int ok = scan(&B, st, stlen, start_byte, deadline,
                out_state, &out_len, &out_byte, &incomplete);
  if (B.md) pcre2_match_data_free(B.md);
  if (!ok) { free(B.v); lua_pushboolean(L, 0); return 1; }

  lua_pushboolean(L, 1);

  /* the token array: reuse resume.res, else a fresh one. If this first call
     paused, the line will grow the array across many more calls -- size it
     now from the token density we just saw, so it doesn't rehash each call. */
  int prealloc = B.n * 2;
  if (incomplete && !resuming && out_byte > start_byte) {
    long est = (long)B.n * (long)(tlen - start_byte) / (out_byte - start_byte);
    est = (est * 12) / 5 + 16;                     /* ~2.4x slack, in entries */
    if (est > prealloc) prealloc = est > (1 << 26) ? (1 << 26) : (int)est;
  }
  int base_n = 0, merge_first = 0;
  if (resuming) {
    lua_getfield(L, 4, "res");
    if (lua_type(L, -1) != LUA_TTABLE) { lua_pop(L, 1); lua_createtable(L, prealloc, 0); }
    else {
      base_n = pop_trailing_incomplete(L, lua_gettop(L));
      /* Does the first new token merge into the last one already in `res`?
         push_token's rule across the pause boundary: same type, or the
         previous token is all whitespace. (The C core never emits
         "incomplete", so that clause of the rule can't apply here.) */
      if (base_n >= 2 && B.n > 0) {
        lua_rawgeti(L, lua_gettop(L), base_n - 1);   /* prev type */
        int same = lua_type(L, -1) == LUA_TSTRING
                && strcmp(lua_tostring(L, -1), B.v[0].type) == 0;
        lua_pop(L, 1);
        int ws = 0;
        lua_rawgeti(L, lua_gettop(L), base_n);       /* prev text */
        size_t pn = 0; const char *pt = lua_tolstring(L, -1, &pn);
        if (pt) { ws = 1; for (size_t z = 0; z < pn; z++) {
          char pc = pt[z];
          if (pc!=' '&&pc!='\t'&&pc!='\n'&&pc!='\v'&&pc!='\f'&&pc!='\r') { ws = 0; break; }
        } }
        lua_pop(L, 1);
        merge_first = same || ws;
      }
    }
  } else {
    lua_createtable(L, prealloc, 0);
  }
  int rt = lua_gettop(L);

  long start = start_byte;
  for (int k = 0; k < B.n; k++) {
    if (k == 0 && merge_first) {
      /* overwrite res[base_n-1 / base_n] with the merged token */
      lua_pushstring(L, B.v[0].type);
      lua_rawseti(L, rt, base_n - 1);
      lua_rawgeti(L, rt, base_n);                    /* old text */
      lua_pushlstring(L, text + start, B.v[0].end - start);
      lua_concat(L, 2);
      lua_rawseti(L, rt, base_n);
      start = B.v[0].end;
      base_n -= 2;                                   /* k>=1 lands right after */
      continue;
    }
    lua_pushstring(L, B.v[k].type);
    lua_rawseti(L, rt, base_n + k * 2 + 1);
    lua_pushlstring(L, text + start, B.v[k].end - start);
    lua_rawseti(L, rt, base_n + k * 2 + 2);
    start = B.v[k].end;
  }
  free(B.v);

  if (incomplete) {
    int n = (int)lua_rawlen(L, rt);
    lua_pushstring(L, "incomplete");
    lua_rawseti(L, rt, n + 1);
    lua_pushlstring(L, text + out_byte, tlen - out_byte);
    lua_rawseti(L, rt, n + 2);
    lua_pushlstring(L, "\0", 1);                 /* new_state */
    lua_createtable(L, 0, 3);                    /* resume */
    lua_pushboolean(L, 1);          lua_setfield(L, -2, "c");
    lua_pushinteger(L, out_byte);   lua_setfield(L, -2, "i");
    lua_pushlstring(L, (const char *)out_state, out_len);
    lua_setfield(L, -2, "state");
    lua_pushvalue(L, rt);          lua_setfield(L, -2, "res");
    return 4;
  }

  lua_pushlstring(L, (const char *)out_state, out_len);
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
