#ifndef FONT_RENDERER_H
#define FONT_RENDERER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
  unsigned short x0, y0, x1, y1;
  float xoff, yoff, xadvance;
} GlyphBitmapInfo;

// Important: when a subpixel scale is used the width below will be the width in logical pixel.
// As each logical pixel contains 3 subpixels it means that the 'pixels' pointer
// will hold enough space for '3 * width' uint8_t values.
typedef struct {
  uint8_t *pixels;
  int width, height;
} FontRendererBitmap;

struct FontRendererImpl;
typedef struct FontRendererImpl FontRenderer;

enum {
    FONT_RENDERER_HINTING  = 1 << 0,
    FONT_RENDERER_KERNING  = 1 << 1,
    FONT_RENDERER_SUBPIXEL = 1 << 2,
};

typedef struct {
    uint8_t r, g, b;
} FontRendererColor;

typedef struct {
  int left, top, right, bottom;
} FontRendererClipArea;

FontRenderer *  FontRendererNew(unsigned int flags, float gamma);

void            FontRendererFree(FontRenderer *);

int             FontRendererLoadFont(FontRenderer *, const char *filename);

int             FontRendererGetFontHeight(FontRenderer *, float size);

int             FontRendererBakeFontBitmap(FontRenderer *, int font_height,
                    void *pixels, int pixels_width, int pixels_height,
                    int first_char, int num_chars, GlyphBitmapInfo *glyph_info,
                    int subpixel_scale);

#if 0
// FIXME: this function needs to be updated to match BlendGammaSubpixel.
void            FontRendererBlendGamma(FontRenderer *,
                    uint8_t *dst, int dst_stride,
                    uint8_t *src, int src_stride,
                    int region_width, int region_height,
                    FontRendererColor color);
#endif

void            FontRendererBlendGammaSubpixel(FontRenderer *font_renderer,
                    FontRendererClipArea *clip, int x, int y,
                    uint8_t *dst, int dst_width,
                    const FontRendererBitmap *glyphs_bitmap,
                    const GlyphBitmapInfo *glyph, FontRendererColor color);

#ifdef __cplusplus
}
#endif

#endif
