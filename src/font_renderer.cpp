#include "font_renderer.h"

#include "font_renderer_alpha.h"

FontRenderer *FontRendererNew(unsigned int flags) {
    bool hinting = ((flags & FONT_RENDERER_HINTING) != 0);
    bool kerning = ((flags & FONT_RENDERER_KERNING) != 0);
    font_renderer_alpha *font_renderer = new font_renderer_alpha(hinting, kerning);
    return (FontRenderer *) font_renderer;
}

void FontRendererFree(FontRenderer *fr_) {
    font_renderer_alpha *font_renderer = (font_renderer_alpha *) fr_;
    delete font_renderer;    
}

int FontRendererLoadFont(FontRenderer *fr_, const char *filename) {
    font_renderer_alpha *font_renderer = (font_renderer_alpha *) fr_;
    bool success = font_renderer->load_font(filename);
    return (success ? 0 : 1);
}

int FontRendererGetFontHeight(FontRenderer *fr_, float size) {
    font_renderer_alpha *font_renderer = (font_renderer_alpha *) fr_;
    double ascender, descender;
    font_renderer->get_font_vmetrics(ascender, descender);
    int face_height = font_renderer->get_face_height();

    float scale = font_renderer->scale_for_em_to_pixels(size);
    return int((ascender - descender) * face_height * scale + 0.5);
}

int FontRendererBakeFontBitmap(FontRenderer *fr_, int font_height,
    void *pixels, int pixels_width, int pixels_height,
    int first_char, int num_chars, GlyphBitmapInfo *glyphs)
{
    font_renderer_alpha *font_renderer = (font_renderer_alpha *) fr_;

    const int pixel_size = 1;
    memset(pixels, 0x00, pixels_width * pixels_height * pixel_size);

    double ascender, descender;
    font_renderer->get_font_vmetrics(ascender, descender);

    const int ascender_px  = int(ascender  * font_height + 0.5);
    const int descender_px = int(descender * font_height + 0.5);

    const int pad_y = font_height * 2 / 10;
    const int y_step = font_height + 2 * pad_y;

    agg::rendering_buffer ren_buf((agg::int8u *) pixels, pixels_width, pixels_height, -pixels_width * pixel_size);
    int x = 0, y = pixels_height;
    int res = 0;
    const agg::alpha8 text_color(0xff);
    for (int i = 0; i < num_chars; i++) {
        int codepoint = first_char + i;
        if (x + font_height > pixels_width) {
            x = 0;
            y -= y_step;
        }
        if (y - font_height - 2 * pad_y < 0) {
            res = -1;
            break;
        }
        const int y_baseline = y - pad_y - font_height;

        double x_next = x, y_next = y_baseline;
        font_renderer->render_codepoint(ren_buf, font_height, text_color, x_next, y_next, codepoint);
        int x_next_i = int(x_next + 0.5);
        GlyphBitmapInfo& glyph_info = glyphs[i];
        glyph_info.x0 = x;
        glyph_info.y0 = pixels_height - (y_baseline + ascender_px  + pad_y);
        glyph_info.x1 = x_next_i;
        glyph_info.y1 = pixels_height - (y_baseline + descender_px - pad_y);
        glyph_info.xoff = 0;
        glyph_info.yoff = -pad_y;
        glyph_info.xadvance = x_next - x;
#if 0
        fprintf(stderr,
            "glyph codepoint %3d (ascii: %1c), BOX (%3d, %3d) (%3d, %3d), "
            "OFFSET (%.5g, %.5g), X ADVANCE %.5g\n",
            codepoint, i,
            glyph_info.x0, glyph_info.y0, glyph_info.x1, glyph_info.y1,
            glyph_info.xoff, glyph_info.yoff, glyph_info.xadvance);
#endif
        x = x_next_i;
    }
    return res;
}
