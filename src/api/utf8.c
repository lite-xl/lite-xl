/*
 * Integration of https://github.com/starwing/luautf8
 *
 * MIT License
 *
 * Copyright (c) 2018 Xavier Wang
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>


#include <assert.h>
#include <string.h>

#include "../unidata.h"

/* UTF-8 string operations */

#define UTF8_BUFFSZ 8
#define UTF8_MAX    0x7FFFFFFFu
#define UTF8_MAXCP  0x10FFFFu
#define iscont(p)   ((*(p) & 0xC0) == 0x80)
#define CAST(tp,expr) ((tp)(expr))

#ifndef LUA_QL
# define LUA_QL(x) "'" x "'"
#endif

static int utf8_invalid (utfint ch)
{ return (ch > UTF8_MAXCP || (0xD800u <= ch && ch <= 0xDFFFu)); }

static size_t utf8_encode (char *buff, utfint x) {
  int n = 1;  /* number of bytes put in buffer (backwards) */
  lua_assert(x <= UTF8_MAX);
  if (x < 0x80)  /* ascii? */
    buff[UTF8_BUFFSZ - 1] = x & 0x7F;
  else {  /* need continuation bytes */
    utfint mfb = 0x3f;  /* maximum that fits in first byte */
    do {  /* add continuation bytes */
      buff[UTF8_BUFFSZ - (n++)] = 0x80 | (x & 0x3f);
      x >>= 6;  /* remove added bits */
      mfb >>= 1;  /* now there is one less bit available in first byte */
    } while (x > mfb);  /* still needs continuation byte? */
    buff[UTF8_BUFFSZ - n] = ((~mfb << 1) | x) & 0xFF;  /* add first byte */
  }
  return n;
}

static const char *utf8_decode (const char *s, utfint *val, int strict) {
  static const utfint limits[] =
  {~0u, 0x80u, 0x800u, 0x10000u, 0x200000u, 0x4000000u};
  unsigned int c = (unsigned char)s[0];
  utfint res = 0;  /* final result */
  if (c < 0x80)  /* ascii? */
    res = c;
  else {
    int count = 0;  /* to count number of continuation bytes */
    for (; c & 0x40; c <<= 1) {  /* while it needs continuation bytes... */
      unsigned int cc = (unsigned char)s[++count];  /* read next byte */
      if ((cc & 0xC0) != 0x80)  /* not a continuation byte? */
        return NULL;  /* invalid byte sequence */
      res = (res << 6) | (cc & 0x3F);  /* add lower 6 bits from cont. byte */
    }
    res |= ((utfint)(c & 0x7F) << (count * 5));  /* add first byte */
    if (count > 5 || res > UTF8_MAX || res < limits[count])
      return NULL;  /* invalid byte sequence */
    s += count;  /* skip continuation bytes read */
  }
  if (strict) {
    /* check for invalid code points; too large or surrogates */
    if (res > UTF8_MAXCP || (0xD800u <= res && res <= 0xDFFFu))
      return NULL;
  }
  if (val) *val = res;
  return s + 1;  /* +1 to include first byte */
}

static const char *utf8_prev (const char *s, const char *e) {
  while (s < e && iscont(e - 1)) --e;
  return s < e ? e - 1 : s;
}

static const char *utf8_next (const char *s, const char *e) {
  while (s < e && iscont(s + 1)) ++s;
  return s < e ? s + 1 : e;
}

static size_t utf8_length (const char *s, const char *e) {
  size_t i;
  for (i = 0; s < e; ++i)
    s = utf8_next(s, e);
  return i;
}

static const char *utf8_offset (const char *s, const char *e, lua_Integer offset, lua_Integer idx) {
  const char *p = s + offset - 1;
  if (idx >= 0) {
    while (p < e && idx > 0)
      p = utf8_next(p, e), --idx;
    return idx == 0 ? p : NULL;
  } else {
    while (s < p && idx < 0)
      p = utf8_prev(s, p), ++idx;
    return idx == 0 ? p : NULL;
  }
}

static const char *utf8_relat (const char *s, const char *e, int idx) {
  return idx >= 0 ?
    utf8_offset(s, e, 1, idx - 1) :
    utf8_offset(s, e, e-s+1, idx);
}

static int utf8_range(const char *s, const char *e, lua_Integer *i, lua_Integer *j) {
  const char *ps = utf8_relat(s, e, CAST(int, *i));
  const char *pe = utf8_relat(s, e, CAST(int, *j));
  *i = (ps ? ps : (*i > 0 ? e : s)) - s;
  *j = (pe ? utf8_next(pe, e) : (*j > 0 ? e : s)) - s;
  return *i < *j;
}


/* Unicode character categories */

#define table_size(t) (sizeof(t)/sizeof((t)[0]))

#define utf8_categories(X) \
  X('a', alpha) \
  X('c', cntrl) \
  X('d', digit) \
  X('l', lower) \
  X('p', punct) \
  X('s', space) \
  X('t', compose) \
  X('u', upper) \
  X('x', xdigit)

#define utf8_converters(X) \
  X(lower) \
  X(upper) \
  X(title) \
  X(fold)

static int find_in_range (range_table *t, size_t size, utfint ch) {
  size_t begin, end;

  begin = 0;
  end = size;

  while (begin < end) {
    size_t mid = (begin + end) / 2;
    if (t[mid].last < ch)
      begin = mid + 1;
    else if (t[mid].first > ch)
      end = mid;
    else
      return (ch - t[mid].first) % t[mid].step == 0;
  }

  return 0;
}

static int convert_char (conv_table *t, size_t size, utfint ch) {
  size_t begin, end;

  begin = 0;
  end = size;

  while (begin < end) {
    size_t mid = (begin + end) / 2;
    if (t[mid].last < ch)
      begin = mid + 1;
    else if (t[mid].first > ch)
      end = mid;
    else if ((ch - t[mid].first) % t[mid].step == 0)
      return ch + t[mid].offset;
    else
      return ch;
  }

  return ch;
}

