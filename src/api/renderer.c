#include <string.h>
#include <assert.h>
#include "api.h"
#include "../renderer.h"
#include "../rencache.h"
#ifdef LITE_USE_SDL_RENDERER
#include "../renwindow.h"
#endif
#include "lua.h"

RenWindow *active_window_renderer = NULL;

// a reference index to a table that stores the fonts
static int RENDERER_FONT_REF = LUA_NOREF;

unsigned char default_features[][4] = {
  { 'r', 'v', 'r', 'n' },
  { 'c', 'c', 'm', 'p' },
  { 'r', 'l', 'i', 'g' },
  { ' ', 'R', 'Q', 'D' },
};

unsigned char default_ligature_features[][4] = {
  { 'c', 'a', 'l', 't' },
  { 'l', 'i', 'g', 'a' },
  { 'c', 'l', 'i', 'g' },
  { 'd', 'l', 'i', 'g' },
};

#define n_default_features (sizeof(default_features) / sizeof(default_features[0]))
#define n_default_ligature_features (sizeof(default_ligature_features) / sizeof(default_ligature_features[0]))

static size_t get_table_size(lua_State *L, int index) {
  if (index < 0)
    index = lua_gettop(L) + index + 1;
  size_t counter = 0;
  lua_pushnil(L);
  while (lua_next(L, index) != 0) {
    counter++;
    lua_pop(L, 1); // pop value
  }
  return counter;
}

