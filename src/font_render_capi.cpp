#include "font_render_capi.h"

#include "font_render_lcd.h"

FontRenderer *FontRendererNew(unsigned int flags, float gamma) {
    bool hinting  = ((flags&FONT_RENDERER_HINTING)  != 0);
    bool kerning  = ((flags&FONT_RENDERER_KERNING)  != 0);
    bool subpixel = ((flags&FONT_RENDERER_SUBPIXEL) != 0);
    font_renderer_lcd *font_renderer = new font_renderer_lcd(hinting, kerning, subpixel, (double) gamma);
    return (FontRenderer *) font_renderer;
}

int FontRendererLoadFont(FontRenderer *fr_, const char *filename) {
    font_renderer_lcd *font_renderer = (font_renderer_lcd *) fr_;
    bool success = font_renderer->load_font(filename);
    return (success ? 0 : 1);
}

int FontRendererDrawText(FontRenderer *fr_, RenColor *pixels, int width, int height, int pitch, const char *text, float text_size, int x, int y, RenColor color) {
    // FIXME: it works below as long as font_renderer_lcd use a BGRA32 pixel format
    font_renderer_lcd *font_renderer = (font_renderer_lcd *) fr_;
    agg::rendering_buffer ren_buf((agg::int8u *) pixels, width, height, -pitch);
    const agg::rgba8 agg_color(color.r, color.g, color.b);
    double new_x = font_renderer->render_text(ren_buf, (double) text_size, agg_color, (double) x, (double) (height - y), text);
    return int(new_x);
}
