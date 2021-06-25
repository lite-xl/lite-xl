#include "api.h"
#include "renderer.h"
#include "rencache.h"

extern RenCache *window_rencache;

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


static RenCache *opt_rencache_arg(lua_State *L, int *index) {
  RenCache *rencache;
  if (lua_touserdata(L, 1)) {
    return luaL_checkudata(L, *(index++), API_TYPE_RENCACHE);
  }
  return window_rencache;
}


static int f_show_debug(lua_State *L) {
  int index = 1;
  RenCache *rencache = opt_rencache_arg(L, &index);
  luaL_checkany(L, index);
  rencache_show_debug(rencache, lua_toboolean(L, index));
  return 0;
}


static int f_get_size(lua_State *L) {
  int w, h;
  ren_get_size(window_ren_surface, &w, &h);
  lua_pushnumber(L, w);
  lua_pushnumber(L, h);
  return 2;
}


static int f_begin_frame(lua_State *L) {
  int index = 1;
  RenCache *rencache = opt_rencache_arg(L, &index);
  rencache_begin_frame(rencache, window_ren_surface, L);
  return 0;
}


static int f_end_frame(lua_State *L) {
  int index = 1;
  RenCache *rencache = opt_rencache_arg(L, &index);
  rencache_end_frame(rencache, L);
  return 0;
}


static int f_set_clip_rect(lua_State *L) {
  RenRect rect;
  int index = 1;
  RenCache *rencache = opt_rencache_arg(L, &index);
  rect.x = luaL_checknumber(L, index);
  rect.y = luaL_checknumber(L, index + 1);
  rect.width = luaL_checknumber(L, index + 2);
  rect.height = luaL_checknumber(L, index + 3);
  rencache_set_clip_rect(rencache, rect);
  return 0;
}


static int f_draw_rect(lua_State *L) {
  RenRect rect;
  int index = 1;
  RenCache *rencache = opt_rencache_arg(L, &index);
  rect.x = luaL_checknumber(L, index);
  rect.y = luaL_checknumber(L, index + 1);
  rect.width = luaL_checknumber(L, index + 2);
  rect.height = luaL_checknumber(L, index + 3);
  RenColor color = checkcolor(L, index + 4, 255);
  rencache_draw_rect(rencache, rect, color);
  return 0;
}

static int draw_text_subpixel_impl(lua_State *L, bool draw_subpixel) {
  int index = 1;
  RenCache *rencache = opt_rencache_arg(L, &index);
  FontDesc *font_desc = luaL_checkudata(L, index, API_TYPE_FONT);
  const char *text = luaL_checkstring(L, index + 1);
  /* The coordinate below will be in subpixel iff draw_subpixel is true.
     Otherwise it will be in pixels. */
  int x_subpixel = luaL_checknumber(L, index + 2);
  int y = luaL_checknumber(L, index + 3);
  RenColor color = checkcolor(L, index + 4, 255);

  CPReplaceTable *rep_table;
  RenColor replace_color;
  if (lua_gettop(L) >= index + 6) {
    rep_table = luaL_checkudata(L, index + 5, API_TYPE_REPLACE);
    replace_color = checkcolor(L, index + 6, 255);
  } else {
    rep_table = NULL;
    replace_color = (RenColor) {0};
  }

  x_subpixel = rencache_draw_text(rencache, L, font_desc, 1, text, x_subpixel, y, color, draw_subpixel, rep_table, replace_color);
  lua_pushnumber(L, x_subpixel);
  return 1;
}

static int f_draw_text(lua_State *L) {
  return draw_text_subpixel_impl(L, false);
}


static int f_draw_text_subpixel(lua_State *L) {
  return draw_text_subpixel_impl(L, true);
}


static const luaL_Reg lib[] = {
  { "show_debug",         f_show_debug         },
  { "get_size",           f_get_size           },
  { "begin_frame",        f_begin_frame        },
  { "end_frame",          f_end_frame          },
  { "set_clip_rect",      f_set_clip_rect      },
  { "draw_rect",          f_draw_rect          },
  { "draw_text",          f_draw_text          },
  { "draw_text_subpixel", f_draw_text_subpixel },
  { NULL,                 NULL                 }
};


int luaopen_renderer_font(lua_State *L);
int luaopen_renderer_replacements(lua_State *L);

int luaopen_renderer(lua_State *L) {
  luaL_newlib(L, lib);

  window_rencache = lua_newuserdata(L, sizeof(RenCache));
  rencache_init(window_rencache);
  luaL_setmetatable(L, API_TYPE_RENCACHE);
  lua_pushvalue(L, -1);
  luaL_ref(L, -1);
  lua_setfield(L, -2, "window");

  luaopen_renderer_font(L);
  lua_setfield(L, -2, "font");
  luaopen_renderer_replacements(L);
  lua_setfield(L, -2, "replacements");
  return 1;
}
