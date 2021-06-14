#ifndef RENDERER_H
#define RENDERER_H

#include <SDL.h>
#include <stdint.h>
#include "fontdesc.h"

typedef struct RenImage RenImage;

enum {
  RenFontAntialiasingMask = 1,
  RenFontGrayscale        = 1,
  RenFontSubpixel         = 0,

  RenFontHintingMask   = 3 << 1,
  RenFontHintingSlight = 0 << 1,
  RenFontHintingNone   = 1 << 1,
  RenFontHintingFull   = 2 << 1,
};

typedef struct { uint8_t b, g, r, a; } RenColor;
typedef struct { int x, y, width, height; } RenRect;

// FIXME: ensure this Max is okay or use dynamic allocation.
#define TEXTURE_REVS_MAX 256
struct RenTexture {
  SDL_Surface *surface;
  int surface_scale;
  RenRect clip; /* Clipping rect in pixel coordinates. */
  int revisions[TEXTURE_REVS_MAX];
};
typedef struct RenTexture RenTexture;

enum { SurfaceTexture, SurfaceWindow };

typedef struct {
  int type; /* Type of surface, RenSurfaceTexture or RenSurfaceWindow. */
  void *data; /* Can be a RenTexture or RenWindow pointer based on type. */
} RenSurface;

struct CPReplace {
  unsigned codepoint_src;
  unsigned codepoint_dst;
};
typedef struct CPReplace CPReplace;


struct CPReplaceTable {
  int size;
  CPReplace *replacements;
};
typedef struct CPReplaceTable CPReplaceTable;

void ren_init(SDL_Window *win);
void ren_resize_window();
void ren_free_window_resources();

void ren_update_rects(RenSurface *ren, RenRect *rects, int count);
void ren_set_clip_rect(RenSurface *ren, RenRect rect);
void ren_get_size(RenSurface *ren, int *x, int *y); /* Reports the size in points. */

RenImage* ren_new_image(int width, int height);
void ren_free_image(RenImage *image);

RenFont* ren_load_font(const char *filename, float size, unsigned int renderer_flags);
int ren_verify_font(const char *filename);
void ren_free_font(RenFont *font);
void ren_set_font_tab_size(RenFont *font, int n);
int ren_get_font_tab_size(RenFont *font);

int ren_get_font_width(RenSurface *ren, FontDesc *font_desc, const char *text, int *subpixel_scale);
int ren_get_font_height(RenSurface *ren, FontDesc *font_desc);
int ren_get_font_subpixel_scale(RenSurface *ren, FontDesc *font_desc);
int ren_font_subpixel_round(int width, int subpixel_scale, int orientation);

void ren_draw_rect(RenSurface *ren, RenRect rect, RenColor color);
void ren_draw_text(RenSurface *ren, FontDesc *font_desc, const char *text, int x, int y, RenColor color, CPReplaceTable *replacements, RenColor replace_color);
void ren_draw_text_subpixel(RenSurface *ren, FontDesc *font_desc, const char *text, int x_subpixel, int y, RenColor color, CPReplaceTable *replacements, RenColor replace_color);
void ren_draw_image(RenSurface *ren, uint32_t image_id, int image_x, int image_y, RenRect rect);

void ren_cp_replace_init(CPReplaceTable *rep_table);
void ren_cp_replace_free(CPReplaceTable *rep_table);
void ren_cp_replace_add(CPReplaceTable *rep_table, const char *src, const char *dst);
void ren_cp_replace_clear(CPReplaceTable *rep_table);

extern RenSurface window_ren_surface[1];

#endif
