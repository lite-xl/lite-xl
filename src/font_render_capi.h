#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#include "renderer.h"

struct FontRenderer_;
typedef struct FontRenderer_ FontRenderer;

enum {
    FONT_RENDERER_HINTING  = 1 << 0,
    FONT_RENDERER_KERNING  = 1 << 1,
    FONT_RENDERER_SUBPIXEL = 1 << 2,

    FONT_RENDERER_DEFAULT = FONT_RENDERER_HINTING | FONT_RENDERER_KERNING | FONT_RENDERER_SUBPIXEL,
};

FontRenderer *FontRendererNew(unsigned int flags, float gamma);
int FontRendererLoadFont(FontRenderer *, const char *filename);
int FontRendererDrawText(FontRenderer *fr_, RenColor *pixels, int width, int height, int pitch, const char *text, float text_size, int x, int y, RenColor color);

#ifdef __cplusplus
}
#endif
