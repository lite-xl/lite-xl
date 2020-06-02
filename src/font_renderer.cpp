#include "font_renderer.h"

#include "agg_pixfmt_rgb.h"
#include "agg_pixfmt_rgba.h"
#include "agg_gamma_lut.h"

#include "font_renderer_alpha.h"

typedef agg::blender_rgb_gamma<agg::rgba8, agg::order_bgra, agg::gamma_lut<> > blender_gamma_type;

class FontRendererImpl {
public:
    FontRendererImpl(bool hinting, bool kerning, float gamma_value) :
        m_renderer(hinting, kerning),
        m_gamma_lut(double(gamma_value)),
        m_blender()
    {
        m_blender.gamma(m_gamma_lut);
    }

    font_renderer_alpha& renderer_alpha() { return m_renderer; }
    blender_gamma_type& blender() { return m_blender; }

private:
    font_renderer_alpha m_renderer;
    agg::gamma_lut<> m_gamma_lut;
    blender_gamma_type m_blender;
};

FontRenderer *FontRendererNew(unsigned int flags, float gamma) {
    bool hinting = ((flags & FONT_RENDERER_HINTING) != 0);
    bool kerning = ((flags & FONT_RENDERER_KERNING) != 0);
    return new FontRendererImpl(hinting, kerning, gamma);
}

void FontRendererFree(FontRenderer *font_renderer) {
    delete font_renderer;    
}

int FontRendererLoadFont(FontRenderer *font_renderer, const char *filename) {
    bool success = font_renderer->renderer_alpha().load_font(filename);
    return (success ? 0 : 1);
}

int FontRendererGetFontHeight(FontRenderer *font_renderer, float size) {
    font_renderer_alpha& renderer_alpha = font_renderer->renderer_alpha();
    double ascender, descender;
    renderer_alpha.get_font_vmetrics(ascender, descender);
    int face_height = renderer_alpha.get_face_height();
    float scale = renderer_alpha.scale_for_em_to_pixels(size);
    return int((ascender - descender) * face_height * scale + 0.5);
}

static void glyph_trim_rect(agg::rendering_buffer& ren_buf, GlyphBitmapInfo *gli) {
    const int height = ren_buf.height();
    int x0 = gli->x0, y0 = gli->y0, x1 = gli->x1, y1 = gli->y1;
    for (int y = gli->y0; y < gli->y1; y++) {
        uint8_t *row = ren_buf.row_ptr(height - 1 - y);
        unsigned int row_bitsum = 0;
        for (int x = x0; x < x1; x++) {
            row_bitsum |= row[x];
        }
        if (row_bitsum == 0) {
            y0++;
        } else {
            break;
        }
    }
    for (int y = gli->y1 - 1; y >= gli->y0; y--) {
        uint8_t *row = ren_buf.row_ptr(height - 1 - y);
        unsigned int row_bitsum = 0;
        for (int x = x0; x < x1; x++) {
            row_bitsum |= row[x];
        }
        if (row_bitsum == 0) {
            y1--;
        } else {
            break;
        }
    }
    int xtriml = x0, xtrimr = x1;
    for (int y = y0; y < y1; y++) {
        uint8_t *row = ren_buf.row_ptr(height - 1 - y);
        for (int x = x0; x < x1; x++) {
            if (row[x]) {
                if (x < xtriml) xtriml = x;
                break;
            }
        }
        for (int x = x1 - 1; x >= x0; x--) {
            if (row[x]) {
                if (x > xtrimr) xtrimr = x + 1;
                break;
            }
        }
    }
    gli->xoff += (xtriml - x0);
    gli->yoff += (y0 - gli->y0);
    gli->x0 = xtriml;
    gli->y0 = y0;
    gli->x1 = xtrimr;
    gli->y1 = y1;
}