static int font_get_options(
  lua_State *L,
  ERenFontAntialiasing *antialiasing,
  ERenFontHinting *hinting,
  int *style,
  RenFontLigatureOptions *liga_options
) {


  if (lua_gettop(L) > 2 && lua_istable(L, 3)) {
    lua_getfield(L, 3, "antialiasing");
    if (lua_isstring(L, -1)) {
      const char *antialiasing_str = lua_tostring(L, -1);
      if (antialiasing_str) {
        if (strcmp(antialiasing_str, "none") == 0) {
          *antialiasing = FONT_ANTIALIASING_NONE;
        } else if (strcmp(antialiasing_str, "grayscale") == 0) {
          *antialiasing = FONT_ANTIALIASING_GRAYSCALE;
        } else if (strcmp(antialiasing_str, "subpixel") == 0) {
          *antialiasing = FONT_ANTIALIASING_SUBPIXEL;
        } else {
          return luaL_error(
            L,
            "error in font options, unknown antialiasing option: \"%s\"",
            antialiasing_str
          );
        }
      }
    }
    lua_getfield(L, 3, "hinting");
    if (lua_isstring(L, -1)) {
      const char *hinting_str = lua_tostring(L, -1);
      if (hinting_str) {
        if (strcmp(hinting_str, "slight") == 0) {
          *hinting = FONT_HINTING_SLIGHT;
        } else if (strcmp(hinting_str, "none") == 0) {
          *hinting = FONT_HINTING_NONE;
        } else if (strcmp(hinting_str, "full") == 0) {
          *hinting = FONT_HINTING_FULL;
        } else {
          return luaL_error(
            L,
            "error in font options, unknown hinting option: \"%s\"",
            hinting
          );
        }
      }
    }
    int style_local = 0;
    lua_getfield(L, 3, "italic");
    if (lua_toboolean(L, -1))
      style_local |= FONT_STYLE_ITALIC;
    lua_getfield(L, 3, "bold");
    if (lua_toboolean(L, -1))
      style_local |= FONT_STYLE_BOLD;
    lua_getfield(L, 3, "underline");
    if (lua_toboolean(L, -1))
      style_local |= FONT_STYLE_UNDERLINE;
    lua_getfield(L, 3, "smoothing");
    if (lua_toboolean(L, -1))
      style_local |= FONT_STYLE_SMOOTH;
    lua_getfield(L, 3, "strikethrough");
    if (lua_toboolean(L, -1))
      style_local |= FONT_STYLE_STRIKETHROUGH;

    lua_getfield(L, 3, "ligatures");
    if (lua_istable(L, -1)) {
      liga_options->n_features = 0;
      size_t n_features = n_default_features + n_default_ligature_features + get_table_size(L, -1);
      liga_options->features = calloc(n_features, sizeof(unsigned char [4]));
      // Handle default features
      for (size_t i = 0; i < n_default_features; i++) {
        char tagstr[5];
        memcpy(tagstr, default_features[i], sizeof(unsigned char [4]));
        tagstr[4] = '\0';
        lua_getfield(L, -1, tagstr);
        if (lua_isnoneornil(L, -1)) { // The tag isn't explicitly set/unset, so include it
          memcpy(&liga_options->features[liga_options->n_features++], default_features[i], sizeof(unsigned char [4]));
        }
        lua_pop(L, 1);
      }
      // Handle default ligature features
      for (size_t i = 0; i < n_default_ligature_features; i++) {
        char tagstr[5];
        memcpy(tagstr, default_ligature_features[i], sizeof(unsigned char [4]));
        tagstr[4] = '\0';
        lua_getfield(L, -1, tagstr);
        if (lua_isnoneornil(L, -1)) { // The tag isn't explicitly set/unset, so include it
          memcpy(&liga_options->features[liga_options->n_features++], default_ligature_features[i], sizeof(unsigned char [4]));
        }
        lua_pop(L, 1);
      }

      // Handle custom features
      lua_pushnil(L);
      while (lua_next(L, -2) != 0) {
        size_t taglen;
        const char* tagname;
        if (lua_isinteger(L, -2)) {
          tagname = luaL_checklstring(L, -1, &taglen);
        } else {
          tagname = luaL_checklstring(L, -2, &taglen);
        }
        if (taglen != 4) {
          return luaL_error(
            L,
            "error in font options, wrong tag size: \"%s\", expected 4, got %d",
            tagname, taglen
          );
        }
        if (lua_toboolean(L, -1)) {
          memcpy(&liga_options->features[liga_options->n_features++], tagname, sizeof(unsigned char [4]));
        }
        lua_pop(L, 1); // pop value
      }
    } else if(lua_toboolean(L, -1)) {
      size_t n_features = n_default_features + n_default_ligature_features;
      liga_options->features = malloc(n_features * sizeof(unsigned char [4]));
      memcpy(liga_options->features, default_features, n_default_features * sizeof(unsigned char [4]));
      liga_options->n_features = n_default_features;
      memcpy(&liga_options->features[n_default_features],
             default_ligature_features,
             n_default_ligature_features * sizeof(unsigned char [4]));
      liga_options->n_features += n_default_ligature_features;
    }

    lua_pop(L, 8);

    if (style_local != 0)
      *style = style_local;
  }

  return 0;
}

static int f_font_load(lua_State *L) {
  const char *filename  = luaL_checkstring(L, 1);
  float size = luaL_checknumber(L, 2);
  int style = 0;
  ERenFontHinting hinting = FONT_HINTING_SLIGHT;
  ERenFontAntialiasing antialiasing = FONT_ANTIALIASING_SUBPIXEL;
  RenFontLigatureOptions ligopt = {0};

  int ret_code = font_get_options(L, &antialiasing, &hinting, &style, &ligopt);
  if (ret_code > 0)
    return ret_code;
  if (ligopt.features == NULL) {
    ligopt.script = NULL;
    ligopt.language = NULL;
    ligopt.features = malloc(n_default_features * sizeof(unsigned char [4]));
    memcpy(ligopt.features, default_features, n_default_features * sizeof(unsigned char [4]));
    ligopt.n_features = n_default_features;
  }

  RenFont** font = lua_newuserdata(L, sizeof(RenFont*));
  *font = ren_font_load(filename, size, antialiasing, hinting, style, ligopt);
  if (!*font) {
    free(ligopt.features);
    return luaL_error(L, "failed to load font");
  }
  luaL_setmetatable(L, API_TYPE_FONT);
  return 1;
}

