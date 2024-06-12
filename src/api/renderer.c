#include <string.h>
#include "api.h"
#include "../renderer.h"
#include "../rencache.h"
#include "../renwindow.h"
#include "lua.h"

// a reference index to a table that stores the fonts
static int RENDERER_FONT_REF = LUA_NOREF;
// a reference index to a table that stores the canvases sent to the renderer
int RENDERER_CANVAS_REF = LUA_NOREF;
// a reference index to a table that stores the temporary canvases needed for COW
int RENDERER_CANVAS_COW_REF = LUA_NOREF;
// reference indexes for tables that cache scaled versions of canvases
static int RENDERER_CANVAS_SCALED_CURRENT_REF = LUA_NOREF;
static int RENDERER_CANVAS_SCALED_PREVIOUS_REF = LUA_NOREF;

static int font_get_options(
  lua_State *L,
  ERenFontAntialiasing *antialiasing,
  ERenFontHinting *hinting,
  int *style
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

    lua_pop(L, 5);

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

  int ret_code = font_get_options(L, &antialiasing, &hinting, &style);
  if (ret_code > 0)
    return ret_code;

  RenFont** font = lua_newuserdata(L, sizeof(RenFont*));
  *font = ren_font_load(window_renderer, filename, size, antialiasing, hinting, style);
  if (!*font)
    return luaL_error(L, "failed to load font");
  luaL_setmetatable(L, API_TYPE_FONT);
  return 1;
}

static bool font_retrieve(lua_State* L, RenFont** fonts, int idx) {
  memset(fonts, 0, sizeof(RenFont*)*FONT_FALLBACK_MAX);
  if (lua_type(L, idx) != LUA_TTABLE) {
    fonts[0] = *(RenFont**)luaL_checkudata(L, idx, API_TYPE_FONT);
    return false;
  }
  int len = luaL_len(L, idx); len = len > FONT_FALLBACK_MAX ? FONT_FALLBACK_MAX : len;
  for (int i = 0; i < len; i++) {
    lua_rawgeti(L, idx, i+1);
    fonts[i] = *(RenFont**) luaL_checkudata(L, -1, API_TYPE_FONT);
    lua_pop(L, 1);
  }
  return true;
}

static int f_font_copy(lua_State *L) {
  RenFont* fonts[FONT_FALLBACK_MAX];
  bool table = font_retrieve(L, fonts, 1);
  float size = lua_gettop(L) >= 2 ? luaL_checknumber(L, 2) : ren_font_group_get_height(fonts);
  int style = -1;
  ERenFontHinting hinting = -1;
  ERenFontAntialiasing antialiasing = -1;

  int ret_code = font_get_options(L, &antialiasing, &hinting, &style);
  if (ret_code > 0)
    return ret_code;

  if (table) {
    lua_newtable(L);
    luaL_setmetatable(L, API_TYPE_FONT);
  }
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; ++i) {
    RenFont** font = lua_newuserdata(L, sizeof(RenFont*));
    *font = ren_font_copy(window_renderer, fonts[i], size, antialiasing, hinting, style);
    if (!*font)
      return luaL_error(L, "failed to copy font");
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

  lua_pushnumber(L, ren_font_group_get_width(window_renderer, fonts, text, len, NULL));
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
  ren_font_group_set_size(window_renderer, fonts, size);
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
  int w, h;
  ren_get_size(window_renderer, &w, &h);
  lua_pushnumber(L, w);
  lua_pushnumber(L, h);
  return 2;
}


static int f_begin_frame(UNUSED lua_State *L) {
  rencache_begin_frame(window_renderer);
  return 0;
}


static int f_end_frame(UNUSED lua_State *L) {
  rencache_end_frame(window_renderer);
  // clear the font reference table
  lua_newtable(L);
  lua_rawseti(L, LUA_REGISTRYINDEX, RENDERER_FONT_REF);
  // clear the canvas reference table
  lua_newtable(L);
  lua_rawseti(L, LUA_REGISTRYINDEX, RENDERER_CANVAS_REF);
  // clear the canvas COW reference table
  lua_newtable(L);
  lua_rawseti(L, LUA_REGISTRYINDEX, RENDERER_CANVAS_COW_REF);
  // clear the previous frame scaled canvas cache
  lua_newtable(L);
  lua_rawseti(L, LUA_REGISTRYINDEX, RENDERER_CANVAS_SCALED_PREVIOUS_REF);
  // swap current and previous scaled canvas cache
  int tmp_ref = RENDERER_CANVAS_SCALED_PREVIOUS_REF;
  RENDERER_CANVAS_SCALED_PREVIOUS_REF = RENDERER_CANVAS_SCALED_CURRENT_REF;
  RENDERER_CANVAS_SCALED_CURRENT_REF = tmp_ref;
  return 0;
}


