#include <assert.h>
#include <stdio.h>
#include "renwindow.h"

#ifdef LITE_USE_SDL_RENDERER
static void update_surface_scale(RenWindow *ren) {
  int w_pixels, h_pixels;
  int w_points, h_points;
  SDL_GL_GetDrawableSize(ren->window, &w_pixels, &h_pixels);
  SDL_GetWindowSize(ren->window, &w_points, &h_points);
  double scaleX = (double) w_pixels / (double) w_points;
  double scaleY = (double) h_pixels / (double) h_points;
  ren->rensurface.scale_x = round(scaleX * 100) / 100;
  ren->rensurface.scale_y = round(scaleY * 100) / 100;
}

static void setup_renderer(RenWindow *ren, int w, int h) {
  /* Note that w and h here should always be in pixels and obtained from
     a call to SDL_GL_GetDrawableSize(). */
  if (!ren->renderer) {
    ren->renderer = SDL_CreateRenderer(ren->window, -1, 0);
  }
  if (ren->texture) {
    SDL_DestroyTexture(ren->texture);
  }
  ren->texture = SDL_CreateTexture(ren->renderer, SDL_PIXELFORMAT_BGRA32, SDL_TEXTUREACCESS_STREAMING, w, h);
  update_surface_scale(ren);
}
#endif


void renwin_init_surface(UNUSED RenWindow *ren) {
#ifdef LITE_USE_SDL_RENDERER
  if (ren->rensurface.surface) {
    SDL_FreeSurface(ren->rensurface.surface);
  }
  int w, h;
  SDL_GL_GetDrawableSize(ren->window, &w, &h);
  ren->rensurface.surface = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_BGRA32);
  if (!ren->rensurface.surface) {
    fprintf(stderr, "Error creating surface: %s", SDL_GetError());
    exit(1);
  }
  setup_renderer(ren, w, h);
#endif
}


static RenRect scaled_rect(const RenRect rect, const RenSurface *rs) {
#ifdef LITE_USE_SDL_RENDERER
  double scale_x = rs->scale_x;
  double scale_y = rs->scale_y;
#else
  int scale_x = 1;
  int scale_y = 1;
#endif
  return (RenRect) {
    rect.x * scale_x,
    rect.y * scale_y,
    rect.width * scale_x,
    rect.height * scale_y
  };
}


void renwin_clip_to_surface(RenWindow *ren) {
  SDL_SetClipRect(renwin_get_surface(ren).surface, NULL);
}


void renwin_set_clip_rect(RenWindow *ren, RenRect rect) {
  RenSurface rs = renwin_get_surface(ren);
  RenRect sr = scaled_rect(rect, &rs);
  SDL_SetClipRect(rs.surface, &(SDL_Rect){.x = sr.x, .y = sr.y, .w = sr.width, .h = sr.height});
}


RenSurface renwin_get_surface(RenWindow *ren) {
#ifdef LITE_USE_SDL_RENDERER
  return ren->rensurface;
#else
  SDL_Surface *surface = SDL_GetWindowSurface(ren->window);
  if (!surface) {
    fprintf(stderr, "Error getting window surface: %s", SDL_GetError());
    exit(1);
  }
  return (RenSurface){.surface = surface, .scale_x = 1, .scale_y = 1};
#endif
}

void renwin_resize_surface(UNUSED RenWindow *ren) {
#ifdef LITE_USE_SDL_RENDERER
  int new_w, new_h;
  SDL_GL_GetDrawableSize(ren->window, &new_w, &new_h);
  /* Note that (w, h) may differ from (new_w, new_h) on retina displays. */
  if (new_w != ren->rensurface.surface->w || new_h != ren->rensurface.surface->h) {
    renwin_init_surface(ren);
    renwin_clip_to_surface(ren);
    setup_renderer(ren, new_w, new_h);
  }
#endif
}

void renwin_show_window(RenWindow *ren) {
  SDL_ShowWindow(ren->window);
}

void renwin_update_rects(RenWindow *ren, RenRect *rects, int count) {
#ifdef LITE_USE_SDL_RENDERER
  const double scale_x = ren->rensurface.scale_x;
  const double scale_y = ren->rensurface.scale_y;
  for (int i = 0; i < count; i++) {
    const RenRect *r = &rects[i];
    const int x = scale_x * r->x, y = scale_y * r->y;
    const int w = scale_x * r->width, h = scale_y * r->height;
    const SDL_Rect sr = {.x = x, .y = y, .w = w, .h = h};
    int32_t *pixels = ((int32_t *) ren->rensurface.surface->pixels) + x + ren->rensurface.surface->w * y;
    SDL_UpdateTexture(ren->texture, &sr, pixels, ren->rensurface.surface->w * 4);
  }
  SDL_RenderCopy(ren->renderer, ren->texture, NULL, NULL);
  SDL_RenderPresent(ren->renderer);
#else
  SDL_UpdateWindowSurfaceRects(ren->window, (SDL_Rect*) rects, count);
#endif
}

void renwin_free(RenWindow *ren) {
#ifdef LITE_USE_SDL_RENDERER
  SDL_DestroyTexture(ren->texture);
  SDL_DestroyRenderer(ren->renderer);
  SDL_FreeSurface(ren->rensurface.surface);
#endif
  SDL_DestroyWindow(ren->window);
  ren->window = NULL;
}