static bool font_retrieve(lua_State* L, RenFont** fonts, int idx) {
  bool is_table;
  memset(fonts, 0, sizeof(RenFont*)*FONT_FALLBACK_MAX);
  if (lua_type(L, idx) != LUA_TTABLE) {
    fonts[0] = *(RenFont**)luaL_checkudata(L, idx, API_TYPE_FONT);
    is_table = false;
  } else {
    is_table = true;
    int len = luaL_len(L, idx); len = len > FONT_FALLBACK_MAX ? FONT_FALLBACK_MAX : len;
    for (int i = 0; i < len; i++) {
      lua_rawgeti(L, idx, i+1);
      fonts[i] = *(RenFont**) luaL_checkudata(L, -1, API_TYPE_FONT);
      lua_pop(L, 1);
    }
  }
#ifdef LITE_USE_SDL_RENDERER
  update_font_scale(active_window_renderer, fonts);
#endif
  return is_table;
}

static int f_font_copy(lua_State *L) {
  RenFont* fonts[FONT_FALLBACK_MAX];
  bool table = font_retrieve(L, fonts, 1);
  float size = lua_gettop(L) >= 2 ? luaL_checknumber(L, 2) : ren_font_group_get_height(fonts);
  int style = -1;
  ERenFontHinting hinting = -1;
  ERenFontAntialiasing antialiasing = -1;
  RenFontLigatureOptions ligopt = {0};

  int ret_code = font_get_options(L, &antialiasing, &hinting, &style, &ligopt);
  if (ret_code > 0)
    return ret_code;

  if (table) {
    lua_newtable(L);
    luaL_setmetatable(L, API_TYPE_FONT);
  }
  RenFontLigatureOptions *ligopt_ptr = ligopt.features == NULL ? NULL : &ligopt;
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; ++i) {
    RenFont** font = lua_newuserdata(L, sizeof(RenFont*));
    *font = ren_font_copy(fonts[i], size, antialiasing, hinting, style, ligopt_ptr);
    if (!*font) {
      if (!ligopt_ptr) free(ligopt_ptr->features);
      return luaL_error(L, "failed to copy font");
    }
    luaL_setmetatable(L, API_TYPE_FONT);
    if (table)
      lua_rawseti(L, -2, i+1);
  }
  return 1;
}

static int f_font_group(lua_State* L) {
  int table_size;
  luaL_checktype(L, 1, LUA_TTABLE);

  table_size = lua_rawlen(L, 1);
  if (table_size <= 0)
    return luaL_error(L, "failed to create font group: table is empty");
  if (table_size > FONT_FALLBACK_MAX)
    return luaL_error(L, "failed to create font group: table size too large");

  // we also need to ensure that there are no fontgroups inside it
  for (int i = 1; i <= table_size; i++) {
    if (lua_rawgeti(L, 1, i) != LUA_TUSERDATA)
      return luaL_typeerror(L, -1, API_TYPE_FONT "(userdata)");
    lua_pop(L, 1);
  }

  luaL_setmetatable(L, API_TYPE_FONT);
  return 1;
}

static int f_font_get_path(lua_State *L) {
  RenFont* fonts[FONT_FALLBACK_MAX];
  bool table = font_retrieve(L, fonts, 1);

  if (table) {
    lua_newtable(L);
  }
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; ++i) {
    const char* path = ren_font_get_path(fonts[i]);
    lua_pushstring(L, path);
    if (table)
      lua_rawseti(L, -2, i+1);
  }
  return 1;
}

static int f_font_set_tab_size(lua_State *L) {
  RenFont* fonts[FONT_FALLBACK_MAX]; font_retrieve(L, fonts, 1);
  int n = luaL_checknumber(L, 2);
  ren_font_group_set_tab_size(fonts, n);
  return 0;
}

static int f_font_gc(lua_State *L) {
  if (lua_istable(L, 1)) return 0; // do not run if its FontGroup
  RenFont** self = luaL_checkudata(L, 1, API_TYPE_FONT);
  ren_font_free(*self);

  return 0;
}


