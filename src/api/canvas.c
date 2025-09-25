#include "api.h"
#include <lauxlib.h>
#include <lua.h>
#include "../renderer.h"
#include <SDL3/SDL.h>
#include <string.h>
#include "utils/lxlauxlib.h"
#include <assert.h>

static int f_new(lua_State *L) {
  lua_Integer w = luaL_checkinteger(L, 1);
  lua_Integer h = luaL_checkinteger(L, 2);
  RenColor color = luaXL_checkcolor(L, 3, 0);
  bool transparency = luaXL_optboolean(L, 4, true);

  SDL_Surface *surface = SDL_CreateSurface(w, h, transparency ? SDL_PIXELFORMAT_RGBA32 : SDL_PIXELFORMAT_RGB24);
  SDL_FillSurfaceRect(surface, NULL, SDL_MapSurfaceRGBA(surface, color.r, color.g, color.b, color.a));

  RenCanvas *canvas = lua_newuserdatauv(L, sizeof(RenCanvas), USERDATA_LAST - 1);
  luaL_setmetatable(L, API_TYPE_CANVAS);
  canvas->w = w;
  canvas->h = h;
  canvas->version = 0;

  RenCanvasRef *ref = lua_newuserdata(L, sizeof(RenCanvasRef));
  luaL_setmetatable(L, API_TYPE_CANVAS_REF);
  lua_setiuservalue(L, -2, USERDATA_CANVAS_REF);
  ref->render_ref_count = 0;
  ref->surface = surface;

  return 1;
}


static int f_get_size(lua_State *L) {
  RenCanvas *canvas = luaL_checkudata(L, 1, API_TYPE_CANVAS);
  lua_pushinteger(L, canvas->w);
  lua_pushinteger(L, canvas->h);
  return 2;
}


// When the Canvas is in-flight to the renderer, we want to avoid altering it
// so that the original one is output, while still allowing to modify the Canvas.
// So we move aside the original CanvasRef and associate a new copy to the Canvas.
static RenCanvasRef *cow_if_needed(lua_State *L, RenCanvasRef *original) {
  RenCanvasRef *ref = original;
  if (ref->render_ref_count != 0) {
    // Note: SDL_DuplicateSurface copies the clip rect. We **do** want that.
    SDL_Surface *surface_copy = SDL_DuplicateSurface(ref->surface);
    ref = lua_newuserdata(L, sizeof(RenCanvasRef));
    luaL_setmetatable(L, API_TYPE_CANVAS_REF);
    lua_setiuservalue(L, 1, USERDATA_CANVAS_REF);
    ref->surface = surface_copy;
    ref->render_ref_count = 0;
    // TODO: should we reset the version?
  }
  return ref;
}


static int f_get_pixels(lua_State *L) {
  RenCanvas *canvas = luaL_checkudata(L, 1, API_TYPE_CANVAS);
  lua_getiuservalue(L, 1, USERDATA_CANVAS_REF);
  RenCanvasRef *ref = lua_touserdata(L, -1);

  lua_Integer x = luaL_optinteger(L, 2, 0);
  lua_Integer y = luaL_optinteger(L, 3, 0);
  lua_Integer w = luaL_optinteger(L, 4, canvas->w);
  lua_Integer h = luaL_optinteger(L, 5, canvas->h);

  SDL_Surface *dst = SDL_CreateSurface(w, h, SDL_PIXELFORMAT_RGBA32);
  SDL_Rect rect = { .x = x, .y = y, .w = w, .h = h };
  SDL_BlitSurface(ref->surface, &rect, dst, NULL);

  const SDL_PixelFormatDetails *details = SDL_GetPixelFormatDetails(SDL_PIXELFORMAT_RGBA32);
  lua_pushlstring(L, dst->pixels, details->bytes_per_pixel * w * h);

  SDL_DestroySurface(dst);
  return 1;
}


static int f_set_pixels(lua_State *L) {
  RenCanvas *canvas = luaL_checkudata(L, 1, API_TYPE_CANVAS);

  size_t len;
  const char *bytes = luaL_checklstring(L, 2, &len);

  lua_Integer x = luaL_checkinteger(L, 3);
  lua_Integer y = luaL_checkinteger(L, 4);
  lua_Integer w = luaL_checkinteger(L, 5);
  lua_Integer h = luaL_checkinteger(L, 6);
  luaL_argcheck(L, w > 0, 5, "must be a positive non-zero integer");
  luaL_argcheck(L, h > 0, 6, "must be a positive non-zero integer");
  SDL_Rect dst_pos = { .x = x, .y = y, .w = 0, .h = 0 };

  lua_getiuservalue(L, 1, USERDATA_CANVAS_REF);
  RenCanvasRef *ref = lua_touserdata(L, -1);
  ref = cow_if_needed(L, ref);

  const SDL_PixelFormatDetails *details = SDL_GetPixelFormatDetails(SDL_PIXELFORMAT_RGBA32);
  int pitch = ((int)(details->bits_per_pixel+0.5)/8) * w;

  // Dropping const on bytes here is likely fine, as we won't be changing it
  // and the surface will be destroyed by the end of this function
  SDL_Surface *src = SDL_CreateSurfaceFrom(w, h, SDL_PIXELFORMAT_RGBA32, (void *) bytes, pitch);
  SDL_SetSurfaceBlendMode(src, SDL_BLENDMODE_NONE);
  SDL_BlitSurface(src, NULL, ref->surface, &dst_pos);
  canvas->version++;
  SDL_DestroySurface(src);
  return 0;
}


