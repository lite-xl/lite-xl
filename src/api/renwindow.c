#include "api.h"
#include "../renwindow.h"
#include "lua.h"
#include <SDL3/SDL.h>
#include <stdlib.h>

static RenWindow *persistant_window = NULL;

static void init_window_icon(SDL_Window *window) {
#if !defined(_WIN32) && !defined(__APPLE__)
  #include "../resources/icons/icon.inl"
  (void) icon_rgba_len; /* unused */
  SDL_PixelFormat format = SDL_GetPixelFormatForMasks(32, 0x000000ff, 0x0000ff00, 0x00ff0000, 0xff000000);
  SDL_Surface *surf = SDL_CreateSurfaceFrom(64, 64, format, icon_rgba, 64 * 4);
  SDL_SetWindowIcon(window, surf);
  SDL_DestroySurface(surf);
#endif
}

static int f_renwin_create(lua_State *L) {
  const char *title = luaL_checkstring(L, 1);
  float width = luaL_optnumber(L, 4, 0);
  float height = luaL_optnumber(L, 5, 0);

  if (video_init() != 0)
    return luaL_error(L, "Error creating lite-xl window: %s", SDL_GetError());

  if (width < 1 || height < 1) {
    const SDL_DisplayMode* dm = SDL_GetCurrentDisplayMode(SDL_GetPrimaryDisplay());

    if (width < 1) {
      width = dm->w * 0.8;
    }
    if (height < 1) {
      height = dm->h * 0.8;
    }
  }

  SDL_Window *window = SDL_CreateWindow(
    title, width, height,
    SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY | SDL_WINDOW_HIDDEN
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

static int f_renwin_set_title(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  const char *title = luaL_checkstring(L, 2);
  SDL_SetWindowTitle(window_renderer->window, title);
  return 0;
}

static int f_renwin_set_size(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  double w = luaL_checknumber(L, 2);
  double h = luaL_checknumber(L, 3);
  SDL_SetWindowSize(window_renderer->window, w, h);
  ren_resize_window(window_renderer);
  return 0;
}

static int f_renwin_get_size(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  int x, y, w, h;
  SDL_GetWindowSize(window_renderer->window, &w, &h);
  SDL_GetWindowPosition(window_renderer->window, &x, &y);
  lua_pushinteger(L, w);
  lua_pushinteger(L, h);
  return 2;
}

static const char *window_opts[] = { "normal", "minimized", "maximized", "fullscreen", 0 };
enum { WIN_NORMAL, WIN_MINIMIZED, WIN_MAXIMIZED, WIN_FULLSCREEN };

static int f_renwin_set_mode(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  int n = luaL_checkoption(L, 2, "normal", window_opts);
  SDL_SetWindowFullscreen(window_renderer->window, n == WIN_FULLSCREEN);
  if (n == WIN_NORMAL) { SDL_RestoreWindow(window_renderer->window); }
  if (n == WIN_MAXIMIZED) { SDL_MaximizeWindow(window_renderer->window); }
  if (n == WIN_MINIMIZED) { SDL_MinimizeWindow(window_renderer->window); }
  return 0;
}

static int f_renwin_get_mode(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  unsigned flags = SDL_GetWindowFlags(window_renderer->window);
  if (flags & SDL_WINDOW_FULLSCREEN) {
    lua_pushstring(L, "fullscreen");
  } else if (flags & SDL_WINDOW_MINIMIZED) {
    lua_pushstring(L, "minimized");
  } else if (flags & SDL_WINDOW_MAXIMIZED) {
    lua_pushstring(L, "maximized");
  } else {
    lua_pushstring(L, "normal");
  }
  return 1;
}

static int f_renwin_get_id(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  lua_pushinteger(L, SDL_GetWindowID(window_renderer->window));
  return 1;
}

static int f_renwin_has_focus(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  unsigned flags = SDL_GetWindowFlags(window_renderer->window);
  lua_pushboolean(L, flags & SDL_WINDOW_INPUT_FOCUS);
  return 1;
}

static int f_renwin_raise(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  SDL_RaiseWindow(window_renderer->window);
  return 0;
}

static int f_renwin_set_bordered(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**) luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  SDL_SetWindowBordered(window_renderer->window, lua_toboolean(L, 2));
  return 0;
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
  { "create",       f_renwin_create       },
  { "__gc",         f_renwin_gc           },
  { "set_title",    f_renwin_set_title    },
  { "set_size",     f_renwin_set_size     },
  { "get_size",     f_renwin_get_size     },
  { "set_mode",     f_renwin_set_mode     },
  { "get_mode",     f_renwin_get_mode     },
  { "get_id",       f_renwin_get_id       },
  { "has_focus",    f_renwin_has_focus    },
  { "raise",        f_renwin_raise        },
  { "set_bordered", f_renwin_set_bordered },
  { "_persist",     f_renwin_persist      },
  { "_restore",     f_renwin_restore      },
  {NULL, NULL}
};

int luaopen_renwindow(lua_State* L) {
  luaL_newmetatable(L, API_TYPE_RENWINDOW);
  luaL_setfuncs(L, renwindow_lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");
  return 1;
}
