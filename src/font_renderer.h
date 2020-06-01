#ifndef FONT_RENDERER_H
#define FONT_RENDERER_H

#ifdef __cplusplus
extern "C" {
#endif

// Mirrors stbtt_bakedchar.
struct GlyphBitmapInfo_ {
  unsigned short x0, y0, x1, y1;
  float xoff, yoff, xadvance;
};
typedef struct GlyphBitmapInfo_ GlyphBitmapInfo;

struct FontRenderer_;
typedef struct FontRenderer_ FontRenderer;

enum {
    FONT_RENDERER_HINTING  = 1 << 0,
    FONT_RENDERER_KERNING  = 1 << 1,
};

FontRenderer *FontRendererNew(unsigned int flags);
int FontRendererLoadFont(FontRenderer *, const char *filename);
int FontRendererGetFontHeight(FontRenderer *, float size);
int FontRendererBakeFontBitmap(FontRenderer *, int font_height,
    void *pixels, int pixels_width, int pixels_height,
    int first_char, int num_chars, GlyphBitmapInfo *glyph_info); 

#ifdef __cplusplus
}
#endif

#endif