static RenRect rect_to_grid(lua_Number x, lua_Number y, lua_Number w, lua_Number h) {
  int x1 = (int) (x + 0.5), y1 = (int) (y + 0.5);
  int x2 = (int) (x + w + 0.5), y2 = (int) (y + h + 0.5);
  return (RenRect) {x1, y1, x2 - x1, y2 - y1};
}


static int f_set_clip_rect(lua_State *L) {
  lua_Number x = luaL_checknumber(L, 1);
  lua_Number y = luaL_checknumber(L, 2);
  lua_Number w = luaL_checknumber(L, 3);
  lua_Number h = luaL_checknumber(L, 4);
  RenRect rect = rect_to_grid(x, y, w, h);
  rencache_set_clip_rect(window_renderer, rect);
  return 0;
}


static int f_draw_rect(lua_State *L) {
  lua_Number x = luaL_checknumber(L, 1);
  lua_Number y = luaL_checknumber(L, 2);
  lua_Number w = luaL_checknumber(L, 3);
  lua_Number h = luaL_checknumber(L, 4);
  RenRect rect = rect_to_grid(x, y, w, h);
  RenColor color = checkcolor(L, 5, 255);
  rencache_draw_rect(window_renderer, rect, color);
  return 0;
}

static int f_draw_text(lua_State *L) {
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
  x = rencache_draw_text(window_renderer, fonts, text, len, x, y, color);
  lua_pushnumber(L, x);
  return 1;
}

static int f_create_canvas(lua_State *L) {
  int w = luaL_checkinteger(L, 1);
  int h = luaL_checkinteger(L, 2);
  if (w <= 0) {
    return luaL_error(L, "error in canvas options, width must be a positive integer");
  }
  if (h <= 0) {
    return luaL_error(L, "error in canvas options, height must be a positive integer");
  }

  RenColor color = checkcolor(L, 3, 0); // defaults to black
  // TODO: might be a good idea to match the window format
  SDL_Surface *s = SDL_CreateRGBSurface(0, w, h, 32,
    0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF);
  if (!s) {
    return luaL_error(L, "unable to create canvas: %s", SDL_GetError);
  }
  SDL_FillRect(s, NULL, SDL_MapRGBA(s->format, color.r, color.g, color.b, color.a));

  RenCanvas *canvas = lua_newuserdata(L, sizeof(RenCanvas));
  RenSurface window_surface = renwin_get_surface(&window_renderer);
  canvas->rensurface.surface = s;
  canvas->rensurface.scale = window_surface.scale;
  canvas->change_counter = 0;
  luaL_setmetatable(L, API_TYPE_CANVAS);
  return 1;
}

// Check if a canvas is cached in the specified registry table.
// The key is the canvas itself, the secondary key is a string specific for
// the scaled canvas.
// If the canvas was found this returns true and pushes the cached canvas on
// the stack. Otherwise it returns false and doesn't push anything on the stack.
static bool check_if_cached(lua_State *L, int registry_ref, int key_idx, int secondary_key_idx) {
  if (key_idx < 0) key_idx = lua_gettop(L) + key_idx + 1;
  if (secondary_key_idx < 0) secondary_key_idx = lua_gettop(L) + secondary_key_idx + 1;

  lua_rawgeti(L, LUA_REGISTRYINDEX, registry_ref);
  if (!lua_istable(L, -1)) {
    fprintf(stderr, "warning: failed to check canvas cache\n");
    lua_pop(L, 1);
    return false;
  }

  // Check if there is a cache for the key
  lua_pushvalue(L, key_idx);
  lua_rawget(L, -2);
  if (lua_isnoneornil(L, -1)) {
    lua_pop(L, 2);
    return false;
  }
  // We should now have the cache table at the top of the stack
  // Check if the secondary key is in the cache
  lua_pushvalue(L, secondary_key_idx);
  lua_rawget(L, -2);
  if (lua_isnoneornil(L, -1)) {
    lua_pop(L, 3);
    return false;
  }
  // Only keep the cached canvas on the stack
  lua_replace(L, -3);
  lua_pop(L, 1);
  return true;
}

