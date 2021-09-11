#include "api.h"
#include "renderer.h"
#include "rencache.h"

static int f_font_load(lua_State *L) {
  const char *filename  = luaL_checkstring(L, 1);
  float size = luaL_checknumber(L, 2);
  unsigned int font_hinting = FONT_HINTING_SLIGHT;
  bool subpixel = true;
  if (lua_gettop(L) > 2 && lua_istable(L, 3)) {
    lua_getfield(L, 3, "antialiasing");
    if (lua_isstring(L, -1)) {
      const char *antialiasing = lua_tostring(L, -1);
      if (antialiasing) {
        if (strcmp(antialiasing, "grayscale") == 0) {
          subpixel = false;
        } else if (strcmp(antialiasing, "subpixel") == 0) {
          subpixel = true;
        } else {
          return luaL_error(L, "error in renderer.font.load, unknown antialiasing option: \"%s\"", antialiasing);
        }
      }
    }
    lua_pop(L, 1);
    lua_getfield(L, 3, "hinting");
    if (lua_isstring(L, -1)) {
      const char *hinting = lua_tostring(L, -1);
      if (hinting) {
        if (strcmp(hinting, "slight") == 0) {
          font_hinting = FONT_HINTING_SLIGHT;
        } else if (strcmp(hinting, "none") == 0) {
          font_hinting = FONT_HINTING_NONE;
        } else if (strcmp(hinting, "full") == 0) {
          font_hinting = FONT_HINTING_FULL;
        } else {
          return luaL_error(L, "error in renderer.font.load, unknown hinting option: \"%s\"", hinting);
        }
      }
    }
    lua_pop(L, 1);
  }
  RenFont** font = lua_newuserdata(L, sizeof(RenFont*));
  *font = ren_font_load(filename, size, subpixel, font_hinting);
  if (!*font)
    return luaL_error(L, "failed to load font");
  luaL_setmetatable(L, API_TYPE_FONT);
  return 1;
}

static int f_font_copy(lua_State *L) {
  RenFont** self = luaL_checkudata(L, 1, API_TYPE_FONT);
  float size = lua_gettop(L) >= 2 ? luaL_checknumber(L, 2) : ren_font_get_height(*self);
  RenFont** font = lua_newuserdata(L, sizeof(RenFont*));
  *font = ren_font_copy(*self, size);
  if (!*font)
    return luaL_error(L, "failed to copy font");
  luaL_setmetatable(L, API_TYPE_FONT);
  return 1;
}

static int f_font_set_tab_size(lua_State *L) {
  RenFont** self = luaL_checkudata(L, 1, API_TYPE_FONT);
  int n = luaL_checknumber(L, 2);
  ren_font_set_tab_size(*self, n);
  return 0;
}

static int f_font_gc(lua_State *L) {
  RenFont** self = luaL_checkudata(L, 1, API_TYPE_FONT);
  ren_font_free(*self);
  return 0;
}

static int f_font_get_width(lua_State *L) {
  RenFont** self = luaL_checkudata(L, 1, API_TYPE_FONT);
  lua_pushnumber(L, ren_font_get_width(*self, luaL_checkstring(L, 2)));
  return 1;
}

static int f_font_get_height(lua_State *L) {
  RenFont** self = luaL_checkudata(L, 1, API_TYPE_FONT);
  lua_pushnumber(L, ren_font_get_height(*self));
  return 1;
}

static int f_font_get_size(lua_State *L) {
  RenFont** self = luaL_checkudata(L, 1, API_TYPE_FONT);
  lua_pushnumber(L, ren_font_get_size(*self));
  return 1;
}

static RenColor checkcolor(lua_State *L, int idx, int def) {
  RenColor color;
  if (lua_isnoneornil(L, idx)) {
    return (RenColor) { def, def, def, 255 };
  }
  lua_rawgeti(L, idx, 1);
  lua_rawgeti(L, idx, 2);
  lua_rawgeti(L, idx, 3);
  lua_rawgeti(L, idx, 4);
  color.r = luaL_checknumber(L, -4);
  color.g = luaL_checknumber(L, -3);
  color.b = luaL_checknumber(L, -2);
  color.a = luaL_optnumber(L, -1, 255);
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
  ren_get_size(&w, &h);
  lua_pushnumber(L, w);
  lua_pushnumber(L, h);
  return 2;
}


static int f_begin_frame(lua_State *L) {
  rencache_begin_frame(L);
  return 0;
}


static int f_end_frame(lua_State *L) {
  rencache_end_frame(L);
  return 0;
}


static int f_set_clip_rect(lua_State *L) {
  RenRect rect;
  rect.x = luaL_checknumber(L, 1);
  rect.y = luaL_checknumber(L, 2);
  rect.width = luaL_checknumber(L, 3);
  rect.height = luaL_checknumber(L, 4);
  rencache_set_clip_rect(rect);
  return 0;
}


static int f_draw_rect(lua_State *L) {
  RenRect rect;
  rect.x = luaL_checknumber(L, 1);
  rect.y = luaL_checknumber(L, 2);
  rect.width = luaL_checknumber(L, 3);
  rect.height = luaL_checknumber(L, 4);
  RenColor color = checkcolor(L, 5, 255);
  rencache_draw_rect(rect, color);
  return 0;
}

static int f_draw_text(lua_State *L) {
  RenFont** font = luaL_checkudata(L, 1, API_TYPE_FONT);
  const char *text = luaL_checkstring(L, 2);
  int x_subpixel = luaL_checknumber(L, 3);
  int y = luaL_checknumber(L, 4);
  RenColor color = checkcolor(L, 5, 255);
  x_subpixel = rencache_draw_text(L, *font, text, x_subpixel, y, color);
  lua_pushnumber(L, x_subpixel);
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
  { "set_tab_size",       f_font_set_tab_size       },
  { "get_width",          f_font_get_width          },
  { "get_height",         f_font_get_height         },
  { "get_size",           f_font_get_size           },
  { NULL, NULL }
};

int luaopen_renderer(lua_State *L) {
  luaL_newlib(L, lib);
  luaL_newmetatable(L, API_TYPE_FONT);
  luaL_setfuncs(L, fontLib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  lua_setfield(L, -2, "font");
  return 1;
}
