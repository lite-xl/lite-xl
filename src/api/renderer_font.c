#include <lua.h>
#include <lauxlib.h>

#include "api.h"
#include "fontdesc.h"
#include "renderer.h"
#include "rencache.h"

static int f_load(lua_State *L) {
  const char *filename  = luaL_checkstring(L, 1);
  float size = luaL_checknumber(L, 2);
  unsigned int font_options = 0;
  if (lua_gettop(L) > 2 && lua_istable(L, 3)) {
    lua_getfield(L, 3, "antialiasing");
    if (lua_isstring(L, -1)) {
      const char *antialiasing = lua_tostring(L, -1);
      if (antialiasing) {
        if (strcmp(antialiasing, "grayscale") == 0) {
          font_options |= RenFontGrayscale;
        } else if (strcmp(antialiasing, "subpixel") == 0) {
          font_options |= RenFontSubpixel;
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
          font_options |= RenFontHintingSlight;
        } else if (strcmp(hinting, "none") == 0) {
          font_options |= RenFontHintingNone;
        } else if (strcmp(hinting, "full") == 0) {
          font_options |= RenFontHintingFull;
        } else {
          return luaL_error(L, "error in renderer.font.load, unknown hinting option: \"%s\"", hinting);
        }
      }
    }
    lua_pop(L, 1);
  }

  if (ren_verify_font(filename)) {
    luaL_error(L, "failed to load font");
  }

  FontDesc *font_desc = lua_newuserdata(L, font_desc_alloc_size(filename));
  font_desc_init(font_desc, filename, size, font_options);
  luaL_setmetatable(L, API_TYPE_FONT);
  return 1;
}


static int f_set_tab_size(lua_State *L) {
  FontDesc *self = luaL_checkudata(L, 1, API_TYPE_FONT);
  int n = luaL_checknumber(L, 2);
  font_desc_set_tab_size(self, n);
  return 0;
}


static int f_gc(lua_State *L) {
  FontDesc *self = luaL_checkudata(L, 1, API_TYPE_FONT);
  font_desc_clear(self);
  return 0;
}

static int f_get_width(lua_State *L) {
  FontDesc *self = luaL_checkudata(L, 1, API_TYPE_FONT);
  const char *text = luaL_checkstring(L, 2);
  /* By calling ren_get_font_width with NULL as third arguments
     we will obtain the width in points. */
  int w = ren_get_font_width(self, text, NULL);
  lua_pushnumber(L, w);
  return 1;
}


static int f_subpixel_scale(lua_State *L) {
  FontDesc *self = luaL_checkudata(L, 1, API_TYPE_FONT);
  lua_pushnumber(L, ren_get_font_subpixel_scale(self));
  return 1;
}

static int f_get_width_subpixel(lua_State *L) {
  FontDesc *self = luaL_checkudata(L, 1, API_TYPE_FONT);
  const char *text = luaL_checkstring(L, 2);
  int subpixel_scale;
  /* We need to pass a non-null subpixel_scale pointer to force
     subpixel width calculation. */
  lua_pushnumber(L, ren_get_font_width(self, text, &subpixel_scale));
  return 1;
}


static int f_get_height(lua_State *L) {
  FontDesc *self = luaL_checkudata(L, 1, API_TYPE_FONT);
  lua_pushnumber(L, ren_get_font_height(self) );
  return 1;
}


static int f_get_size(lua_State *L) {
  FontDesc *self = luaL_checkudata(L, 1, API_TYPE_FONT);
  lua_pushnumber(L, self->size);
  return 1;
}


static int f_set_size(lua_State *L) {
  FontDesc *self = luaL_checkudata(L, 1, API_TYPE_FONT);
  float new_size = luaL_checknumber(L, 2);
  font_desc_clear(self);
  self->size = new_size;
  return 0;
}


static const luaL_Reg lib[] = {
  { "__gc",               f_gc                 },
  { "load",               f_load               },
  { "set_tab_size",       f_set_tab_size      },
  { "get_width",          f_get_width          },
  { "get_width_subpixel", f_get_width_subpixel },
  { "get_height",         f_get_height         },
  { "subpixel_scale",     f_subpixel_scale     },
  { "get_size",           f_get_size           },
  { "set_size",           f_set_size           },
  { NULL, NULL }
};

int luaopen_renderer_font(lua_State *L) {
  luaL_newmetatable(L, API_TYPE_FONT);
  luaL_setfuncs(L, lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  return 1;
}