static int f_copy(lua_State *L) {
  // TODO: should we make this COW, so when the copy or the original get changed, we make the actual copy
  RenCanvas *canvas = luaL_checkudata(L, 1, API_TYPE_CANVAS);
  lua_Integer x = luaL_optinteger(L, 2, 0);
  lua_Integer y = luaL_optinteger(L, 3, 0);
  lua_Integer w = luaL_optinteger(L, 4, canvas->w);
  lua_Integer h = luaL_optinteger(L, 5, canvas->h);
  lua_Integer new_w = luaL_optinteger(L, 6, w);
  lua_Integer new_h = luaL_optinteger(L, 7, h);
  const char *mode_str = luaL_optstring(L, 8, "linear");
  SDL_ScaleMode mode = SDL_SCALEMODE_INVALID;
  if (strcmp(mode_str, "nearest") == 0) {
    mode = SDL_SCALEMODE_NEAREST;
  } else if (strcmp(mode_str, "linear") == 0) {
    mode = SDL_SCALEMODE_LINEAR;
  }
  #if 0 // SDL_SCALEMODE_PIXELART doesn't seem to be actually available (as of SDL 3.2.20)
  else if (strcmp(mode_str, "pixelart") == 0) {
    mode = SDL_SCALEMODE_PIXELART;
  }
  #endif

  lua_getiuservalue(L, 1, USERDATA_CANVAS_REF);
  RenCanvasRef *ref = lua_touserdata(L, -1);

  RenCanvas *new_canvas = lua_newuserdatauv(L, sizeof(RenCanvas), USERDATA_LAST - 1);
  luaL_setmetatable(L, API_TYPE_CANVAS);
  new_canvas->w = new_w;
  new_canvas->h = new_h;
  new_canvas->version = 0;

  bool full_surface = (x == 0 && y == 0 && w == canvas->w && h == canvas->h);
  bool scaled = (new_w != w || new_h != h);
  SDL_Surface *surface_copy;
  if (full_surface && !scaled) {
    surface_copy = SDL_DuplicateSurface(ref->surface);
    // DuplicateSurface copies the clip rect, so we reset it
    SDL_SetSurfaceClipRect(surface_copy, NULL);
  } else if (full_surface) {
    surface_copy = SDL_ScaleSurface(ref->surface, new_w, new_h, mode);
  } else {
    surface_copy = SDL_CreateSurface(new_w, new_h, ref->surface->format);
    SDL_Rect src_rect = {.x = x, .y = y, .w = w, .h = h};
    SDL_BlitSurfaceScaled(ref->surface, &src_rect, surface_copy, NULL, mode);
  }

  RenCanvasRef *new_ref = lua_newuserdata(L, sizeof(RenCanvasRef));
  luaL_setmetatable(L, API_TYPE_CANVAS_REF);
  lua_setiuservalue(L, -2, USERDATA_CANVAS_REF);
  new_ref->surface = surface_copy;
  new_ref->render_ref_count = 0;

  return 1;
}


static int f_scaled(lua_State *L) {
  RenCanvas *canvas = luaL_checkudata(L, 1, API_TYPE_CANVAS);
  luaL_checkinteger(L, 2); // new_w
  luaL_checkinteger(L, 3); // new_h
  if (lua_gettop(L) == 3) {
    // Use default scale mode
    lua_pushnil(L);
  }

  lua_pushinteger(L, 0); // x
  lua_pushinteger(L, 0); // y
  lua_pushinteger(L, canvas->w); // w
  lua_pushinteger(L, canvas->h); // h
  lua_rotate(L, 2, -3); // bring new_w, new_h, scale mode at the top of the stack

  return f_copy(L);
}


static int f_set_clip_rect(lua_State *L) {
  luaL_checkudata(L, 1, API_TYPE_CANVAS);
  lua_Integer x = luaL_checkinteger(L, 2);
  lua_Integer y = luaL_checkinteger(L, 3);
  lua_Integer w = luaL_checkinteger(L, 4);
  lua_Integer h = luaL_checkinteger(L, 5);

  lua_getiuservalue(L, 1, USERDATA_CANVAS_REF);
  RenCanvasRef *ref = lua_touserdata(L, -1);

  SDL_Rect rect = { .x = x, .y = y, .w = w, .h = h };
  SDL_SetSurfaceClipRect(ref->surface, &rect);

  return 0;
}


