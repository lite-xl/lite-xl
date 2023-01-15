#include <SDL.h>
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <errno.h>
#include <stdbool.h>
#include <uchardet.h>

#ifdef _WIN32
  #include <windows.h>
#endif

typedef struct {
  const char* charset;
  unsigned char bom[4];
  int len;
} bom_t;

/*
 * List of encodings that can have byte order marks.
 * Note: UTF-32 should be tested before UTF-16, the order matters.
*/
static bom_t bom_list[] = {
  { "UTF-8",    {0xef, 0xbb, 0xbf},       3 },
  { "UTF-32LE", {0xff, 0xfe, 0x00, 0x00}, 4 },
  { "UTF-32BE", {0x00, 0x00, 0xfe, 0xff}, 4 },
  { "UTF-16LE", {0xff, 0xfe},             2 },
  { "UTF-16BE", {0xfe, 0xff},             2 },
  { "GB18030",  {0x84, 0x31, 0x95, 0x33}, 4 },
  { "UTF-7",    {0x2b, 0x2f, 0x76, 0x38}, 4 },
  { "UTF-7",    {0x2b, 0x2f, 0x76, 0x39}, 4 },
  { "UTF-7",    {0x2b, 0x2f, 0x76, 0x2b}, 4 },
  { "UTF-7",    {0x2b, 0x2f, 0x76, 0x2f}, 4 },
  { NULL }
};

/*
 * NOTE:
 * Newer uchardet currently has some issues properly detecting some instances of
 * UTF-8 as seen on https://gitlab.freedesktop.org/uchardet/uchardet/-/issues.
 * REF: https://github.com/notepad-plus-plus/notepad-plus-plus/issues/5310
 *
 * For this reason, we included a third party MIT function to check if a string
 * is valid utf8 and prefer this result over the one from uchardet.
*/
/*************************UTF-8 Validation Code********************************/
/* Found on: https://stackoverflow.com/a/22135005                             */
/* Copyright (c) 2008-2009 Bjoern Hoehrmann <bjoern@hoehrmann.de>             */
/* See http://bjoern.hoehrmann.de/utf-8/decoder/dfa/ for details.             */
#define UTF8_ACCEPT 0
#define UTF8_REJECT 1

static const uint8_t utf8d[] = {
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 00..1f
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 20..3f
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 40..5f
  0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, // 60..7f
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, // 80..9f
  7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, // a0..bf
  8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, // c0..df
  0xa,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x4,0x3,0x3, // e0..ef
  0xb,0x6,0x6,0x6,0x5,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8, // f0..ff
  0x0,0x1,0x2,0x3,0x5,0x8,0x7,0x1,0x1,0x1,0x4,0x6,0x1,0x1,0x1,0x1, // s0..s0
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,0,1,0,1,1,1,1,1,1, // s1..s2
  1,2,1,1,1,1,1,2,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1, // s3..s4
  1,2,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,3,1,3,1,1,1,1,1,1, // s5..s6
  1,3,1,1,1,1,1,3,1,3,1,1,1,1,1,1,1,3,1,1,1,1,1,1,1,1,1,1,1,1,1,1, // s7..s8
};

uint32_t utf8_validate(uint32_t *state, const char *str, size_t len) {
   size_t i;
   uint32_t type;

    for (i = 0; i < len; i++) {
        // We don't care about the codepoint, so this is
        // a simplified version of the decode function.
        type = utf8d[(uint8_t)str[i]];
        *state = utf8d[256 + (*state) * 16 + type];

        if (*state == UTF8_REJECT)
            break;
    }

    return *state;
}
/*************************End of UTF-8 Validation Code*************************/


/*
 * The default SDL_iconv_string allows broken conversions so we need
 * a more stricter replacement. Also there is no easy way to know the len
 * of the returned output without inspecting a sequence of \0 which is
 * slower than returning it in the bytes_written parameter.
 *
 * Adapted from: SDL/src/stdlib/SDL_iconv.c
 */
