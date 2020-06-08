#include "font_renderer.h"

#include "agg_lcd_distribution_lut.h"
#include "agg_pixfmt_rgb.h"
#include "agg_pixfmt_rgba.h"
#include "agg_gamma_lut.h"

#include "font_renderer_alpha.h"

typedef agg::blender_rgb_gamma<agg::rgba8, agg::order_bgra, agg::gamma_lut<> > blender_gamma_type;

class FontRendererImpl {
public:
    // Conventional LUT values: (1./3., 2./9., 1./9.)
    // The values below are fine tuned as in the Elementary Plot library.

    FontRendererImpl(bool hinting, bool kerning, bool subpixel, float gamma_value) :
        m_renderer(hinting, kerning, subpixel),
        m_gamma_lut(double(gamma_value)),
        m_blender(),
        m_lcd_lut(0.448, 0.184, 0.092)
    {
        m_blender.gamma(m_gamma_lut);
    }

    font_renderer_alpha& renderer_alpha() { return m_renderer; }
    blender_gamma_type& blender() { return m_blender; }
    agg::gamma_lut<>& gamma() { return m_gamma_lut; }
    agg::lcd_distribution_lut& lcd_distribution_lut() { return m_lcd_lut; }

private:
    font_renderer_alpha m_renderer;
    agg::gamma_lut<> m_gamma_lut;
    blender_gamma_type m_blender;
    agg::lcd_distribution_lut m_lcd_lut;
};