static int f_draw_rect(lua_State *L) {
  RenCanvas *canvas = luaL_checkudata(L, 1, API_TYPE_CANVAS);
  lua_Number x = luaL_checkinteger(L, 2);
  lua_Number y = luaL_checkinteger(L, 3);
  lua_Number w = luaL_checkinteger(L, 4);
  lua_Number h = luaL_checkinteger(L, 5);
  RenColor color = luaXL_checkcolor(L, 6, 255);
  bool replace = luaXL_optboolean(L, 7, false);

  lua_getiuservalue(L, 1, USERDATA_CANVAS_REF);
  RenCanvasRef *ref = lua_touserdata(L, -1);
  ref = cow_if_needed(L, ref);

  RenSurface rs = {
    .scale = 1,
    .surface = ref->surface
  };
  RenRect rect = { .x = x, .y = y, .width = w, .height = h };
  ren_draw_rect(&rs, rect, color, replace);
  canvas->version++;

  return 0;
}


static int f_draw_text(lua_State *L) {
  RenCanvas *canvas = luaL_checkudata(L, 1, API_TYPE_CANVAS);
  RenFont* fonts[FONT_FALLBACK_MAX];
  font_retrieve(L, fonts, 2);
  size_t len;
  const char *text = luaL_checklstring(L, 3, &len);
  double x = luaL_checknumber(L, 4);
  int y = luaL_checkinteger(L, 5);
  RenColor color = luaXL_checkcolor(L, 6, 255);
  RenTab tab = luaXL_checktab(L, 7);

  lua_getiuservalue(L, 1, USERDATA_CANVAS_REF);
  RenCanvasRef *ref = lua_touserdata(L, -1);
  ref = cow_if_needed(L, ref);

  RenSurface rs = {
    .scale = 1,
    .surface = ref->surface
  };
  double end_x = ren_draw_text(&rs, fonts, text, len, x, y, color, tab);
  lua_pushnumber(L, end_x);
  canvas->version++;

  return 1;
}


static int f_draw_canvas(lua_State *L) {
  RenCanvas *canvas_dst = luaL_checkudata(L, 1, API_TYPE_CANVAS);
  RenCanvas *canvas_src = luaL_checkudata(L, 2, API_TYPE_CANVAS);
  
  lua_Integer x = luaL_checkinteger(L, 3);
  lua_Integer y = luaL_checkinteger(L, 4);
  bool blend = luaXL_optboolean(L, 5, true);

  lua_getiuservalue(L, 1, USERDATA_CANVAS_REF);
  RenCanvasRef *ref_dst = lua_touserdata(L, -1);
  ref_dst = cow_if_needed(L, ref_dst);

  lua_getiuservalue(L, 2, USERDATA_CANVAS_REF);
  RenCanvasRef *ref_src = lua_touserdata(L, -1);

  SDL_Rect rect = { .x = x, .y = y, .w = canvas_src->w, .h = canvas_src->h };
  SDL_BlendMode src_mode;
  SDL_GetSurfaceBlendMode(ref_src->surface, &src_mode);
  SDL_SetSurfaceBlendMode(ref_src->surface, blend ? SDL_BLENDMODE_BLEND : SDL_BLENDMODE_NONE);

  SDL_BlitSurface(ref_src->surface, NULL, ref_dst->surface, &rect);

  SDL_SetSurfaceBlendMode(ref_src->surface, src_mode);

  canvas_dst->version++;
  return 0;
}


static int f_ref_gc(lua_State *L) {
  RenCanvasRef* self = luaL_checkudata(L, 1, API_TYPE_CANVAS_REF);
  SDL_DestroySurface(self->surface);
  return 0;
}


static const luaL_Reg canvasLib[] = {
  { "get_pixels",    f_get_pixels    },
  { "set_pixels",    f_set_pixels    },
  { "get_size",      f_get_size      },
  { "copy",          f_copy          },
  { "scaled",        f_scaled        },
  { "set_clip_rect", f_set_clip_rect },
  { "draw_rect",     f_draw_rect     },
  { "draw_text",     f_draw_text     },
  { "draw_canvas",   f_draw_canvas   },
  { NULL,            NULL            }
};

static const luaL_Reg canvasRefLib[] = {
  { "__gc", f_ref_gc },
  { NULL,         NULL         }
};

static const luaL_Reg lib[] = {
  { "new",        f_new        },
  { NULL,         NULL         }
};

int luaopen_canvas(lua_State *L) {
  luaL_newlib(L, lib);

  luaL_newmetatable(L, API_TYPE_CANVAS);
  luaL_setfuncs(L, canvasLib, 0);
  lua_setfield(L, -1, "__index");
  
  luaL_newmetatable(L, API_TYPE_CANVAS_REF);
  luaL_setfuncs(L, canvasRefLib, 0);
  lua_setfield(L, -1, "__index");
  return 1;
}