static int f_font_get_width(lua_State *L) {
  RenFont* fonts[FONT_FALLBACK_MAX]; font_retrieve(L, fonts, 1);
  size_t len;
  const char *text = luaL_checklstring(L, 2, &len);

  lua_pushnumber(L, ren_font_group_get_width(fonts, text, len, NULL));
  return 1;
}

static int f_font_get_height(lua_State *L) {
  RenFont* fonts[FONT_FALLBACK_MAX]; font_retrieve(L, fonts, 1);
  lua_pushnumber(L, ren_font_group_get_height(fonts));
  return 1;
}

static int f_font_get_size(lua_State *L) {
  RenFont* fonts[FONT_FALLBACK_MAX]; font_retrieve(L, fonts, 1);
  lua_pushnumber(L, ren_font_group_get_size(fonts));
  return 1;
}

static int f_font_set_size(lua_State *L) {
  RenFont* fonts[FONT_FALLBACK_MAX]; font_retrieve(L, fonts, 1);
  float size = luaL_checknumber(L, 2);
  int scale = 1;
#ifdef LITE_USE_SDL_RENDERER
  if (active_window_renderer != NULL) {
    scale = renwin_get_surface(active_window_renderer).scale;
  }
#endif
  ren_font_group_set_size(fonts, size, scale);
  return 0;
}

static int color_value_error(lua_State *L, int idx, int table_idx) {
  const char *type, *msg;
  // generate an appropriate error message
  if (luaL_getmetafield(L, -1, "__name") == LUA_TSTRING) {
    type = lua_tostring(L, -1); // metatable name
  } else if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
    type = "light userdata"; // special name for light userdata
  } else {
    type = lua_typename(L, lua_type(L, -1)); // default name
  }
  // the reason it went through so much hoops is to generate the correct error
  // message (with function name and proper index).
  msg = lua_pushfstring(L, "table[%d]: %s expected, got %s", table_idx, lua_typename(L, LUA_TNUMBER), type);
  return luaL_argerror(L, idx, msg);
}

static int get_color_value(lua_State *L, int idx, int table_idx) {
  lua_rawgeti(L, idx, table_idx);
  return lua_isnumber(L, -1) ? lua_tonumber(L, -1) : color_value_error(L, idx, table_idx);
}

static int get_color_value_opt(lua_State *L, int idx, int table_idx, int default_value) {
  lua_rawgeti(L, idx, table_idx);
  if (lua_isnoneornil(L, -1))
    return default_value;
  else if (lua_isnumber(L, -1))
    return lua_tonumber(L, -1);
  else
    return color_value_error(L, idx, table_idx);
}

static RenColor checkcolor(lua_State *L, int idx, int def) {
  RenColor color;
  if (lua_isnoneornil(L, idx)) {
    return (RenColor) { def, def, def, 255 };
  }
  luaL_checktype(L, idx, LUA_TTABLE);
  color.r = get_color_value(L, idx, 1);
  color.g = get_color_value(L, idx, 2);
  color.b = get_color_value(L, idx, 3);
  color.a = get_color_value_opt(L, idx, 4, 255);
  lua_pop(L, 4);
  return color;
}


static int f_show_debug(lua_State *L) {
  luaL_checkany(L, 1);
  rencache_show_debug(lua_toboolean(L, 1));
  return 0;
}


static int f_get_size(lua_State *L) {
  int w = 0, h = 0;
  if (active_window_renderer)
    ren_get_size(active_window_renderer, &w, &h);
  lua_pushnumber(L, w);
  lua_pushnumber(L, h);
  return 2;
}


static int f_begin_frame(UNUSED lua_State *L) {
  assert(active_window_renderer == NULL);
  active_window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  rencache_begin_frame(active_window_renderer);
  return 0;
}