// The cache is in the format:
// ```lua
// local current_frame_cache = {
//   [key] = {
//     [secondary_key1] = scaled_canvas1_1,
//     [secondary_key2] = scaled_canvas1_2
//   }
// }
// ```
static void cache_canvas(lua_State *L, int key_idx, int secondary_key_idx, int canvas_idx) {
  if (key_idx < 0) key_idx = lua_gettop(L) + key_idx + 1;
  if (secondary_key_idx < 0) secondary_key_idx = lua_gettop(L) + secondary_key_idx + 1;
  if (canvas_idx < 0) canvas_idx = lua_gettop(L) + canvas_idx + 1;

  lua_rawgeti(L, LUA_REGISTRYINDEX, RENDERER_CANVAS_SCALED_CURRENT_REF);
  if (!lua_istable(L, -1)) {
    fprintf(stderr, "warning: failed to add canvas to cache\n");
    lua_pop(L, 1);
    return;
  }

  // Obtain the canvas cache
  lua_pushvalue(L, key_idx);
  lua_rawget(L, -2);
  if (lua_isnoneornil(L, -1)) {
    // There is no cache for the canvas, so we create it
    lua_pop(L, 1);
    lua_newtable(L);
    lua_pushvalue(L, key_idx); // Key = key
    lua_pushvalue(L, -2); // Value = {}
    lua_rawset(L, -4); // current[Key] = Value
  }
  // We should now have the cache table for the specified key at the top of the stack
  lua_pushvalue(L, secondary_key_idx);
  lua_pushvalue(L, canvas_idx);
  lua_rawset(L, -3); // current[key][secondary_key] = canvas
  lua_pop(L, 2);
}

// Creates a scaled version of the canvas and pushes it to the stack
static RenCanvas* push_scaled_canvas(lua_State *L, RenCanvas *original_canvas, RenRect scale_rect) {
  RenCanvas *temp_canvas = lua_newuserdata(L, sizeof(RenCanvas));
  temp_canvas->change_counter = original_canvas->change_counter;
  temp_canvas->rensurface.scale = original_canvas->rensurface.scale;
  temp_canvas->rensurface.surface = SDL_CreateRGBSurface(0, scale_rect.width, scale_rect.height, 32,
                                    0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF);
  if (!temp_canvas->rensurface.surface) {
    fprintf(stderr, "warning: failed to create scaled canvas\n");
  }
  temp_canvas->change_counter = 0;
  luaL_setmetatable(L, API_TYPE_CANVAS);

  SDL_Surface *src = original_canvas->rensurface.surface;
  SDL_Surface *dst = temp_canvas->rensurface.surface;
  if (src && dst) {
    SDL_Rect src_rect = { scale_rect.x, scale_rect.y, src->w, src->h };
    SDL_Rect dst_rect = { 0, 0, dst->w, dst->h };
    // Use the lower variant to avoid eventual clips
    SDL_LowerBlitScaled(src, &src_rect, dst, &dst_rect);
  }
  return temp_canvas;
}

static void push_scaled_key(lua_State *L, unsigned int change_counter, RenRect scale_rect) {
  lua_pushinteger(L, change_counter);
  lua_pushstring(L, "-");
  lua_pushinteger(L, scale_rect.x);
  lua_pushstring(L, ",");
  lua_pushinteger(L, scale_rect.y);
  lua_pushstring(L, ",");
  lua_pushinteger(L, scale_rect.width);
  lua_pushstring(L, ",");
  lua_pushinteger(L, scale_rect.height);
  lua_concat(L, 9);
}

