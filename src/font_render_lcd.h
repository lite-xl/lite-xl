#pragma once

#include "agg_basics.h"
#include "agg_conv_curve.h"
#include "agg_conv_transform.h"
#include "agg_gamma_lut.h"
#include "agg_font_freetype.h"
// #include "agg_pixfmt_rgb.h"
#include "agg_pixfmt_rgba.h"
// #include "agg_pixfmt_rgb24_lcd.h"
#include "agg_pixfmt_bgra32_lcd.h"
#include "agg_rasterizer_scanline_aa.h"
#include "agg_renderer_primitives.h"
#include "agg_renderer_scanline.h"
#include "agg_rendering_buffer.h"
#include "agg_scanline_u.h"

// FIXME: the pixel type rgb24 of rgba32 is hard coded below
class font_renderer_lcd
{
    typedef agg::pixfmt_bgra32 pixfmt_type;
    typedef agg::renderer_base<pixfmt_type> base_ren_type;
    typedef agg::renderer_scanline_aa_solid<base_ren_type> renderer_solid;
    typedef agg::font_engine_freetype_int32 font_engine_type;
    typedef agg::font_cache_manager<font_engine_type> font_manager_type;

    font_engine_type             m_feng;
    font_manager_type            m_fman;
    agg::gamma_lut<>             m_gamma_lut;

    // Font rendering options.
    bool m_hinting;
    bool m_kerning;
    bool m_grayscale;
    double m_gamma;

    bool m_font_loaded;

    // Pipeline to process the vectors glyph paths (curves + contour)
    agg::trans_affine m_mtx;
    agg::conv_curve<font_manager_type::path_adaptor_type> m_curves;
    agg::conv_transform<agg::conv_curve<font_manager_type::path_adaptor_type> > m_trans;
public:
    font_renderer_lcd(bool hinting, bool kerning, bool subpixel, double gamma):
        m_feng(),
        m_fman(m_feng),
        m_hinting(hinting),
        m_kerning(kerning),
        m_grayscale(!subpixel),
        m_gamma(gamma),
        m_font_loaded(false),
        m_curves(m_fman.path_adaptor()),
        m_trans(m_curves, m_mtx)
    {
        m_gamma_lut.gamma(m_gamma);
    }

    bool load_font(const char *font_filename) {
        if(m_feng.load_font(font_filename, 0, agg::glyph_ren_outline)) {
            m_font_loaded = true;
        }
        return m_font_loaded;
    }

    template<class Rasterizer, class Scanline, class RenSolid>
    double draw_text(Rasterizer& ras, Scanline& sl, 
                     RenSolid& ren_solid, const agg::rgba8 color,
                     const char* text,
                     double x, double y, double height,
                     unsigned subpixel_scale)
    {
        const double scale_x = 100;

        m_feng.height(height);
        m_feng.width(height * scale_x * subpixel_scale);
        m_feng.hinting(m_hinting);

        const char* p = text;

        // FIXME: check we need to multiply x by scale_x.
        x *= scale_x * subpixel_scale;
        double start_x = x;

        while(*p)
        {
            if(*p == '\n')
            {
                x = start_x;
                y -= height * 1.25;
                ++p;
                continue;
            }

            const agg::glyph_cache* glyph = m_fman.glyph(*p);
            if(glyph)
            {
                if(m_kerning)
                {
                    m_fman.add_kerning(&x, &y);
                }

                m_fman.init_embedded_adaptors(glyph, 0, 0);
                if(glyph->data_type == agg::glyph_data_outline)
                {
                    double ty = m_hinting ? floor(y + 0.5) : y;
                    ras.reset();
                    m_mtx.reset();
                    m_mtx *= agg::trans_affine_scaling(1.0 / scale_x, 1);
                    m_mtx *= agg::trans_affine_translation(start_x + x/scale_x, ty);
                    ras.add_path(m_trans);
                    ren_solid.color(color);
                    agg::render_scanlines(ras, sl, ren_solid);
                }

                // increment pen position
                x += glyph->advance_x;
                y += glyph->advance_y;
            }
            ++p;
        }
        return x / (subpixel_scale * scale_x);
    }

    void clear(agg::rendering_buffer& ren_buf, const agg::rgba8 color) {
        agg::pixfmt_bgra32 pf(ren_buf);
        base_ren_type ren_base(pf);
        ren_base.clear(color);
    }

    double render_text(agg::rendering_buffer& ren_buf,
        const double text_size,
        const agg::rgba8 text_color,
        double x, double y,
        const char *text)
    {
        if (!m_font_loaded) {
            return y;
        }

        agg::scanline_u8 sl;
        agg::rasterizer_scanline_aa<> ras;
        ras.clip_box(0, 0, ren_buf.width()*3, ren_buf.height());

        //--------------------------------------
        if(m_grayscale)
        {
            agg::pixfmt_bgra32 pf(ren_buf);
            base_ren_type ren_base(pf);
            renderer_solid ren_solid(ren_base);
            y = draw_text(ras, sl, ren_solid, text_color, text, x, y, text_size, 1);
        }
        else
        {
            // Conventional LUT values: (1./3., 2./9., 1./9.)
            // The values below are fine tuned as in the Elementary Plot library.
            // The primary weight should be 0.448 but is left adjustable.
            agg::lcd_distribution_lut lut(0.448, 0.184, 0.092);
            typedef agg::pixfmt_bgra32_lcd_gamma<agg::gamma_lut<> > pixfmt_lcd_type;
            pixfmt_lcd_type pf_lcd(ren_buf, lut, m_gamma_lut);
            agg::renderer_base<pixfmt_lcd_type> ren_base_lcd(pf_lcd);
            agg::renderer_scanline_aa_solid<agg::renderer_base<pixfmt_lcd_type> > ren_solid_lcd(ren_base_lcd);
            y = draw_text(ras, sl, ren_solid_lcd, text_color, text, x, y, text_size, 3);
        }
        return y;
    }
};