FontRenderer *FontRendererNew(unsigned int flags, float gamma) {
    bool hinting = ((flags & FONT_RENDERER_HINTING) != 0);
    bool kerning = ((flags & FONT_RENDERER_KERNING) != 0);
    bool subpixel = ((flags & FONT_RENDERER_SUBPIXEL) != 0);
    return new FontRendererImpl(hinting, kerning, subpixel, gamma);
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

static void glyph_trim_rect(agg::rendering_buffer& ren_buf, GlyphBitmapInfo& gli, int subpixel_scale) {
    const int height = ren_buf.height();
    int x0 = gli.x0 * subpixel_scale, x1 = gli.x1 * subpixel_scale;
    int y0 = gli.y0, y1 = gli.y1;
    for (int y = gli.y0; y < gli.y1; y++) {
        const uint8_t *row = ren_buf.row_ptr(height - 1 - y);
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
    for (int y = gli.y1 - 1; y >= y0; y--) {
        const uint8_t *row = ren_buf.row_ptr(height - 1 - y);
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
    for (int x = gli.x0 * subpixel_scale; x < gli.x1 * subpixel_scale; x += subpixel_scale) {
        unsigned int xaccu = 0;
        for (int y = y0; y < y1; y++) {
            const uint8_t *row = ren_buf.row_ptr(height - 1 - y);
            for (int i = 0; i < subpixel_scale; i++) {
                xaccu |= row[x + i];
            }
        }
        if (xaccu == 0) {
            x0 += subpixel_scale;
        } else {
            break;
        }
    }
    for (int x = (gli.x1 - 1) * subpixel_scale; x >= x0; x -= subpixel_scale) {
        unsigned int xaccu = 0;
        for (int y = y0; y < y1; y++) {
            const uint8_t *row = ren_buf.row_ptr(height - 1 - y);
            for (int i = 0; i < subpixel_scale; i++) {
                xaccu |= row[x + i];
            }
        }
        if (xaccu == 0) {
            x1 -= subpixel_scale;
        } else {
            break;
        }
    }
    gli.xoff += (x0 / subpixel_scale) - gli.x0;
    gli.yoff += (y0 - gli.y0);
    gli.x0 = x0 / subpixel_scale;
    gli.y0 = y0;
    gli.x1 = x1 / subpixel_scale;
    gli.y1 = y1;
}

static void glyph_lut_convolution(agg::rendering_buffer ren_buf, agg::lcd_distribution_lut& lcd_lut, agg::int8u *covers_buf, GlyphBitmapInfo& gli) {
    const int subpixel = 3;
    const int x0 = gli.x0, y0 = gli.y0, x1 = gli.x1, y1 = gli.y1;
    const int len = (x1 - x0) * subpixel;
    const int height = ren_buf.height();
    for (int y = y0; y < y1; y++) {
        agg::int8u *covers = ren_buf.row_ptr(height - 1 - y) + x0 * subpixel;
        memcpy(covers_buf, covers, len);
        for (int x = x0 - 1; x < x1 + 1; x++) {
            for (int i = 0; i < subpixel; i++) {
                const int cx = (x - x0) * subpixel + i;
                covers[cx] = lcd_lut.convolution(covers_buf, cx, 0, len - 1);
            }
        }
    }
    gli.x0 -= 1;
    gli.x1 += 1;
    gli.xoff -= 1;
}

static int ceil_to_multiple(int n, int p) {
    return p * ((n + p - 1) / p);
}

int FontRendererBakeFontBitmap(FontRenderer *font_renderer, int font_height,
    void *pixels, int pixels_width, int pixels_height,
    int first_char, int num_chars, GlyphBitmapInfo *glyphs, int subpixel_scale)
{
    font_renderer_alpha& renderer_alpha = font_renderer->renderer_alpha();

    const int pixel_size = 1;
    memset(pixels, 0x00, pixels_width * pixels_height * subpixel_scale * pixel_size);

    double ascender, descender;
    renderer_alpha.get_font_vmetrics(ascender, descender);

    const int ascender_px  = int(ascender * font_height);
    const int descender_px = ascender_px - font_height;

    const int pad_y = font_height / 10;
    const int y_step = font_height + 2 * pad_y;

    agg::lcd_distribution_lut& lcd_lut = font_renderer->lcd_distribution_lut();
    agg::rendering_buffer ren_buf((agg::int8u *) pixels, pixels_width * subpixel_scale, pixels_height, -pixels_width * subpixel_scale * pixel_size);
    // When using subpixel font rendering it is needed to leave a padding pixel on the left and on the right.
    // Since each pixel is composed by n subpixel we set below x_start to subpixel_scale instead than zero.
    const int x_start = subpixel_scale;
    int x = x_start, y = pixels_height - 1;
    int res = 0;
    const agg::alpha8 text_color(0xff);
#ifdef FONT_RENDERER_HEIGHT_HACK
    const int font_height_reduced = (font_height * 86) / 100;
#else
    const int font_height_reduced = font_height;
#endif
    renderer_alpha.set_font_height(font_height_reduced);
    agg::int8u *cover_swap_buffer = new agg::int8u[pixels_width * subpixel_scale];
    for (int i = 0; i < num_chars; i++) {
        int codepoint = first_char + i;
        if (x + font_height * subpixel_scale > pixels_width * subpixel_scale) {
            x = x_start;
            y -= y_step;
        }
        if (y - y_step < 0) {
            res = -1;
            break;
        }
        const int y_baseline = y - pad_y - ascender_px;

        double x_next = x, y_next = y_baseline;
        renderer_alpha.render_codepoint(ren_buf, text_color, x_next, y_next, codepoint, subpixel_scale);
        int x_next_i = (subpixel_scale == 1 ? int(x_next + 1.0) : ceil_to_multiple(x_next + 0.5, subpixel_scale));

        // Below x and x_next_i will always be integer multiples of subpixel_scale.
        GlyphBitmapInfo& glyph_info = glyphs[i];
        glyph_info.x0 = x / subpixel_scale;
        glyph_info.y0 = pixels_height - 1 - (y_baseline + ascender_px  + pad_y); // FIXME: add -1 ?
        glyph_info.x1 = x_next_i / subpixel_scale;
        glyph_info.y1 = pixels_height - 1 - (y_baseline + descender_px - pad_y); // FIXME: add -1 ?

        glyph_info.xoff = 0;
        glyph_info.yoff = -pad_y;
        glyph_info.xadvance = (x_next - x) / subpixel_scale;

#ifdef FONT_RENDERER_DEBUG
        glyph_info.ybaseline = pixels_height - 1 - y_baseline;
#endif
        if (glyph_info.x1 > glyph_info.x0) {
            glyph_lut_convolution(ren_buf, lcd_lut, cover_swap_buffer, glyph_info);
        }
        glyph_trim_rect(ren_buf, glyph_info, subpixel_scale);

        // When subpixel is activated we need one padding pixel on the left and on the right.
        x = x_next_i + 2 * subpixel_scale;
    }
    delete [] cover_swap_buffer;
    return res;
}

void blend_solid_hspan(agg::rendering_buffer& rbuf, blender_gamma_type& blender,
                        int x, int y, unsigned len,
                        const agg::rgba8& c, const agg::int8u* covers)
{
    typedef typename blender_gamma_type::color_type color_type;
    typedef typename blender_gamma_type::order_type order_type;
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

void blend_solid_hspan_rgb_subpixel(agg::rendering_buffer& rbuf, agg::gamma_lut<>& gamma, agg::lcd_distribution_lut& lcd_lut,
    const int x, const int y, unsigned len,
    const agg::rgba8& c,
    const agg::int8u* covers)
{
    const int pixel_size = 4;
    const agg::int8u rgb[3] = { c.r, c.g, c.b };
    agg::int8u* p = rbuf.row_ptr(y) + x * pixel_size;

    // Indexes to adress RGB colors in a BGRA32 format.
    const int pixel_index[3] = {2, 1, 0};
    for (unsigned cx = 0; cx < len; cx += 3)
    {
        for (int i = 0; i < 3; i++) {
            const unsigned cover_value = covers[cx + i];
            const unsigned alpha = (cover_value + 1) * (c.a + 1);
            const unsigned dst_col = gamma.dir(rgb[i]);
            const unsigned src_col = gamma.dir(*(p + pixel_index[i]));
            *(p + pixel_index[i]) = gamma.inv((((dst_col - src_col) * alpha) + (src_col << 16)) >> 16);
        }
        // Leave p[3], the alpha channel value unmodified.
        p += 4;
    }
}

// destination implicitly BGRA32. Source implictly single-byte renderer_alpha coverage.
void FontRendererBlendGamma(FontRenderer *font_renderer, uint8_t *dst, int dst_stride, uint8_t *src, int src_stride, int region_width, int region_height, FontRendererColor color) {
    blender_gamma_type& blender = font_renderer->blender();
    agg::rendering_buffer dst_ren_buf(dst, region_width, region_height, dst_stride);
    const agg::rgba8 color_a(color.r, color.g, color.b);
    for (int x = 0, y = 0; y < region_height; y++) {
        agg::int8u *covers = src + y * src_stride;
        blend_solid_hspan(dst_ren_buf, blender, x, y, region_width, color_a, covers);
    }
}

// destination implicitly BGRA32. Source implictly single-byte renderer_alpha coverage with subpixel scale = 3.
void FontRendererBlendGammaSubpixel(FontRenderer *font_renderer, uint8_t *dst, int dst_stride, uint8_t *src, int src_stride, int region_width, int region_height, FontRendererColor color) {
    const int subpixel_scale = 3;
    agg::gamma_lut<>& gamma = font_renderer->gamma();
    agg::lcd_distribution_lut& lcd_lut = font_renderer->lcd_distribution_lut();
    agg::rendering_buffer dst_ren_buf(dst, region_width, region_height, dst_stride);
    const agg::rgba8 color_a(color.r, color.g, color.b);
    for (int x = 0, y = 0; y < region_height; y++) {
        agg::int8u *covers = src + y * src_stride;
        blend_solid_hspan_rgb_subpixel(dst_ren_buf, gamma, lcd_lut, x, y, region_width * subpixel_scale, color_a, covers);
    }
}
