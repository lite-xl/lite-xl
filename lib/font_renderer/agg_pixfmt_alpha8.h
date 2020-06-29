#pragma once

#include <string.h>
#include "agg_basics.h"
#include "agg_rendering_buffer.h"

namespace agg
{
    // This is a special purpose color type that only has the alpha channel.
    // It can be thought as a gray color but with the intensity always on.
    // It is actually used to store coverage information.
    struct alpha8
    {
        typedef int8u  value_type;
        typedef int32u calc_type;
        typedef int32  long_type;
        enum base_scale_e
        {
            base_shift = 8,
            base_scale = 1 << base_shift,
            base_mask  = base_scale - 1
        };

        value_type a;

        //--------------------------------------------------------------------
        alpha8(unsigned a_=base_mask) :
            a(int8u(a_)) {}
    };

    // Pixer format to store coverage information.
    class pixfmt_alpha8
    {
    public:
        typedef alpha8 color_type;
        typedef int8u  value_type;
        typedef int32u calc_type;
        typedef agg::rendering_buffer::row_data row_data;

        //--------------------------------------------------------------------
        pixfmt_alpha8(rendering_buffer& rb): m_rbuf(&rb)
        {
        }

        //--------------------------------------------------------------------
        unsigned width()  const {
            return m_rbuf->width();
        }
        unsigned height() const {
            return m_rbuf->height();
        }

        // This method should never be called when using the scanline_u8.
        // The use of scanline_p8 should be avoided because if does not works
        // properly for rendering fonts because single hspan are split in many
        // hline/hspan elements and pixel whitening happens.
        void blend_hline(int x, int y, unsigned len,
                         const color_type& c, int8u cover)
        { }

        void copy_hline(int x, int y, unsigned len, const color_type& c)
        {
            value_type* p = (value_type*) m_rbuf->row_ptr(y) + x;
            do 
            {
                *p = c.a;
                p++;
            }
            while(--len);
        }

        //--------------------------------------------------------------------
        void blend_solid_hspan(int x, int y,
                               unsigned len,
                               const color_type& c,
                               const int8u* covers)
        {
            value_type* p = (value_type*) m_rbuf->row_ptr(y) + x;
            do
            {
                calc_type alpha = (calc_type(c.a) * (calc_type(*covers) + 1)) >> 8;
                *p = alpha;
                p++;
                ++covers;
            }
            while(--len);
        }

    private:
        rendering_buffer* m_rbuf;
    };

}
