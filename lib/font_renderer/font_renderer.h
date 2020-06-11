#ifndef FONT_RENDERER_H
#define FONT_RENDERER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  unsigned short x0, y0, x1, y1;
  float xoff, yoff, xadvance;
} FR_Bitmap_Glyph_Metrics;

typedef struct FR_Bitmap FR_Bitmap;

struct FR_Impl;
typedef struct FR_Impl FontRenderer;

enum {
    FONT_RENDERER_HINTING  = 1 << 0,
    FONT_RENDERER_KERNING  = 1 << 1,
    FONT_RENDERER_SUBPIXEL = 1 << 2,
};

typedef struct {
    uint8_t r, g, b;
} FR_Color;

typedef struct {
  int left, top, right, bottom;
} FR_Clip_Area;

FontRenderer *  FR_New(unsigned int flags, float gamma);

void            FR_Free(FontRenderer *);

int             FR_Load_Font(FontRenderer *, const char *filename);

int             FR_Get_Font_Height(FontRenderer *, float size);

int             FR_Bake_Font_Bitmap(FontRenderer *, int font_height,
                    FR_Bitmap *image,
                    int first_char, int num_chars, FR_Bitmap_Glyph_Metrics *glyph_info,
                    int subpixel_scale);

#if 0
// FIXME: this function needs to be updated to match BlendGammaSubpixel.
void            FR_Blend_Gamma(FontRenderer *,
                    uint8_t *dst, int dst_stride,
                    uint8_t *src, int src_stride,
                    int region_width, int region_height,
                    FR_Color color);
#endif

void            FR_Blend_Gamma_Subpixel(FontRenderer *font_renderer,
                    FR_Clip_Area *clip, int x, int y,
                    uint8_t *dst, int dst_width,
                    const FR_Bitmap *glyphs_bitmap,
                    const FR_Bitmap_Glyph_Metrics *glyph, FR_Color color);

FR_Bitmap* FR_Bitmap_New(int width, int height, int subpixel_scale);

void FR_Bitmap_Free(FR_Bitmap *image);

#ifdef __cplusplus
}
#endif

#endif
