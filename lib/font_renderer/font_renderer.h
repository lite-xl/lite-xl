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
    FR_HINTING   = 1 << 0,
    FR_KERNING   = 1 << 2,
    FR_SUBPIXEL  = 1 << 3,
};

typedef struct {
    uint8_t r, g, b;
} FR_Color;

typedef struct {
  int left, top, right, bottom;
} FR_Clip_Area;

FontRenderer *  FR_New(unsigned int flags, float gamma);
void            FR_Free(FontRenderer *);
FR_Bitmap*      FR_Bitmap_New(FontRenderer *, int width, int height);
int             FR_Load_Font(FontRenderer *, const char *filename);
int             FR_Get_Font_Height(FontRenderer *, float size);
int             FR_Bake_Font_Bitmap(FontRenderer *, int font_height,
                    FR_Bitmap *image,
                    int first_char, int num_chars, FR_Bitmap_Glyph_Metrics *glyph_info);
void            FR_Blend_Glyph(FontRenderer *font_renderer,
                    FR_Clip_Area *clip, int x, int y,
                    uint8_t *dst, int dst_width,
                    const FR_Bitmap *glyphs_bitmap,
                    const FR_Bitmap_Glyph_Metrics *glyph, FR_Color color);

void FR_Bitmap_Free(FR_Bitmap *image);

#ifdef __cplusplus
}
#endif

#endif