#define define_category(cls, name) static int utf8_is##name (utfint ch)\
{ return find_in_range(name##_table, table_size(name##_table), ch); }
#define define_converter(name) static utfint utf8_to##name (utfint ch) \
{ return convert_char(to##name##_table, table_size(to##name##_table), ch); }
utf8_categories(define_category)
utf8_converters(define_converter)
#undef define_category
#undef define_converter

static int utf8_isgraph (utfint ch) {
  if (find_in_range(space_table, table_size(space_table), ch))
    return 0;
  if (find_in_range(graph_table, table_size(graph_table), ch))
    return 1;
  if (find_in_range(compose_table, table_size(compose_table), ch))
    return 1;
  return 0;
}

static int utf8_isalnum (utfint ch) {
  if (find_in_range(alpha_table, table_size(alpha_table), ch))
    return 1;
  if (find_in_range(alnum_extend_table, table_size(alnum_extend_table), ch))
    return 1;
  return 0;
}

static int utf8_width (utfint ch, int ambi_is_single) {
  if (find_in_range(doublewidth_table, table_size(doublewidth_table), ch))
    return 2;
  if (find_in_range(ambiwidth_table, table_size(ambiwidth_table), ch))
    return ambi_is_single ? 1 : 2;
  if (find_in_range(compose_table, table_size(compose_table), ch))
    return 0;
  if (find_in_range(unprintable_table, table_size(unprintable_table), ch))
    return 0;
  return 1;
}


/* string module compatible interface */

static int typeerror (lua_State *L, int idx, const char *tname)
{ return luaL_error(L, "%s expected, got %s", tname, luaL_typename(L, idx)); }

static const char *check_utf8 (lua_State *L, int idx, const char **end) {
  size_t len;
  const char *s = luaL_checklstring(L, idx, &len);
  if (end) *end = s+len;
  return s;
}

static const char *to_utf8 (lua_State *L, int idx, const char **end) {
  size_t len;
  const char *s = lua_tolstring(L, idx, &len);
  if (end) *end = s+len;
  return s;
}

static const char *utf8_safe_decode (lua_State *L, const char *p, utfint *pval) {
  p = utf8_decode(p, pval, 0);
  if (p == NULL) luaL_error(L, "invalid UTF-8 code");
  return p;
}

static void add_utf8char (luaL_Buffer *b, utfint ch) {
  char buff[UTF8_BUFFSZ];
  size_t n = utf8_encode(buff, ch);
  luaL_addlstring(b, buff+UTF8_BUFFSZ-n, n);
}

static lua_Integer byte_relat (lua_Integer pos, size_t len) {
  if (pos >= 0) return pos;
  else if (0u - (size_t)pos > len) return 0;
  else return (lua_Integer)len + pos + 1;
}

static int Lutf8_len (lua_State *L) {
  size_t len, n;
  const char *s = luaL_checklstring(L, 1, &len), *p, *e;
  lua_Integer posi = byte_relat(luaL_optinteger(L, 2, 1), len);
  lua_Integer pose = byte_relat(luaL_optinteger(L, 3, -1), len);
  int lax = lua_toboolean(L, 4);
  luaL_argcheck(L, 1 <= posi && --posi <= (lua_Integer)len, 2,
                   "initial position out of string");
  luaL_argcheck(L, --pose < (lua_Integer)len, 3,
                   "final position out of string");
  for (n = 0, p=s+posi, e=s+pose+1; p < e; ++n) {
    if (lax)
      p = utf8_next(p, e);
    else {
      utfint ch;
      const char *np = utf8_decode(p, &ch, !lax);
      if (np == NULL || utf8_invalid(ch)) {
        lua_pushnil(L);
        lua_pushinteger(L, p - s + 1);
        return 2;
      }
      p = np;
    }
  }
  lua_pushinteger(L, n);
  return 1;
}

static int Lutf8_sub (lua_State *L) {
  const char *e, *s = check_utf8(L, 1, &e);
  lua_Integer posi = luaL_checkinteger(L, 2);
  lua_Integer pose = luaL_optinteger(L, 3, -1);
  if (utf8_range(s, e, &posi, &pose))
    lua_pushlstring(L, s+posi, pose-posi);
  else
    lua_pushliteral(L, "");
  return 1;
}

static int Lutf8_reverse (lua_State *L) {
  luaL_Buffer b;
  const char *prev, *pprev, *ends, *e, *s = check_utf8(L, 1, &e);
  (void) ends;
  int lax = lua_toboolean(L, 2);
  luaL_buffinit(L, &b);
  if (lax) {
    for (prev = e; s < prev; e = prev) {
      prev = utf8_prev(s, prev);
      luaL_addlstring(&b, prev, e-prev);
    }
  } else {
    for (prev = e; s < prev; prev = pprev) {
      utfint code = 0;
      ends = utf8_safe_decode(L, pprev = utf8_prev(s, prev), &code);
      assert(ends == prev);
      if (utf8_invalid(code))
        return luaL_error(L, "invalid UTF-8 code");
      if (!utf8_iscompose(code)) {
        luaL_addlstring(&b, pprev, e-pprev);
        e = pprev;
      }
    }
  }
  luaL_pushresult(&b);
  return 1;
}

static int Lutf8_byte (lua_State *L) {
  size_t n = 0;
  const char *e, *s = check_utf8(L, 1, &e);
  lua_Integer posi = luaL_optinteger(L, 2, 1);
  lua_Integer pose = luaL_optinteger(L, 3, posi);
  if (utf8_range(s, e, &posi, &pose)) {
    for (e = s + pose, s = s + posi; s < e; ++n) {
      utfint ch = 0;
      s = utf8_safe_decode(L, s, &ch);
      lua_pushinteger(L, ch);
    }
  }
  return CAST(int, n);
}

static int Lutf8_codepoint (lua_State *L) {
  const char *e, *s = check_utf8(L, 1, &e);
  size_t len = e-s;
  lua_Integer posi = byte_relat(luaL_optinteger(L, 2, 1), len);
  lua_Integer pose = byte_relat(luaL_optinteger(L, 3, posi), len);
  int lax = lua_toboolean(L, 4);
  int n;
  const char *se;
  luaL_argcheck(L, posi >= 1, 2, "out of range");
  luaL_argcheck(L, pose <= (lua_Integer)len, 3, "out of range");
  if (posi > pose) return 0;  /* empty interval; return no values */
  if (pose - posi >= INT_MAX)  /* (lua_Integer -> int) overflow? */
    return luaL_error(L, "string slice too long");
  n = (int)(pose -  posi + 1);
  luaL_checkstack(L, n, "string slice too long");
  n = 0;  /* count the number of returns */
  se = s + pose;  /* string end */
  for (s += posi - 1; s < se;) {
    utfint code = 0;
    s = utf8_safe_decode(L, s, &code);
    if (!lax && utf8_invalid(code))
      return luaL_error(L, "invalid UTF-8 code");
    lua_pushinteger(L, code);
    n++;
  }
  return n;
}

static int Lutf8_char (lua_State *L) {
  int i, n = lua_gettop(L); /* number of arguments */
  luaL_Buffer b;
  luaL_buffinit(L, &b);
  for (i = 1; i <= n; ++i) {
    lua_Integer code = luaL_checkinteger(L, i);
    luaL_argcheck(L, code <= UTF8_MAXCP, i, "value out of range");
    add_utf8char(&b, CAST(utfint, code));
  }
  luaL_pushresult(&b);
  return 1;
}

#define bind_converter(name)                                   \
static int Lutf8_##name (lua_State *L) {                        \
  int t = lua_type(L, 1);                                      \
  if (t == LUA_TNUMBER)                                        \
    lua_pushinteger(L, utf8_to##name(CAST(utfint, lua_tointeger(L, 1))));    \
  else if (t == LUA_TSTRING) {                                 \
    luaL_Buffer b;                                             \
    const char *e, *s = to_utf8(L, 1, &e);                     \
    luaL_buffinit(L, &b);                                      \
    while (s < e) {                                            \
      utfint ch = 0;                                             \
      s = utf8_safe_decode(L, s, &ch);                         \
      add_utf8char(&b, utf8_to##name(ch));                     \
    }                                                          \
    luaL_pushresult(&b);                                       \
  }                                                            \
  else return typeerror(L, 1, "number/string");                \
  return 1;                                                    \
}
utf8_converters(bind_converter)
#undef bind_converter


/* unicode extra interface */

static const char *parse_escape (lua_State *L, const char *s, const char *e, int hex, utfint *pch) {
  utfint code = 0;
  int in_bracket = 0;
  if (*s == '{') ++s, in_bracket = 1;
  for (; s < e; ++s) {
    utfint ch = (unsigned char)*s;
    if (ch >= '0' && ch <= '9') ch = ch - '0';
    else if (hex && ch >= 'A' && ch <= 'F') ch = 10 + (ch - 'A');
    else if (hex && ch >= 'a' && ch <= 'f') ch = 10 + (ch - 'a');
    else if (!in_bracket) break;
    else if (ch == '}')   { ++s; break; }
    else luaL_error(L, "invalid escape '%c'", ch);
    code *= hex ? 16 : 10;
    code += ch;
  }
  *pch = code;
  return s;
}

static int Lutf8_escape (lua_State *L) {
  const char *e, *s = check_utf8(L, 1, &e);
  luaL_Buffer b;
  luaL_buffinit(L, &b);
  while (s < e) {
    utfint ch = 0;
    s = utf8_safe_decode(L, s, &ch);
    if (ch == '%') {
      int hex = 0;
      switch (*s) {
      case '0': case '1': case '2': case '3':
      case '4': case '5': case '6': case '7':
      case '8': case '9': case '{':
        break;
      case 'x': case 'X': hex = 1; /* fall through */
      case 'u': case 'U': if (s+1 < e) { ++s; break; }
                            /* fall through */
      default:
        s = utf8_safe_decode(L, s, &ch);
        goto next;
      }
      s = parse_escape(L, s, e, hex, &ch);
    }
next:
    add_utf8char(&b, ch);
  }
  luaL_pushresult(&b);
  return 1;
}

static int Lutf8_insert (lua_State *L) {
  const char *e, *s = check_utf8(L, 1, &e);
  size_t sublen;
  const char *subs;
  luaL_Buffer b;
  int nargs = 2;
  const char *first = e;
  if (lua_type(L, 2) == LUA_TNUMBER) {
    int idx = (int)lua_tointeger(L, 2);
    if (idx != 0) first = utf8_relat(s, e, idx);
    luaL_argcheck(L, first, 2, "invalid index");
    ++nargs;
  }
  subs = luaL_checklstring(L, nargs, &sublen);
  luaL_buffinit(L, &b);
  luaL_addlstring(&b, s, first-s);
  luaL_addlstring(&b, subs, sublen);
  luaL_addlstring(&b, first, e-first);
  luaL_pushresult(&b);
  return 1;
}

static int Lutf8_remove (lua_State *L) {
  const char *e, *s = check_utf8(L, 1, &e);
  lua_Integer posi = luaL_optinteger(L, 2, -1);
  lua_Integer pose = luaL_optinteger(L, 3, -1);
  if (!utf8_range(s, e, &posi, &pose))
    lua_settop(L, 1);
  else {
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    luaL_addlstring(&b, s, posi);
    luaL_addlstring(&b, s+pose, e-s-pose);
    luaL_pushresult(&b);
  }
  return 1;
}

static int push_offset (lua_State *L, const char *s, const char *e, lua_Integer offset, lua_Integer idx) {
  utfint ch = 0;
  const char *p;
  if (idx != 0)
    p = utf8_offset(s, e, offset, idx);
  else if (p = s+offset-1, iscont(p))
    p = utf8_prev(s, p);
  if (p == NULL || p == e) return 0;
  utf8_decode(p, &ch, 0);
  lua_pushinteger(L, p-s+1);
  lua_pushinteger(L, ch);
  return 2;
}

static int Lutf8_charpos (lua_State *L) {
  const char *e, *s = check_utf8(L, 1, &e);
  lua_Integer offset = 1;
  if (lua_isnoneornil(L, 3)) {
      lua_Integer idx = luaL_optinteger(L, 2, 0);
      if (idx > 0) --idx;
      else if (idx < 0) offset = e-s+1;
      return push_offset(L, s, e, offset, idx);
  }
  offset = byte_relat(luaL_optinteger(L, 2, 1), e-s);
  if (offset < 1) offset = 1;
  return push_offset(L, s, e, offset, luaL_checkinteger(L, 3));
}

static int Lutf8_offset (lua_State *L) {
  size_t len;
  const char *s = luaL_checklstring(L, 1, &len);
  lua_Integer n  = luaL_checkinteger(L, 2);
  lua_Integer posi = (n >= 0) ? 1 : len + 1;
  posi = byte_relat(luaL_optinteger(L, 3, posi), len);
  luaL_argcheck(L, 1 <= posi && --posi <= (lua_Integer)len, 3,
                   "position out of range");
  if (n == 0) {
    /* find beginning of current byte sequence */
    while (posi > 0 && iscont(s + posi)) posi--;
  } else {
    if (iscont(s + posi))
      return luaL_error(L, "initial position is a continuation byte");
    if (n < 0) {
       while (n < 0 && posi > 0) {  /* move back */
         do {  /* find beginning of previous character */
           posi--;
         } while (posi > 0 && iscont(s + posi));
         n++;
       }
     } else {
       n--;  /* do not move for 1st character */
       while (n > 0 && posi < (lua_Integer)len) {
         do {  /* find beginning of next character */
           posi++;
         } while (iscont(s + posi));  /* (cannot pass final '\0') */
         n--;
       }
     }
  }
  if (n == 0)  /* did it find given character? */
    lua_pushinteger(L, posi + 1);
  else  /* no such character */
    lua_pushnil(L);
  return 1;
}

static int Lutf8_next (lua_State *L) {
  const char *e, *s = check_utf8(L, 1, &e);
  lua_Integer offset = byte_relat(luaL_optinteger(L, 2, 1), e-s);
  lua_Integer idx = luaL_optinteger(L, 3, !lua_isnoneornil(L, 2));
  return push_offset(L, s, e, offset, idx);
}

static int iter_aux (lua_State *L, int strict) {
  const char *e, *s = check_utf8(L, 1, &e);
  int n = CAST(int, lua_tointeger(L, 2));
  const char *p = n <= 0 ? s : utf8_next(s+n-1, e);
  if (p < e) {
    utfint code = 0;
    utf8_safe_decode(L, p, &code);
    if (strict && utf8_invalid(code))
      return luaL_error(L, "invalid UTF-8 code");
    lua_pushinteger(L, p-s+1);
    lua_pushinteger(L, code);
    return 2;
  }
  return 0;  /* no more codepoints */
}

static int iter_auxstrict (lua_State *L) { return iter_aux(L, 1); }
static int iter_auxlax (lua_State *L) { return iter_aux(L, 0); }

static int Lutf8_codes (lua_State *L) {
  int lax = lua_toboolean(L, 2);
  luaL_checkstring(L, 1);
  lua_pushcfunction(L, lax ? iter_auxlax : iter_auxstrict);
  lua_pushvalue(L, 1);
  lua_pushinteger(L, 0);
  return 3;
}

static int Lutf8_width (lua_State *L) {
  int t = lua_type(L, 1);
  int ambi_is_single = !lua_toboolean(L, 2);
  int default_width = CAST(int, luaL_optinteger(L, 3, 0));
  if (t == LUA_TNUMBER) {
    size_t chwidth = utf8_width(CAST(utfint, lua_tointeger(L, 1)), ambi_is_single);
    if (chwidth == 0) chwidth = default_width;
    lua_pushinteger(L, (lua_Integer)chwidth);
  } else if (t != LUA_TSTRING)
    return typeerror(L, 1, "number/string");
  else {
    const char *e, *s = to_utf8(L, 1, &e);
    int width = 0;
    while (s < e) {
      utfint ch = 0;
      int chwidth;
      s = utf8_safe_decode(L, s, &ch);
      chwidth = utf8_width(ch, ambi_is_single);
      width += chwidth == 0 ? default_width : chwidth;
    }
    lua_pushinteger(L, (lua_Integer)width);
  }
  return 1;
}

static int Lutf8_widthindex (lua_State *L) {
  const char *e, *s = check_utf8(L, 1, &e);
  int width = CAST(int, luaL_checkinteger(L, 2));
  int ambi_is_single = !lua_toboolean(L, 3);
  int default_width = CAST(int, luaL_optinteger(L, 4, 0));
  size_t idx = 1;
  while (s < e) {
    utfint ch = 0;
    size_t chwidth;
    s = utf8_safe_decode(L, s, &ch);
    chwidth = utf8_width(ch, ambi_is_single);
    if (chwidth == 0) chwidth = default_width;
    width -= CAST(int, chwidth);
    if (width <= 0) {
      lua_pushinteger(L, idx);
      lua_pushinteger(L, width + chwidth);
      lua_pushinteger(L, chwidth);
      return 3;
    }
    ++idx;
  }
  lua_pushinteger(L, (lua_Integer)idx);
  return 1;
}

static int Lutf8_ncasecmp (lua_State *L) {
  const char *e1, *s1 = check_utf8(L, 1, &e1);
  const char *e2, *s2 = check_utf8(L, 2, &e2);
  while (s1 < e1 || s2 < e2) {
    utfint ch1 = 0, ch2 = 0;
    if (s1 == e1)
      ch2 = 1;
    else if (s2 == e2)
      ch1 = 1;
    else {
      s1 = utf8_safe_decode(L, s1, &ch1);
      s2 = utf8_safe_decode(L, s2, &ch2);
      ch1 = utf8_tofold(ch1);
      ch2 = utf8_tofold(ch2);
    }
    if (ch1 != ch2) {
      lua_pushinteger(L, ch1 > ch2 ? 1 : -1);
      return 1;
    }
  }
  lua_pushinteger(L, 0);
  return 1;
}


/* utf8 pattern matching implement */

#ifndef   LUA_MAXCAPTURES
# define  LUA_MAXCAPTURES  32
#endif /* LUA_MAXCAPTURES */

#define CAP_UNFINISHED (-1)
#define CAP_POSITION   (-2)


typedef struct MatchState {
  int matchdepth;  /* control for recursive depth (to avoid C stack overflow) */
  const char *src_init;  /* init of source string */
  const char *src_end;  /* end ('\0') of source string */
  const char *p_end;  /* end ('\0') of pattern */
  lua_State *L;
  int level;  /* total number of captures (finished or unfinished) */
  struct {
    const char *init;
    ptrdiff_t len;
  } capture[LUA_MAXCAPTURES];
} MatchState;

/* recursive function */
static const char *match (MatchState *ms, const char *s, const char *p);

/* maximum recursion depth for 'match' */
#if !defined(MAXCCALLS)
#define MAXCCALLS       200
#endif

#define L_ESC           '%'
#define SPECIALS        "^$*+?.([%-"

static int check_capture (MatchState *ms, int l) {
  l -= '1';
  if (l < 0 || l >= ms->level || ms->capture[l].len == CAP_UNFINISHED)
    return luaL_error(ms->L, "invalid capture index %%%d", l + 1);
  return l;
}

static int capture_to_close (MatchState *ms) {
  int level = ms->level;
  while (--level >= 0)
    if (ms->capture[level].len == CAP_UNFINISHED) return level;
  return luaL_error(ms->L, "invalid pattern capture");
}

static const char *classend (MatchState *ms, const char *p) {
  utfint ch = 0;
  p = utf8_safe_decode(ms->L, p, &ch);
  switch (ch) {
    case L_ESC: {
      if (p == ms->p_end)
        luaL_error(ms->L, "malformed pattern (ends with " LUA_QL("%%") ")");
      return utf8_next(p, ms->p_end);
    }
    case '[': {
      if (*p == '^') p++;
      do {  /* look for a `]' */
        if (p == ms->p_end)
          luaL_error(ms->L, "malformed pattern (missing " LUA_QL("]") ")");
        if (*(p++) == L_ESC && p < ms->p_end)
          p++;  /* skip escapes (e.g. `%]') */
      } while (*p != ']');
      return p+1;
    }
    default: {
      return p;
    }
  }
}

static int match_class (utfint c, utfint cl) {
  int res;
  switch (utf8_tolower(cl)) {
#define X(cls, name) case cls: res = utf8_is##name(c); break;
    utf8_categories(X)
#undef  X
    case 'g' : res = utf8_isgraph(c); break;
    case 'w' : res = utf8_isalnum(c); break;
    case 'z' : res = (c == 0); break;  /* deprecated option */
    default: return (cl == c);
  }
  return (utf8_islower(cl) ? res : !res);
}

static int matchbracketclass (MatchState *ms, utfint c, const char *p, const char *ec) {
  int sig = 1;
  assert(*p == '[');
  if (*++p == '^') {
    sig = 0;
    p++;  /* skip the `^' */
  }
  while (p < ec) {
    utfint ch = 0;
    p = utf8_safe_decode(ms->L, p, &ch);
    if (ch == L_ESC) {
      p = utf8_safe_decode(ms->L, p, &ch);
      if (match_class(c, ch))
        return sig;
    } else {
      utfint next = 0;
      const char *np = utf8_safe_decode(ms->L, p, &next);
      if (next == '-' && np < ec) {
        p = utf8_safe_decode(ms->L, np, &next);
        if (ch <= c && c <= next)
          return sig;
      }
      else if (ch == c) return sig;
    }
  }
  return !sig;
}

static int singlematch (MatchState *ms, const char *s, const char *p, const char *ep) {
  if (s >= ms->src_end)
    return 0;
  else {
    utfint ch=0, pch=0;
    utf8_safe_decode(ms->L, s, &ch);
    p = utf8_safe_decode(ms->L, p, &pch);
    switch (pch) {
      case '.': return 1;  /* matches any char */
      case L_ESC: utf8_safe_decode(ms->L, p, &pch);
                  return match_class(ch, pch);
      case '[': return matchbracketclass(ms, ch, p-1, ep-1);
      default:  return pch == ch;
    }
  }
}

static const char *matchbalance (MatchState *ms, const char *s, const char **p) {
  utfint ch=0, begin=0, end=0;
  *p = utf8_safe_decode(ms->L, *p, &begin);
  if (*p >= ms->p_end)
    luaL_error(ms->L, "malformed pattern "
                      "(missing arguments to " LUA_QL("%%b") ")");
  *p = utf8_safe_decode(ms->L, *p, &end);
  s = utf8_safe_decode(ms->L, s, &ch);
  if (ch != begin) return NULL;
  else {
    int cont = 1;
    while (s < ms->src_end) {
      s = utf8_safe_decode(ms->L, s, &ch);
      if (ch == end) {
        if (--cont == 0) return s;
      }
      else if (ch == begin) cont++;
    }
  }
  return NULL;  /* string ends out of balance */
}

static const char *max_expand (MatchState *ms, const char *s, const char *p, const char *ep) {
  const char *m = s; /* matched end of single match p */
  while (singlematch(ms, m, p, ep))
    m = utf8_next(m, ms->src_end);
  /* keeps trying to match with the maximum repetitions */
  while (s <= m) {
    const char *res = match(ms, m, ep+1);
    if (res) return res;
    /* else didn't match; reduce 1 repetition to try again */
    if (s == m) break;
    m = utf8_prev(s, m);
  }
  return NULL;
}

static const char *min_expand (MatchState *ms, const char *s, const char *p, const char *ep) {
  for (;;) {
    const char *res = match(ms, s, ep+1);
    if (res != NULL)
      return res;
    else if (singlematch(ms, s, p, ep))
      s = utf8_next(s, ms->src_end);  /* try with one more repetition */
    else return NULL;
  }
}

static const char *start_capture (MatchState *ms, const char *s, const char *p, int what) {
  const char *res;
  int level = ms->level;
  if (level >= LUA_MAXCAPTURES) luaL_error(ms->L, "too many captures");
  ms->capture[level].init = s;
  ms->capture[level].len = what;
  ms->level = level+1;
  if ((res=match(ms, s, p)) == NULL)  /* match failed? */
    ms->level--;  /* undo capture */
  return res;
}

static const char *end_capture (MatchState *ms, const char *s, const char *p) {
  int l = capture_to_close(ms);
  const char *res;
  ms->capture[l].len = s - ms->capture[l].init;  /* close capture */
  if ((res = match(ms, s, p)) == NULL)  /* match failed? */
    ms->capture[l].len = CAP_UNFINISHED;  /* undo capture */
  return res;
}

static const char *match_capture (MatchState *ms, const char *s, int l) {
  size_t len;
  l = check_capture(ms, l);
  len = ms->capture[l].len;
  if ((size_t)(ms->src_end-s) >= len &&
      memcmp(ms->capture[l].init, s, len) == 0)
    return s+len;
  else return NULL;
}

static const char *match (MatchState *ms, const char *s, const char *p) {
  if (ms->matchdepth-- == 0)
    luaL_error(ms->L, "pattern too complex");
  init: /* using goto's to optimize tail recursion */
  if (p != ms->p_end) {  /* end of pattern? */
    utfint ch = 0;
    utf8_safe_decode(ms->L, p, &ch);
    switch (ch) {
      case '(': {  /* start capture */
        if (*(p + 1) == ')')  /* position capture? */
          s = start_capture(ms, s, p + 2, CAP_POSITION);
        else
          s = start_capture(ms, s, p + 1, CAP_UNFINISHED);
        break;
      }
      case ')': {  /* end capture */
        s = end_capture(ms, s, p + 1);
        break;
      }
      case '$': {
        if ((p + 1) != ms->p_end)  /* is the `$' the last char in pattern? */
          goto dflt;  /* no; go to default */
        s = (s == ms->src_end) ? s : NULL;  /* check end of string */
        break;
      }
      case L_ESC: {  /* escaped sequence not in the format class[*+?-]? */
        const char *prev_p = p;
        p = utf8_safe_decode(ms->L, p+1, &ch);
        switch (ch) {
          case 'b': {  /* balanced string? */
            s = matchbalance(ms, s, &p);
            if (s != NULL)
              goto init;  /* return match(ms, s, p + 4); */
            /* else fail (s == NULL) */
            break;
          }
          case 'f': {  /* frontier? */
            const char *ep; utfint previous = 0, current = 0;
            if (*p != '[')
              luaL_error(ms->L, "missing " LUA_QL("[") " after "
                                 LUA_QL("%%f") " in pattern");
            ep = classend(ms, p);  /* points to what is next */
            if (s != ms->src_init)
              utf8_decode(utf8_prev(ms->src_init, s), &previous, 0);
            if (s != ms->src_end)
              utf8_decode(s, &current, 0);
            if (!matchbracketclass(ms, previous, p, ep - 1) &&
                 matchbracketclass(ms, current, p, ep - 1)) {
              p = ep; goto init;  /* return match(ms, s, ep); */
            }
            s = NULL;  /* match failed */
            break;
          }
          case '0': case '1': case '2': case '3':
          case '4': case '5': case '6': case '7':
          case '8': case '9': {  /* capture results (%0-%9)? */
            s = match_capture(ms, s, ch);
            if (s != NULL) goto init;  /* return match(ms, s, p + 2) */
            break;
          }
          default: p = prev_p; goto dflt;
        }
        break;
      }
      default: dflt: {  /* pattern class plus optional suffix */
        const char *ep = classend(ms, p);  /* points to optional suffix */
        /* does not match at least once? */
        if (!singlematch(ms, s, p, ep)) {
          if (*ep == '*' || *ep == '?' || *ep == '-') {  /* accept empty? */
            p = ep + 1; goto init;  /* return match(ms, s, ep + 1); */
          } else  /* '+' or no suffix */
            s = NULL;  /* fail */
        } else {  /* matched once */
          const char *next_s = utf8_next(s, ms->src_end);
          switch (*ep) {  /* handle optional suffix */
            case '?': {  /* optional */
              const char *res;
              const char *next_ep = utf8_next(ep, ms->p_end);
              if ((res = match(ms, next_s, next_ep)) != NULL)
                s = res;
              else {
                p = next_ep; goto init;  /* else return match(ms, s, ep + 1); */
              }
              break;
            }
            case '+':  /* 1 or more repetitions */
              s = next_s;  /* 1 match already done */
              /* fall through */
            case '*':  /* 0 or more repetitions */
              s = max_expand(ms, s, p, ep);
              break;
            case '-':  /* 0 or more repetitions (minimum) */
              s = min_expand(ms, s, p, ep);
              break;
            default:  /* no suffix */
              s = next_s; p = ep; goto init;  /* return match(ms, s + 1, ep); */
          }
        }
        break;
      }
    }
  }
  ms->matchdepth++;
  return s;
}

static const char *lmemfind (const char *s1, size_t l1, const char *s2, size_t l2) {
  if (l2 == 0) return s1;  /* empty strings are everywhere */
  else if (l2 > l1) return NULL;  /* avoids a negative `l1' */
  else {
    const char *init;  /* to search for a `*s2' inside `s1' */
    l2--;  /* 1st char will be checked by `memchr' */
    l1 = l1-l2;  /* `s2' cannot be found after that */
    while (l1 > 0 && (init = (const char *)memchr(s1, *s2, l1)) != NULL) {
      init++;   /* 1st char is already checked */
      if (memcmp(init, s2+1, l2) == 0)
        return init-1;
      else {  /* correct `l1' and `s1' to try again */
        l1 -= init-s1;
        s1 = init;
      }
    }
    return NULL;  /* not found */
  }
}

static int get_index (const char *p, const char *s, const char *e) {
    int idx;
    for (idx = 0; s < e && s < p; ++idx)
        s = utf8_next(s, e);
    return s == p ? idx : idx - 1;
}

static void push_onecapture (MatchState *ms, int i, const char *s, const char *e) {
  if (i >= ms->level) {
    if (i == 0)  /* ms->level == 0, too */
      lua_pushlstring(ms->L, s, e - s);  /* add whole match */
    else
      luaL_error(ms->L, "invalid capture index");
  } else {
    ptrdiff_t l = ms->capture[i].len;
    if (l == CAP_UNFINISHED) luaL_error(ms->L, "unfinished capture");
    if (l == CAP_POSITION) {
      int idx = get_index(ms->capture[i].init, ms->src_init, ms->src_end);
      lua_pushinteger(ms->L, idx+1);
    } else
      lua_pushlstring(ms->L, ms->capture[i].init, l);
  }
}

static int push_captures (MatchState *ms, const char *s, const char *e) {
  int i;
  int nlevels = (ms->level == 0 && s) ? 1 : ms->level;
  luaL_checkstack(ms->L, nlevels, "too many captures");
  for (i = 0; i < nlevels; i++)
    push_onecapture(ms, i, s, e);
  return nlevels;  /* number of strings pushed */
}

/* check whether pattern has no special characters */
static int nospecials (const char *p, const char * ep) {
  while (p < ep) {
    if (strpbrk(p, SPECIALS))
      return 0;  /* pattern has a special character */
    p += strlen(p) + 1;  /* may have more after \0 */
  }
  return 1;  /* no special chars found */
}


/* utf8 pattern matching interface */

static int find_aux (lua_State *L, int find) {
  const char *es, *s = check_utf8(L, 1, &es);
  const char *ep, *p = check_utf8(L, 2, &ep);
  lua_Integer idx = luaL_optinteger(L, 3, 1);
  const char *init;
  if (!idx) idx = 1;
  init = utf8_relat(s, es, CAST(int, idx));
  if (init == NULL) {
    if (idx > 0) {
      lua_pushnil(L);  /* cannot find anything */
      return 1;
    }
    init = s;
  }
  /* explicit request or no special characters? */
  if (find && (lua_toboolean(L, 4) || nospecials(p, ep))) {
    /* do a plain search */
    const char *s2 = lmemfind(init, es-init, p, ep-p);
    if (s2) {
      const char *e2 = s2 + (ep - p);
      if (iscont(e2)) e2 = utf8_next(e2, es);
      lua_pushinteger(L, idx = get_index(s2, s, es) + 1);
      lua_pushinteger(L, idx + get_index(e2, s2, es) - 1);
      return 2;
    }
  } else {
    MatchState ms;
    int anchor = (*p == '^');
    if (anchor) p++;  /* skip anchor character */
    if (idx < 0) idx += utf8_length(s, es)+1; /* TODO not very good */
    ms.L = L;
    ms.matchdepth = MAXCCALLS;
    ms.src_init = s;
    ms.src_end = es;
    ms.p_end = ep;
    do {
      const char *res;
      ms.level = 0;
      assert(ms.matchdepth == MAXCCALLS);
      if ((res=match(&ms, init, p)) != NULL) {
        if (find) {
          lua_pushinteger(L, idx);  /* start */
          lua_pushinteger(L, idx + utf8_length(init, res) - 1);   /* end */
          return push_captures(&ms, NULL, 0) + 2;
        } else
          return push_captures(&ms, init, res);
      }
      if (init == es) break;
      idx += 1;
      init = utf8_next(init, es);
    } while (init <= es && !anchor);
  }
  lua_pushnil(L);  /* not found */
  return 1;
}

static int Lutf8_find (lua_State *L) { return find_aux(L, 1); }
static int Lutf8_match (lua_State *L) { return find_aux(L, 0); }

static int gmatch_aux (lua_State *L) {
  MatchState ms;
  const char *es, *s = check_utf8(L, lua_upvalueindex(1), &es);
  const char *ep, *p = check_utf8(L, lua_upvalueindex(2), &ep);
  const char *src;
  ms.L = L;
  ms.matchdepth = MAXCCALLS;
  ms.src_init = s;
  ms.src_end = es;
  ms.p_end = ep;
  for (src = s + (size_t)lua_tointeger(L, lua_upvalueindex(3));
       src <= ms.src_end;
       src = utf8_next(src, ms.src_end)) {
    const char *e;
    ms.level = 0;
    assert(ms.matchdepth == MAXCCALLS);
    if ((e = match(&ms, src, p)) != NULL) {
      lua_Integer newstart = e-s;
      if (e == src) newstart++;  /* empty match? go at least one position */
      lua_pushinteger(L, newstart);
      lua_replace(L, lua_upvalueindex(3));
      return push_captures(&ms, src, e);
    }
    if (src == ms.src_end) break;
  }
  return 0;  /* not found */
}

static int Lutf8_gmatch (lua_State *L) {
  luaL_checkstring(L, 1);
  luaL_checkstring(L, 2);
  lua_settop(L, 2);
  lua_pushinteger(L, 0);
  lua_pushcclosure(L, gmatch_aux, 3);
  return 1;
}

static void add_s (MatchState *ms, luaL_Buffer *b, const char *s, const char *e) {
  const char *new_end, *news = to_utf8(ms->L, 3, &new_end);
  while (news < new_end) {
    utfint ch = 0;
    news = utf8_safe_decode(ms->L, news, &ch);
    if (ch != L_ESC)
      add_utf8char(b, ch);
    else {
      news = utf8_safe_decode(ms->L, news, &ch); /* skip ESC */
      if (!utf8_isdigit(ch)) {
        if (ch != L_ESC)
          luaL_error(ms->L, "invalid use of " LUA_QL("%c")
              " in replacement string", L_ESC);
        add_utf8char(b, ch);
      } else if (ch == '0')
        luaL_addlstring(b, s, e-s);
      else {
        push_onecapture(ms, ch-'1', s, e);
        luaL_addvalue(b);  /* add capture to accumulated result */
      }
    }
  }
}

static void add_value (MatchState *ms, luaL_Buffer *b, const char *s, const char *e, int tr) {
  lua_State *L = ms->L;
  switch (tr) {
    case LUA_TFUNCTION: {
      int n;
      lua_pushvalue(L, 3);
      n = push_captures(ms, s, e);
      lua_call(L, n, 1);
      break;
    }
    case LUA_TTABLE: {
      push_onecapture(ms, 0, s, e);
      lua_gettable(L, 3);
      break;
    }
    default: {  /* LUA_TNUMBER or LUA_TSTRING */
      add_s(ms, b, s, e);
      return;
    }
  }
  if (!lua_toboolean(L, -1)) {  /* nil or false? */
    lua_pop(L, 1);
    lua_pushlstring(L, s, e - s);  /* keep original text */
  } else if (!lua_isstring(L, -1))
    luaL_error(L, "invalid replacement value (a %s)", luaL_typename(L, -1));
  luaL_addvalue(b);  /* add result to accumulator */
}

static int Lutf8_gsub (lua_State *L) {
  const char *es, *s = check_utf8(L, 1, &es);
  const char *ep, *p = check_utf8(L, 2, &ep);
  int tr = lua_type(L, 3);
  lua_Integer max_s = luaL_optinteger(L, 4, (es-s)+1);
  int anchor = (*p == '^');
  lua_Integer n = 0;
  MatchState ms;
  luaL_Buffer b;
  luaL_argcheck(L, tr == LUA_TNUMBER || tr == LUA_TSTRING ||
                   tr == LUA_TFUNCTION || tr == LUA_TTABLE, 3,
                      "string/function/table expected");
  luaL_buffinit(L, &b);
  if (anchor) p++;  /* skip anchor character */
  ms.L = L;
  ms.matchdepth = MAXCCALLS;
  ms.src_init = s;
  ms.src_end = es;
  ms.p_end = ep;
  while (n < max_s) {
    const char *e;
    ms.level = 0;
    assert(ms.matchdepth == MAXCCALLS);
    e = match(&ms, s, p);
    if (e) {
      n++;
      add_value(&ms, &b, s, e, tr);
    }
    if (e && e > s) /* non empty match? */
      s = e;  /* skip it */
    else if (s < es) {
      utfint ch = 0;
      s = utf8_safe_decode(L, s, &ch);
      add_utf8char(&b, ch);
    } else break;
    if (anchor) break;
  }
  luaL_addlstring(&b, s, es-s);
  luaL_pushresult(&b);
  lua_pushinteger(L, n);  /* number of substitutions */
  return 2;
}


/* lua module import interface */

#if LUA_VERSION_NUM >= 502
static const char UTF8PATT[] = "[\0-\x7F\xC2-\xF4][\x80-\xBF]*";
#else
static const char UTF8PATT[] = "[%z\1-\x7F\xC2-\xF4][\x80-\xBF]*";
#endif

int luaopen_utf8extra (lua_State *L) {
  luaL_Reg libs[] = {
#define ENTRY(name) { #name, Lutf8_##name }
    ENTRY(offset),
    ENTRY(codes),
    ENTRY(codepoint),

    ENTRY(len),
    ENTRY(sub),
    ENTRY(reverse),
    ENTRY(lower),
    ENTRY(upper),
    ENTRY(title),
    ENTRY(fold),
    ENTRY(byte),
    ENTRY(char),
    ENTRY(escape),
    ENTRY(insert),
    ENTRY(remove),
    ENTRY(charpos),
    ENTRY(next),
    ENTRY(width),
    ENTRY(widthindex),
    ENTRY(ncasecmp),
    ENTRY(find),
    ENTRY(gmatch),
    ENTRY(gsub),
    ENTRY(match),
#undef  ENTRY
    { NULL, NULL }
  };

  luaL_newlib(L, libs);

  lua_pushlstring(L, UTF8PATT, sizeof(UTF8PATT)-1);
  lua_setfield(L, -2, "charpattern");

  return 1;
}