static int f_draw_canvas(lua_State *L) {
  int nparms = lua_gettop(L);
  if (nparms != 3 && nparms != 5 && nparms != 9) {
    return luaL_error(L, "wrong number of parameters");
  }
  RenCanvas* canvas = (RenCanvas*) luaL_checkudata(L, 1, API_TYPE_CANVAS);
  RenSurface rs = canvas->rensurface;

  // stores a reference to this canvas to the reference table
  lua_rawgeti(L, LUA_REGISTRYINDEX, RENDERER_CANVAS_REF);
  if (lua_istable(L, -1))
  {
    lua_pushvalue(L, 1);
    // Store the change counter to allow COW for canvas operations
    lua_pushinteger(L, canvas->change_counter);
    lua_rawset(L, -3);
  } else {
    fprintf(stderr, "warning: failed to reference count canvases\n");
  }
  lua_pop(L, 1);

  if (!canvas->rensurface.surface) return 0;

  lua_Number dst_x = luaL_checknumber(L, 2);
  lua_Number dst_y = luaL_checknumber(L, 3);
  lua_Number dst_w = luaL_optnumber(L, 4, canvas->rensurface.surface->w);
  lua_Number dst_h = luaL_optnumber(L, 5, canvas->rensurface.surface->h);
  lua_Number src_x = luaL_optinteger(L, 6, 0);
  lua_Number src_y = luaL_optinteger(L, 7, 0);
  lua_Number src_w = luaL_optinteger(L, 8, canvas->rensurface.surface->w);
  lua_Number src_h = luaL_optinteger(L, 9, canvas->rensurface.surface->h);

  RenRect dst_rect = rect_to_grid(dst_x, dst_y, dst_w, dst_h);
  if (dst_rect.width <= 0 || dst_rect.height <= 0
      || src_w <= 0 || src_h <= 0
      || dst_rect.x + dst_rect.width < 0 || dst_rect.y + dst_rect.height < 0
      || src_x + src_w < 0 || src_y + src_h < 0) {
    return 0;
  }

  // Check if we will render the canvas scaled
  if (dst_rect.width != src_w || dst_rect.height != src_h) {
    // We need to pre-scale the canvas, because clipping in rencache
    // will create artifacts due to rounding errors.

    // Create the key in the format CHANGE-X,Y,WIDTH,HEIGHT
    RenRect scale_rect = (RenRect){ src_x, src_y, dst_rect.width, dst_rect.height };
    scale_rect.width = scale_rect.width < 1 ? 1 : scale_rect.width;
    scale_rect.height = scale_rect.height < 1 ? 1 : scale_rect.height;
    push_scaled_key(L, canvas->change_counter, scale_rect);

    // Check if we already used the scaled version in this frame
    if(!check_if_cached(L, RENDERER_CANVAS_SCALED_CURRENT_REF, 1, -1)) {
      // Check if we used it in the previous frame
      if(check_if_cached(L, RENDERER_CANVAS_SCALED_PREVIOUS_REF, 1, -1)) {
        // Push the cached version to the current frame cache
        cache_canvas(L, 1, -2, -1);
      } else {
        // We need to cache the scaled version
        push_scaled_canvas(L, canvas, scale_rect);
        cache_canvas(L, 1, -2, -1);
      }
    }

    // Use the scaled canvas
    RenCanvas *scaled_canvas = (RenCanvas*) luaL_checkudata(L, -1, API_TYPE_CANVAS);
    rs = scaled_canvas->rensurface;
    lua_pop(L, 1);
    // Set the coordinates to use the full size of the scaled canvas
    src_x = 0;
    src_y = 0;
    src_w = dst_rect.width;
    src_h = dst_rect.height;
  }

  RenRect src_rect = { src_x, src_y, src_w, src_h };
  rencache_draw_surface(dst_rect, src_rect, &rs, canvas->change_counter);
  return 0;
}

static const luaL_Reg lib[] = {
  { "show_debug",         f_show_debug         },
  { "get_size",           f_get_size           },
  { "begin_frame",        f_begin_frame        },
  { "end_frame",          f_end_frame          },
  { "set_clip_rect",      f_set_clip_rect      },
  { "draw_rect",          f_draw_rect          },
  { "draw_text",          f_draw_text          },
  { "create_canvas",      f_create_canvas      },
  { "draw_canvas",        f_draw_canvas        },
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
  // gets a reference on the registry to store canvases sent to the renderer
  lua_newtable(L);
  RENDERER_CANVAS_REF = luaL_ref(L, LUA_REGISTRYINDEX);
  // gets a reference on the registry to store canvases needed for COW
  lua_newtable(L);
  RENDERER_CANVAS_COW_REF = luaL_ref(L, LUA_REGISTRYINDEX);
  // gets references on the registry to cache scaled versions of canvases
  lua_newtable(L);
  RENDERER_CANVAS_SCALED_CURRENT_REF = luaL_ref(L, LUA_REGISTRYINDEX);
  lua_newtable(L);
  RENDERER_CANVAS_SCALED_PREVIOUS_REF = luaL_ref(L, LUA_REGISTRYINDEX);

  luaL_newlib(L, lib);
  luaL_newmetatable(L, API_TYPE_FONT);
  luaL_setfuncs(L, fontLib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  lua_setfield(L, -2, "font");
  return 1;
}
