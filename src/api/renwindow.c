#include "api.h"
#include "../renwindow.h"
#include "lua.h"
#include <SDL.h>

static RenWindow *persistant_window = NULL;

static void init_window_icon(SDL_Window *window) {
#if !defined(_WIN32) && !defined(__APPLE__)
  #include "../resources/icons/icon.inl"
  (void) icon_rgba_len; /* unused */
  SDL_Surface *surf = SDL_CreateRGBSurfaceFrom(
    icon_rgba, 64, 64,
    32, 64 * 4,
    0x000000ff,
    0x0000ff00,
    0x00ff0000,
    0xff000000);
  SDL_SetWindowIcon(window, surf);
  SDL_FreeSurface(surf);
#endif
}

static int f_renwin_create(lua_State *L) {
  const char *title = luaL_checkstring(L, 1);
  const int x = luaL_optinteger(L, 2, SDL_WINDOWPOS_UNDEFINED);
  const int y = luaL_optinteger(L, 3, SDL_WINDOWPOS_UNDEFINED);
  float width = luaL_optnumber(L, 4, 0);
  float height = luaL_optnumber(L, 5, 0);

  if (width < 1 || height < 1) {
    SDL_DisplayMode dm;
    SDL_GetCurrentDisplayMode(0, &dm);

    if (width < 1) {
      width = dm.w * 0.8;
    }
    if (height < 1) {
      height = dm.h * 0.8;
    }
  }

  SDL_Window *window = SDL_CreateWindow(
    title, x, y, width, height,
    SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_HIDDEN
  );
  if (!window) {
    return luaL_error(L, "Error creating lite-xl window: %s", SDL_GetError());
  }
  init_window_icon(window);

  RenWindow **window_renderer = (RenWindow**)lua_newuserdata(L, sizeof(RenWindow*));
  luaL_setmetatable(L, API_TYPE_RENWINDOW);

  *window_renderer = ren_create(window);

  return 1;
}

static int f_renwin_gc(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  if (window_renderer != persistant_window)
    ren_destroy(window_renderer);

  return 0;
}

static int f_renwin_get_size(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  int w, h;
  ren_get_size(window_renderer, &w, &h);
  lua_pushnumber(L, w);
  lua_pushnumber(L, h);
  return 2;
}

static int f_renwin_persist(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);

  persistant_window = window_renderer;
  return 0;
}

static int f_renwin_restore(lua_State *L) {
  if (!persistant_window) {
    lua_pushnil(L);
  }
  else {
    RenWindow **window_renderer = (RenWindow**)lua_newuserdata(L, sizeof(RenWindow*));
    luaL_setmetatable(L, API_TYPE_RENWINDOW);

    *window_renderer = persistant_window;
  }

  return 1;
}

static const luaL_Reg renwindow_lib[] = {
  { "create",     f_renwin_create     },
  { "__gc",       f_renwin_gc         },
  { "get_size",   f_renwin_get_size   },
  { "_persist",   f_renwin_persist    },
  { "_restore",   f_renwin_restore    },
  {NULL, NULL}
};

int luaopen_renwindow(lua_State* L) {
  luaL_newmetatable(L, API_TYPE_RENWINDOW);
  luaL_setfuncs(L, renwindow_lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  return 1;
}