char* SDL_iconv_string_custom(
  const char *tocode, const char *fromcode, const char *inbuf,
  size_t inbytesleft, size_t* bytes_written, bool strict
) {
  SDL_iconv_t cd;
  char *string;
  size_t stringsize;
  char *outbuf;
  size_t outbytesleft;
  size_t retCode = 0;

  cd = SDL_iconv_open(tocode, fromcode);
  if (cd == (SDL_iconv_t) - 1) {
    return NULL;
  }

  stringsize = inbytesleft > 4 ? inbytesleft : 4;
  string = (char *) SDL_malloc(stringsize);
  if (!string) {
      SDL_iconv_close(cd);
      return NULL;
  }
  outbuf = string;
  outbytesleft = stringsize;
  SDL_memset(outbuf, 0, 4);

  bool has_error = false;
  while (inbytesleft > 0 && !has_error) {
    const size_t oldinbytesleft = inbytesleft;
    retCode = SDL_iconv(cd, &inbuf, &inbytesleft, &outbuf, &outbytesleft);
    switch (retCode) {
    case SDL_ICONV_E2BIG:
      {
        char *oldstring = string;
        stringsize *= 2;
        string = (char *) SDL_realloc(string, stringsize);
        if (!string) {
          SDL_free(oldstring);
          SDL_iconv_close(cd);
          return NULL;
        }
        outbuf = string + (outbuf - oldstring);
        outbytesleft = stringsize - (outbuf - string);
        SDL_memset(outbuf, 0, 4);
      }
      break;
    case SDL_ICONV_EILSEQ:
      /* Try skipping some input data - not perfect, but... */
      if (!strict) {
        ++inbuf;
        --inbytesleft;
      } else {
        has_error = true;
      }
      break;
    case SDL_ICONV_EINVAL:
    case SDL_ICONV_ERROR:
      /* We can't continue... */
      if (!strict)
        inbytesleft = 0;
      else
        has_error = true;
      break;
    }
    /* Avoid infinite loops when nothing gets converted */
    if (!strict && oldinbytesleft == inbytesleft) {
        break;
    }
  }
  SDL_iconv_close(cd);

  if (bytes_written)
    *bytes_written = outbuf - string;

  if (has_error) {
    SDL_free(string);
    return NULL;
  }

  return string;
}


/* Get the applicable byte order marks for the given charset */
static const unsigned char* encoding_bom_from_charset(const char* charset, size_t* len) {
  for (size_t i=0; bom_list[i].charset != NULL; i++){
    if (strcmp(bom_list[i].charset, charset) == 0) {
      if (len) *len = bom_list[i].len;
      return bom_list[i].bom;
    }
  }

  if (len) *len = 0;

  return NULL;
}


/* Detect the encoding of the given string if a valid bom sequence is found */
static const char* encoding_charset_from_bom(
  const char* string, size_t len, size_t* bom_len
) {
  const unsigned char* bytes = (unsigned char*) string;

  for (size_t i=0; bom_list[i].charset != NULL; i++) {
    if (len >= bom_list[i].len) {
      bool all_match = true;
      for (size_t b = 0; b<bom_list[i].len; b++) {
        if (bytes[b] != bom_list[i].bom[b]) {
          all_match = false;
          break;
        }
      }
      if (all_match) {
        if (bom_len) *bom_len = bom_list[i].len;
        return bom_list[i].charset;
      }
    }
  }

  if (bom_len)
      *bom_len = 0;

  return NULL;
}


/* Detects the encoding of a string. */
const char* encoding_detect(const char* string, size_t string_len) {
  static char charset[30];

  if (string_len == 0) {
		return "UTF-8";
  }

  memset(charset, 0, 30);

  size_t bom_len = 0;
  const char* bom_charset = encoding_charset_from_bom(
    string, string_len, &bom_len
  );

  uint32_t state = UTF8_ACCEPT;
  bool valid_utf8 = true;
  uchardet_t handle = uchardet_new();

	int retval = uchardet_handle_data(handle, string, string_len);
	if (retval == 0) {
    uchardet_data_end(handle);
    const char* ucharset = uchardet_get_charset(handle);
    strcpy(charset, ucharset);
	}
	uchardet_delete(handle);

	if(utf8_validate(&state, string, string_len) == UTF8_REJECT) {
		valid_utf8 = false;
	}

  state = UTF8_ACCEPT;
  char* utf8_output = NULL;
  size_t utf8_len = 0;
  if (
    bom_charset
    &&
    (
      (utf8_output = SDL_iconv_string_custom(
        "UTF-8", bom_charset,
        string+bom_len, string_len-bom_len,
        &utf8_len, true
      )) != NULL
      &&
      utf8_validate(&state, utf8_output, utf8_len) != UTF8_REJECT
    )
  ) {
    SDL_free(utf8_output);
    return bom_charset;
  }

  if (utf8_output)
    SDL_free(utf8_output);

  if (valid_utf8) {
    return "UTF-8";
  } else if (*charset) {
    return charset;
  }

  return NULL;
}


