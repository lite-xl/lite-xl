// Adapted by Francesco Abbate for GSL Shell
// Original code's copyright below.
//----------------------------------------------------------------------------
// Anti-Grain Geometry - Version 2.4
// Copyright (C) 2002-2005 Maxim Shemanarev (http://www.antigrain.com)
//
// Permission to copy, use, modify, sell and distribute this software
// is granted provided this copyright notice appears in all copies.
// This software is provided "as is" without express or implied
// warranty, and with no claim as to its suitability for any purpose.
//
//----------------------------------------------------------------------------
// Contact: mcseem@antigrain.com
//          mcseemagg@yahoo.com
//          http://www.antigrain.com
//----------------------------------------------------------------------------

#ifndef AGG_LCD_DISTRIBUTION_LUT_INCLUDED
#define AGG_LCD_DISTRIBUTION_LUT_INCLUDED

#include <cstdlib>

#include "agg_basics.h"

namespace agg
{

    //=====================================================lcd_distribution_lut
    class lcd_distribution_lut
    {
    public:
        lcd_distribution_lut(double prim, double second, double tert)
        {
            double norm = 1.0 / (prim + second*2 + tert*2);
            prim   *= norm;
            second *= norm;
            tert   *= norm;
            for(unsigned i = 0; i < 256; i++)
            {
                unsigned b = (i << 8);
                unsigned s = round(second * b);
                unsigned t = round(tert   * b);
                unsigned p = b - (2*s + 2*t);

                m_data[3*i + 1] = s; /* secondary */
                m_data[3*i + 2] = t; /* tertiary */
                m_data[3*i    ] = p; /* primary */
            }
        }

        unsigned convolution(const int8u* covers, int i0, int i_min, int i_max) const
        {
            unsigned sum = 0;
            int k_min = (i0 >= i_min + 2 ? -2 : i_min - i0);
            int k_max = (i0 <= i_max - 2 ?  2 : i_max - i0);
            for (int k = k_min; k <= k_max; k++)
            {
                /* select the primary, secondary or tertiary channel */
                int channel = std::abs(k) % 3;
                int8u c = covers[i0 + k];
                sum += m_data[3*c + channel];
            }

            return (sum + 128) >> 8;
        }

    private:
        unsigned short m_data[256*3];
    };

}

#endif
