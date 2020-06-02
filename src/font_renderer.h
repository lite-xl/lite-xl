#ifndef FONT_RENDERER_H
#define FONT_RENDERER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Mirrors stbtt_bakedchar.
typedef struct {
  unsigned short x0, y0, x1, y1;
  float xoff, yoff, xadvance;
} GlyphBitmapInfo;

struct FontRenderer_;
typedef struct FontRenderer_ FontRenderer;

enum {
    FONT_RENDERER_HINTING  = 1 << 0,
    FONT_RENDERER_KERNING  = 1 << 1,
};

typedef struct {
    uint8_t r, g, b;
} FontRendererColor;

FontRenderer *  FontRendererNew(unsigned int flags);

void            FontRendererFree(FontRenderer *);

int             FontRendererLoadFont(FontRenderer *, const char *filename);

int             FontRendererGetFontHeight(FontRenderer *, float size);

int             FontRendererBakeFontBitmap(FontRenderer *, int font_height,
                    void *pixels, int pixels_width, int pixels_height,
                    int first_char, int num_chars, GlyphBitmapInfo *glyph_info); 

void            FontRendererBlendGamma(uint8_t *dst, int dst_stride,
                    uint8_t *src, int src_stride,
                    int region_width, int region_height,
                    FontRendererColor color);

#ifdef __cplusplus
}
#endif

#endif