static int f_end_frame(UNUSED lua_State *L) {
  assert(active_window_renderer != NULL);
  rencache_end_frame(active_window_renderer);
  active_window_renderer = NULL;
  // clear the font reference table
  lua_newtable(L);
  lua_rawseti(L, LUA_REGISTRYINDEX, RENDERER_FONT_REF);
  return 0;
}


static RenRect rect_to_grid(lua_Number x, lua_Number y, lua_Number w, lua_Number h) {
  int x1 = (int) (x + 0.5), y1 = (int) (y + 0.5);
  int x2 = (int) (x + w + 0.5), y2 = (int) (y + h + 0.5);
  return (RenRect) {x1, y1, x2 - x1, y2 - y1};
}


static int f_set_clip_rect(lua_State *L) {
  assert(active_window_renderer != NULL);
  lua_Number x = luaL_checknumber(L, 1);
  lua_Number y = luaL_checknumber(L, 2);
  lua_Number w = luaL_checknumber(L, 3);
  lua_Number h = luaL_checknumber(L, 4);
  RenRect rect = rect_to_grid(x, y, w, h);
  rencache_set_clip_rect(active_window_renderer, rect);
  return 0;
}


static int f_draw_rect(lua_State *L) {
  assert(active_window_renderer != NULL);
  lua_Number x = luaL_checknumber(L, 1);
  lua_Number y = luaL_checknumber(L, 2);
  lua_Number w = luaL_checknumber(L, 3);
  lua_Number h = luaL_checknumber(L, 4);
  RenRect rect = rect_to_grid(x, y, w, h);
  RenColor color = checkcolor(L, 5, 255);
  rencache_draw_rect(active_window_renderer, rect, color);
  return 0;
}

static int f_draw_text(lua_State *L) {
  assert(active_window_renderer != NULL);
  RenFont* fonts[FONT_FALLBACK_MAX];
  font_retrieve(L, fonts, 1);

  // stores a reference to this font to the reference table
  lua_rawgeti(L, LUA_REGISTRYINDEX, RENDERER_FONT_REF);
  if (lua_istable(L, -1))
  {
    lua_pushvalue(L, 1);
    lua_pushboolean(L, 1);
    lua_rawset(L, -3);
  } else {
    fprintf(stderr, "warning: failed to reference count fonts\n");
  }
  lua_pop(L, 1);

  size_t len;
  const char *text = luaL_checklstring(L, 2, &len);
  double x = luaL_checknumber(L, 3);
  int y = luaL_checknumber(L, 4);
  RenColor color = checkcolor(L, 5, 255);
  x = rencache_draw_text(active_window_renderer, fonts, text, len, x, y, color);
  lua_pushnumber(L, x);
  return 1;
}

static const luaL_Reg lib[] = {
  { "show_debug",         f_show_debug         },
  { "get_size",           f_get_size           },
  { "begin_frame",        f_begin_frame        },
  { "end_frame",          f_end_frame          },
  { "set_clip_rect",      f_set_clip_rect      },
  { "draw_rect",          f_draw_rect          },
  { "draw_text",          f_draw_text          },
  { NULL,                 NULL                 }
};

static const luaL_Reg fontLib[] = {
  { "__gc",               f_font_gc                 },
  { "load",               f_font_load               },
  { "copy",               f_font_copy               },
  { "group",              f_font_group              },
  { "set_tab_size",       f_font_set_tab_size       },
  { "get_width",          f_font_get_width          },
  { "get_height",         f_font_get_height         },
  { "get_size",           f_font_get_size           },
  { "set_size",           f_font_set_size           },
  { "get_path",           f_font_get_path           },
  { NULL, NULL }
};

int luaopen_renderer(lua_State *L) {
  // gets a reference on the registry to store font data
  lua_newtable(L);
  RENDERER_FONT_REF = luaL_ref(L, LUA_REGISTRYINDEX);

  luaL_newlib(L, lib);
  luaL_newmetatable(L, API_TYPE_FONT);
  luaL_setfuncs(L, fontLib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  lua_setfield(L, -2, "font");
  return 1;
}