/*
 * encoding.detect(filename)
 *
 * Try to detect the best encoding for the given file.
 *
 * Arguments:
 *  filename, the filename to check
 *
 * Returns:
 *  The charset string or nil
 *  The error message
 */
int f_detect(lua_State *L) {
  const char* file_name = luaL_checkstring(L, 1);

#ifndef _WIN32
  FILE* file = fopen(file_name, "rb");
#else
  wchar_t utf16[1024];
  memset(utf16, 0, sizeof(utf16));
  MultiByteToWideChar(CP_UTF8, 0, file_name, strlen(file_name), utf16, 1024);
  FILE* file = _wfopen(utf16, L"rb");
#endif

  if (!file) {
    lua_pushnil(L);
    lua_pushfstring(L, "unable to open file '%s', code=%d", file_name, errno);
    return 2;
  }

  fseek(file, 0, SEEK_END);

  size_t file_size = ftell(file);
  char* string = malloc(file_size);

  if (!string) {
    lua_pushnil(L);
		lua_pushfstring(L, "out of ram while detecting charset of '%s'", file_name);
		fclose(file);
		return 2;
  }

  fseek(file, 0, SEEK_SET);
  fread(string, 1, file_size, file);

  const char* charset = encoding_detect(string, file_size);

  fclose(file);
  free(string);

  if (charset) {
    lua_pushstring(L, charset);
  } else {
    lua_pushnil(L);
		lua_pushstring(L, "could not detect the file encoding");
		return 2;
  }

  return 1;
}


/*
 * encoding.detect_string(filename)
 *
 * Same as encoding.detect() but for a string.
 *
 * Arguments:
 *  string, the string to check
 *
 * Returns:
 *  The charset string or nil
 *  The error message
 */
int f_detect_string(lua_State *L) {
	size_t string_len = 0;
  const char* string = luaL_checklstring(L, 1, &string_len);

  const char* charset = encoding_detect(string, string_len);

  if (charset) {
    lua_pushstring(L, charset);
  } else {
    lua_pushnil(L);
		lua_pushstring(L, "could not detect the file encoding");
		return 2;
  }

  return 1;
}


/*
 * encoding.convert(tocharset, fromcharset, text, options)
 *
 * Convert the given text from one charset into another if possible.
 *
 * Arguments:
 *  tocharset, a string representing a valid iconv charset
 *  fromcharset, a string representing a valid iconv charset
 *  text, the string to convert
 *  options, a table of conversion options
 *
 * Returns:
 *  The converted ouput string or nil
 *  The error message
 */