int FontRendererBakeFontBitmap(FontRenderer *font_renderer, int font_height,
    void *pixels, int pixels_width, int pixels_height,
    int first_char, int num_chars, GlyphBitmapInfo *glyphs)
{
    font_renderer_alpha& renderer_alpha = font_renderer->renderer_alpha();

    const int pixel_size = 1;
    memset(pixels, 0x00, pixels_width * pixels_height * pixel_size);

    double ascender, descender;
    renderer_alpha.get_font_vmetrics(ascender, descender);

    const int ascender_px  = int(ascender  * font_height + 0.5);
    const int descender_px = int(descender * font_height + 0.5);

    const int pad_y = font_height / 10, pad_x = 1;
    const int y_step = font_height + 2 * pad_y;

    agg::rendering_buffer ren_buf((agg::int8u *) pixels, pixels_width, pixels_height, -pixels_width * pixel_size);
    int x = 0, y = pixels_height;
    int res = 0;
    const agg::alpha8 text_color(0xff);
#ifdef FONT_RENDERER_HEIGHT_HACK
    const int font_height_reduced = (font_height * 86) / 100;
#else
    const int font_height_reduced = font_height;
#endif
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
        renderer_alpha.render_codepoint(ren_buf, font_height_reduced, text_color, x_next, y_next, codepoint);
        int x_next_i = int(x_next + 1.0);

        GlyphBitmapInfo& glyph_info = glyphs[i];
        glyph_info.x0 = x;
        glyph_info.y0 = pixels_height - (y_baseline + ascender_px  + pad_y);
        glyph_info.x1 = x_next_i;
        glyph_info.y1 = pixels_height - (y_baseline + descender_px - pad_y);

        glyph_info.xoff = 0;
        glyph_info.yoff = -pad_y;
        glyph_info.xadvance = x_next - x;

        glyph_trim_rect(ren_buf, &glyph_info);

        x = x_next_i + pad_x;

#ifdef FONT_RENDERER_DEBUG
        fprintf(stderr,
          "glyph codepoint %3d (ascii: %1c), BOX (%3d, %3d) (%3d, %3d), "
          "OFFSET (%.5g, %.5g), X ADVANCE %.5g\n",
          codepoint, i,
          glyph_info.x0, glyph_info.y0, glyph_info.x1, glyph_info.y1,
          glyph_info.xoff, glyph_info.yoff, glyph_info.xadvance);
#endif
    }
    return res;
}

template <typename Blender>
void blend_solid_hspan(agg::rendering_buffer& rbuf, Blender& blender,
                        int x, int y, unsigned len,
                        const typename Blender::color_type& c, const agg::int8u* covers)
{
    typedef Blender  blender_type;
    typedef typename blender_type::color_type color_type;
    typedef typename blender_type::order_type order_type;
    typedef typename color_type::value_type value_type;
    typedef typename color_type::calc_type calc_type;

    if (c.a)
    {
        value_type* p = (value_type*)rbuf.row_ptr(x, y, len) + (x << 2);
        do 
        {
            calc_type alpha = (calc_type(c.a) * (calc_type(*covers) + 1)) >> 8;
            if(alpha == color_type::base_mask)
            {
                p[order_type::R] = c.r;
                p[order_type::G] = c.g;
                p[order_type::B] = c.b;
            }
            else
            {
                blender.blend_pix(p, c.r, c.g, c.b, alpha, *covers);
            }
            p += 4;
            ++covers;
        }
        while(--len);
    }
}

// destination implicitly BGRA32. Source implictly single-byte renderer_alpha coverage.
void FontRendererBlendGamma(FontRenderer *font_renderer, uint8_t *dst, int dst_stride, uint8_t *src, int src_stride, int region_width, int region_height, FontRendererColor color) {
    blender_gamma_type& blender = font_renderer->blender();
    agg::rendering_buffer dst_ren_buf(dst, region_width, region_height, dst_stride);
    const agg::rgba8 color_a(color.r, color.g, color.b);
    for (int x = 0, y = 0; y < region_height; y++) {
        agg::int8u *covers = src + y * src_stride;
        blend_solid_hspan<blender_gamma_type>(dst_ren_buf, blender, x, y, region_width, color_a, covers);
    }
}
