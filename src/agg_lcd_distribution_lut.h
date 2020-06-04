//----------------------------------------------------------------------------
// Anti-Grain Geometry (AGG) - Version 2.5
// A high quality rendering engine for C++
// Copyright (C) 2002-2006 Maxim Shemanarev
// Contact: mcseem@antigrain.com
//          mcseemagg@yahoo.com
//          http://antigrain.com
// 
// AGG is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
// 
// AGG is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with AGG; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, 
// MA 02110-1301, USA.
//----------------------------------------------------------------------------

#ifndef AGG_LCD_DISTRIBUTION_LUT_INCLUDED
#define AGG_LCD_DISTRIBUTION_LUT_INCLUDED

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
                int channel = abs(k) % 3;
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
