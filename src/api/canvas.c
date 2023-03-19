#include "api.h"
#include "../renderer.h"
#include "lua.h"

static int f_get_size(lua_State *L) {
  RenCanvas* canvas = (RenCanvas*) luaL_checkudata(L, 1, API_TYPE_CANVAS);
  SDL_Surface *s = canvas->rensurface.surface;
  lua_pushinteger(L, s ? s->w : 0);
  lua_pushinteger(L, s ? s->h : 0);
  return 2;
}

static void checkmask(lua_State *L, int idx, uint32_t *rmask, uint32_t *gmask, uint32_t *bmask, uint32_t *amask, int *bpp) {
  if (lua_isnoneornil(L, idx)) {
    // RGBA8888 by default
    SDL_PixelFormatEnumToMasks(SDL_PIXELFORMAT_RGBA8888, bpp, rmask, gmask, bmask, amask);
    return;
  }
  luaL_checktype(L, idx, LUA_TTABLE);

  #define GET_FIELD_INTEGER(field, output) do {\
    lua_getfield(L, idx, (field));\
    if (!lua_isinteger(L, -1)) {\
      luaL_error(L, "error in pixel format mask (%s)", (field));\
      return;\
    }\
    *(output) = lua_tointeger(L, -1);\
    lua_pop(L, 1);\
  } while (0);

  GET_FIELD_INTEGER("r_mask", rmask);
  GET_FIELD_INTEGER("g_mask", gmask);
  GET_FIELD_INTEGER("b_mask", bmask);
  GET_FIELD_INTEGER("a_mask", amask);
  GET_FIELD_INTEGER("bpp", bpp);
  #undef GET_FIELD_INTEGER

  return;
}

static int f_set_pixels(lua_State *L) {
  RenCanvas* canvas = (RenCanvas*) luaL_checkudata(L, 1, API_TYPE_CANVAS);
  size_t len;
  const char *bytes = luaL_checklstring(L, 2, &len);
  lua_Integer x = luaL_checkinteger(L, 3);
  lua_Integer y = luaL_checkinteger(L, 4);
  lua_Integer w = luaL_checkinteger(L, 5);
  lua_Integer h = luaL_checkinteger(L, 6);
  w = w < 0 ? 0 : w;
  h = h < 0 ? 0 : h;

  uint32_t rmask, gmask, bmask, amask;
  int bpp;
  checkmask(L, 7, &rmask, &gmask, &bmask, &amask, &bpp);
  uint32_t format = SDL_MasksToPixelFormatEnum(bpp, rmask, gmask, bmask, amask);
  if (format == SDL_PIXELFORMAT_UNKNOWN) {
    return luaL_error(L, "error in set_pixels options, invalid pixel format");
  }
  if (w*h*((int)(bpp+0.5)/8) != len) {
    return luaL_error(L, "error in set_pixels options, data size does not match expected pixel size");
  }

  if (w <= 0 || h <= 0 || x + w < 0 || y + h < 0) {
    return 0;
  }

  int pitch = ((int)(bpp+0.5)/8) * w;
  SDL_Surface *s = SDL_CreateRGBSurfaceWithFormatFrom((void *)bytes, w, h, bpp, pitch, format);
  if (!s) {
    return luaL_error(L, "error while reading pixel data: %s", SDL_GetError());
  }

  // Use a temporary SDL_Surface to blit the pixels on top of the canvas.
  // This makes use of SDL internals to convert between pixel formats if needed.
  RenSurface temp_surface = {.surface = s, .scale = 1};
  ren_draw_surface(&canvas->rensurface, &temp_surface, (RenRect){ x, y, w, h }, (RenRect){ 0, 0, w, h }, false);
  SDL_FreeSurface(s);
  canvas->change_counter++;
  return 0;
}

static int f_gc(lua_State *L) {
  RenCanvas* canvas = (RenCanvas*) luaL_checkudata(L, 1, API_TYPE_CANVAS);
  SDL_FreeSurface(canvas->rensurface.surface);
  return 0;
}

static const luaL_Reg lib[] = {
  { "get_size",   f_get_size   },
  { "set_pixels", f_set_pixels },
  { "__gc",       f_gc         },
  { NULL,         NULL         }
};

int luaopen_canvas(lua_State *L) {
  luaL_newmetatable(L, API_TYPE_CANVAS);
  luaL_setfuncs(L, lib, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");

  #define PUSH_PIXEL_FORMAT_TABLE(format) do {\
    int bpp;\
    uint32_t r, g, b, a;\
    SDL_PixelFormatEnumToMasks((SDL_##format), &bpp, &r, &g, &b, &a);\
    lua_newtable(L);\
    lua_pushinteger(L, bpp);\
    lua_setfield(L, -2, "bpp");\
    lua_pushinteger(L, r);\
    lua_setfield(L, -2, "r_mask");\
    lua_pushinteger(L, g);\
    lua_setfield(L, -2, "g_mask");\
    lua_pushinteger(L, b);\
    lua_setfield(L, -2, "b_mask");\
    lua_pushinteger(L, a);\
    lua_setfield(L, -2, "a_mask");\
    lua_setfield(L, -2, #format);\
  } while(0);
  
  PUSH_PIXEL_FORMAT_TABLE(PIXELFORMAT_RGB888);
  PUSH_PIXEL_FORMAT_TABLE(PIXELFORMAT_RGBA8888);
  PUSH_PIXEL_FORMAT_TABLE(PIXELFORMAT_RGB24);
  #undef PUSH_PIXEL_FORMAT_TABLE

  return 1;
}
