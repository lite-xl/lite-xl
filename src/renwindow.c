#include <assert.h>
#include <stdio.h>
#include "renwindow.h"

#ifdef LITE_USE_SDL_RENDERER
static int query_surface_scale(RenWindow *ren) {
  int w_pixels, h_pixels;
  int w_points, h_points;
  SDL_GL_GetDrawableSize(ren->window, &w_pixels, &h_pixels);
  SDL_GetWindowSize(ren->window, &w_points, &h_points);
  /* We consider that the ratio pixel/point will always be an integer and
     it is the same along the x and the y axis. */
  assert(w_pixels % w_points == 0 && h_pixels % h_points == 0 && w_pixels / w_points == h_pixels / h_points);
  return w_pixels / w_points;
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
  ren->rensurface.scale = query_surface_scale(ren);
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

void renwin_init_command_buf(RenWindow *ren) {
  ren->command_buf = NULL;
  ren->command_buf_idx = 0;
  ren->command_buf_size = 0;
}


static RenRect scaled_rect(const RenRect rect, const int scale) {
  return (RenRect) {rect.x * scale, rect.y * scale, rect.width * scale, rect.height * scale};
}


void renwin_clip_to_surface(RenWindow *ren) {
  SDL_SetClipRect(renwin_get_surface(ren).surface, NULL);
}


void renwin_set_clip_rect(RenWindow *ren, RenRect rect) {
  RenSurface rs = renwin_get_surface(ren);
  RenRect sr = scaled_rect(rect, rs.scale);
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
  return (RenSurface){.surface = surface, .scale = 1};
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
  const int scale = ren->rensurface.scale;
  for (int i = 0; i < count; i++) {
    const RenRect *r = &rects[i];
    const int x = scale * r->x, y = scale * r->y;
    const int w = scale * r->width, h = scale * r->height;
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
  SDL_DestroyWindow(ren->window);
  ren->window = NULL;
#ifdef LITE_USE_SDL_RENDERER
  SDL_DestroyTexture(ren->texture);
  SDL_DestroyRenderer(ren->renderer);
  SDL_FreeSurface(ren->rensurface.surface);
#endif
}