int f_convert(lua_State *L) {
  const char* to = luaL_checkstring(L, 1);
  const char* from = luaL_checkstring(L, 2);
  size_t text_len = 0;
  const char* text = luaL_checklstring(L, 3, &text_len);
  /* conversion options */
  bool strict = false;
  bool handle_to_bom = false;
  bool handle_from_bom = false;
  const unsigned char* bom;
  size_t bom_len = 0;

  if (lua_gettop(L) > 3 && lua_istable(L, 4)) {
    lua_getfield(L, 4, "handle_to_bom");
    if (lua_isboolean(L, -1)) {
      handle_to_bom = lua_toboolean(L, -1);
    }
    lua_getfield(L, 4, "handle_from_bom");
    if (lua_isboolean(L, -1)) {
      handle_from_bom = lua_toboolean(L, -1);
    }
    lua_getfield(L, 4, "strict");
    if (lua_isboolean(L, -1)) {
      strict = lua_toboolean(L, -1);
    }
  }

  /* to strip the bom from the input text if any */
  if (handle_from_bom) {
    encoding_charset_from_bom(text, text_len, &bom_len);
  }

  size_t output_len = 0;
  char* output = SDL_iconv_string_custom(
    to, from, text+bom_len, text_len-bom_len, &output_len, strict
  );

  /* strip bom sometimes added when converting to utf-8, we don't need it */
  if (output && strcmp(to, "UTF-8") == 0) {
    encoding_charset_from_bom(output, output_len, &bom_len);
    if (bom_len > 0) {
      SDL_memmove(output,output+bom_len, output_len-bom_len);
      output = SDL_realloc(output, output_len-bom_len);
      output_len -= bom_len;
    }
  }

  if (output != NULL && handle_to_bom) {
    if (handle_to_bom) {
      bom = encoding_bom_from_charset(to, &bom_len);
      if (bom != NULL) {
        output = SDL_realloc(output, output_len + bom_len);
        SDL_memmove(output+bom_len, output, output_len);
        SDL_memcpy(output, bom, bom_len);
        output_len += bom_len;
      }
    }
  } else if (!output) {
    lua_pushnil(L);
    lua_pushfstring(L, "failed converting from '%s' to '%s'", from, to);
    return 2;
  }

  lua_pushlstring(L, output, output_len);

  SDL_free(output);

  return 1;
}


/*
 * encoding.get_charset_bom(charset)
 *
 * Retrieve the byte order marks sequence for the given charset if applicable.
 *
 * Arguments:
 *  charset, a string representing a valid iconv charset
 *
 * Returns:
 *  The bom sequence string or empty string if not applicable.
 */
int f_get_charset_bom(lua_State *L) {
  const char* charset = luaL_checkstring(L, 1);

  size_t bom_len = 0;
  const unsigned char* bom = encoding_bom_from_charset(charset, &bom_len);

  if (bom)
    lua_pushlstring(L, (char*)bom, bom_len);
  else
    lua_pushstring(L, "");

  return 1;
}


/*
 * encoding.strip_bom(text, charset)
 *
 * Remove the byte order marks from the given string.
 *
 * Arguments:
 *  text, a string that may contain a byte order marks to be removed.
 *  charset, optional charset to scan for, if empty scan all charsets with bom.
 *
 * Returns:
 *  The input text string with the byte order marks removed if found.
 */
int f_strip_bom(lua_State* L) {
  size_t text_len = 0;
  const char* text = luaL_checklstring(L, 1, &text_len);
  const char* charset = luaL_optstring(L, 2, NULL);
  size_t bom_len = 0;

  if (text_len <= 0) {
    lua_pushstring(L, "");
  } else {
    if (charset) {
      for (size_t i=0; bom_list[i].charset != NULL; i++) {
        if (
          strcmp(bom_list[i].charset, charset) == 0
          &&
          text_len >= bom_list[i].len
        ) {
          bool bom_found = true;
          for (size_t b=0; b<bom_list[i].len; b++) {
            if (bom_list[i].bom[b] != (unsigned char)text[b]) {
              bom_found = false;
              break;
            }
          }
          if (bom_found) {
            bom_len = bom_list[i].len;
            break;
          }
        }
      }
    } else {
      encoding_charset_from_bom(text, text_len, &bom_len);
    }
  }

  if (bom_len > 0 && text_len-bom_len > 0) {
    lua_pushlstring(L, text+bom_len, text_len-bom_len);
  } else {
    lua_pushlstring(L, text, text_len);
  }

  return 1;
}


static const luaL_Reg lib[] = {
  { "detect",          f_detect          },
  { "detect_string",   f_detect_string   },
  { "convert",         f_convert         },
  { "get_charset_bom", f_get_charset_bom },
  { "strip_bom",       f_strip_bom       },
  { NULL, NULL }
};


int luaopen_encoding(lua_State *L) {
  luaL_newlib(L, lib);
  return 1;
}
