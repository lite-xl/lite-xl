#pragma once

#include "agg_basics.h"
#include "agg_conv_curve.h"
#include "agg_conv_transform.h"
#include "agg_gamma_lut.h"
#include "agg_font_freetype.h"
#include "agg_pixfmt_alpha8.h"
#include "agg_rasterizer_scanline_aa.h"
#include "agg_renderer_primitives.h"
#include "agg_renderer_scanline.h"
#include "agg_rendering_buffer.h"
#include "agg_scanline_u.h"

class font_renderer_alpha
{
    typedef agg::pixfmt_alpha8 pixfmt_type;
    typedef agg::renderer_base<pixfmt_type> base_ren_type;
    typedef agg::renderer_scanline_aa_solid<base_ren_type> renderer_solid;
    typedef agg::font_engine_freetype_int32 font_engine_type;
    typedef agg::font_cache_manager<font_engine_type> font_manager_type;

    font_engine_type             m_feng;
    font_manager_type            m_fman;

    // Font rendering options.
    bool m_hinting;
    bool m_kerning;
    bool m_subpixel;
    bool m_prescale_x;

    bool m_font_loaded;

    // Pipeline to process the vectors glyph paths (curves + contour)
    agg::trans_affine m_mtx;
    agg::conv_curve<font_manager_type::path_adaptor_type> m_curves;
    agg::conv_transform<agg::conv_curve<font_manager_type::path_adaptor_type> > m_trans;
public:
    typedef agg::pixfmt_alpha8::color_type color_type;

    font_renderer_alpha(bool hinting, bool kerning, bool subpixel, bool prescale_x):
        m_feng(),
        m_fman(m_feng),
        m_hinting(hinting),
        m_kerning(kerning),
        m_subpixel(subpixel),
        m_prescale_x(prescale_x),
        m_font_loaded(false),
        m_curves(m_fman.path_adaptor()),
        m_trans(m_curves, m_mtx)
    { }

    int get_face_height() const {
        return m_feng.face_height();
    }

    void get_font_vmetrics(double& ascender, double& descender) {
        double current_height = m_feng.height();
        m_feng.height(1.0);
        ascender  = m_feng.ascender();
        descender = m_feng.descender();
        m_feng.height(current_height);
}

    float scale_for_em_to_pixels(float size) {
        int units_per_em = m_feng.face_units_em();
        if (units_per_em > 0) {
            return size / units_per_em;
        }
        return 0.0;
    }

    bool load_font(const char *font_filename) {
        if(m_feng.load_font(font_filename, 0, agg::glyph_ren_outline)) {
            m_font_loaded = true;
            m_feng.hinting(m_hinting);
        }
        return m_font_loaded;
    }

    void set_font_height(double height) {
        const double scale_x = (m_prescale_x ? 100.0 : 1.0);
        m_feng.height(height);
        m_feng.width(height * scale_x);
    }

    template<class Rasterizer, class Scanline, class RenSolid>
    void draw_codepoint(Rasterizer& ras, Scanline& sl,
        RenSolid& ren_solid, const color_type color,
        int codepoint, double& x, double& y, const int subpixel_scale)
    {
        const double scale_x = (m_prescale_x ? 100.0 : 1.0);
        // Coefficient to scale back the glyph to the final scale.
        const double cx_inv_scale = subpixel_scale / scale_x;

        // Represent the delta in x scaled by scale_x.
        double x_delta = 0;
        double start_x = x;

        const agg::glyph_cache* glyph = m_fman.glyph(codepoint);
        if(glyph)
        {
            if(m_kerning)
            {
                m_fman.add_kerning(&x_delta, &y);
            }

            m_fman.init_embedded_adaptors(glyph, 0, 0);
            if(glyph->data_type == agg::glyph_data_outline)
            {
                double ty = m_hinting ? floor(y + 0.5) : y;
                ras.reset();
                m_mtx.reset();
                m_mtx *= agg::trans_affine_scaling(cx_inv_scale, 1);
                m_mtx *= agg::trans_affine_translation(start_x + cx_inv_scale * x_delta, ty);
                ras.add_path(m_trans);
                ren_solid.color(color);
                agg::render_scanlines(ras, sl, ren_solid);
            }

            y += glyph->advance_y;
            x += cx_inv_scale * (x_delta + glyph->advance_x);
        }
    }

    void clear(agg::rendering_buffer& ren_buf, const color_type color) {
        pixfmt_type pf(ren_buf);
        base_ren_type ren_base(pf);
        ren_base.clear(color);
    }

    void render_codepoint(agg::rendering_buffer& ren_buf,
        const color_type text_color,
        double& x, double& y,
        int codepoint, const int subpixel_scale)
    {
        if (!m_font_loaded) {
            return;
        }
        agg::scanline_u8 sl;
        agg::rasterizer_scanline_aa<> ras;
        ras.clip_box(0, 0, ren_buf.width(), ren_buf.height());

        agg::pixfmt_alpha8 pf(ren_buf);
        base_ren_type ren_base(pf);
        renderer_solid ren_solid(ren_base);
        draw_codepoint(ras, sl, ren_solid, text_color, codepoint, x, y, subpixel_scale);
    }

    int codepoint_bounds(int codepoint, const int subpixel_scale, agg::rect_i& bounds)
    {
        if (!m_font_loaded) return 1;
        const double scale_x = (m_prescale_x ? 100.0 : 1.0);
        const double cx_inv_scale = subpixel_scale / scale_x;
        const agg::glyph_cache* glyph = m_fman.glyph(codepoint);
        if (glyph) {
            bounds = glyph->bounds;
            bounds.x1 *= cx_inv_scale;
            bounds.x2 *= cx_inv_scale;
            return 0;
        }
        return 1;
  }
};
