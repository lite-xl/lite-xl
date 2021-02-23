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

#ifdef __cplusplus
class FR_Renderer;
#else
struct FR_Renderer;
typedef struct FR_Renderer FR_Renderer;
#endif

enum {
    FR_HINTING    = 1 << 0,
    FR_KERNING    = 1 << 1,
    FR_SUBPIXEL   = 1 << 2,
    FR_PRESCALE_X = 1 << 3,
};

typedef struct {
    uint8_t r, g, b;
} FR_Color;

typedef struct {
  int left, top, right, bottom;
} FR_Clip_Area;

FR_Renderer *   FR_Renderer_New(unsigned int flags);
void            FR_Renderer_Free(FR_Renderer *);
int             FR_Load_Font(FR_Renderer *, const char *filename);
FR_Bitmap*      FR_Bitmap_New(FR_Renderer *, int width, int height);
void            FR_Bitmap_Free(FR_Bitmap *image);
int             FR_Get_Font_Height(FR_Renderer *, float size);
FR_Bitmap *     FR_Bake_Font_Bitmap(FR_Renderer *, int font_height,
                    int first_char, int num_chars, FR_Bitmap_Glyph_Metrics *glyph_info);
void            FR_Blend_Glyph(FR_Renderer *font_renderer,
                    FR_Clip_Area *clip, int x, int y,
                    uint8_t *dst, int dst_width,
                    const FR_Bitmap *glyphs_bitmap,
                    const FR_Bitmap_Glyph_Metrics *glyph, FR_Color color);

#ifdef __cplusplus
}
#endif

#endif
