```c
stbtt_InitFont

stbtt_ScaleForMappingEmToPixels x 3
stbtt_ScaleForPixelHeight
stbtt_BakeFontBitmap
stbtt_GetFontVMetrics x 2

typedef struct {
   unsigned short x0, y0, x1, y1; // coordinates of bbox in bitmap
   float xoff, yoff, xadvance;
} stbtt_bakedchar;

struct RenImage {
  RenColor *pixels;
  int width, height;
};

typedef struct {
  RenImage *image;
  stbtt_bakedchar glyphs[256];
} GlyphSet;

struct RenFont {
  void *data;
  stbtt_fontinfo stbfont;
  GlyphSet *sets[MAX_GLYPHSET];
  float size;
  int height;
};

```

The function stbtt_BakeFontBitmap is used to write bitmap data into set->image->pixels (where set is a GlyphSet).
Note that set->image->pixels need data in RGB format. After stbtt_BakeFontBitmap call the bitmap data are converted into RGB.
With a single call many glyphs corresponding to a range of codepoints, all in a
single image.

## STB truetype font metrics

stbtt_ScaleForPixelHeight takes a float 'height' and returns height / (ascent - descent).

stbtt_ScaleForMappingEmToPixels take a float 'pixels' and returns pixels / unitsPerEm.

### Computing RenFont

When loading a font, in renderer.c, the font->height is determined as:

```c
int ascent, descent, linegap;
stbtt_GetFontVMetrics(&font->stbfont, &ascent, &descent, &linegap);
float scale = stbtt_ScaleForMappingEmToPixels(&font->stbfont, font->size);
font->height = (ascent - descent + linegap) * scale + 0.5;
```

so, mathematically

```c
font->height = (ascent - descent + linegap) * font->size / unitsPerEm + 0.5;
```

**TO DO**: find out for what font->height is actually used.

### Call to BakeFontBitmap

In the same file, renderer.c, to create the glyphset image it computes:

```c
// Using stbtt functions
float s = ScaleForMappingEmToPixels(1) / ScaleForPixelHeight(1);
```

so 's' is actually equal to (ascent - descent) / unitsPerEm.

Then BakeFontBitmap is called and `font->size * s` is used for the pixel_height argument.
So BakeFontBitmap gets

```c
pixel_height = (ascent - descent) * font->size / unitsPerEm;
```

This is equal almost equal to font->height except the 0.5, the missing linegap calculation
and the fact that this latter is an integer instead of a float.

## AGG Font Engine

Calls

FT_Init_FreeType (initialize the library)

In load_font() method:
FT_New_Face or FT_New_Memory_Face (use FT_Done_Face when done)

FT_Attach_File
FT_Select_Charmap

In update_char_size() method:
FT_Set_Char_Size or FT_Set_Pixel_Sizes

In prepare_glyph() method:
FT_Get_Char_Index
FT_Load_Glyph
FT_Render_Glyph (if glyph_render_native_mono or native_gray8) 

in add_kerning() method
FT_Get_Kerning

FT_Done_FreeType (end with library)

## Freetype2's metrics related function and structs

FT_New_Face

```c
typedef struct  FT_FaceRec_
{
  FT_Long           num_faces;
  FT_Long           face_index;

  FT_Long           face_flags;
  FT_Long           style_flags;

  FT_Long           num_glyphs;

  FT_String*        family_name;
  FT_String*        style_name;

  FT_Int            num_fixed_sizes;
  FT_Bitmap_Size*   available_sizes;

  FT_Int            num_charmaps;
  FT_CharMap*       charmaps;

  FT_Generic        generic;

  /*# The following member variables (down to `underline_thickness`) */
  /*# are only relevant to scalable outlines; cf. @FT_Bitmap_Size    */
  /*# for bitmap fonts.                                              */
  FT_BBox           bbox;

  FT_UShort         units_per_EM;
  FT_Short          ascender;
  FT_Short          descender;
  FT_Short          height;

  FT_Short          max_advance_width;
  FT_Short          max_advance_height;

  FT_Short          underline_position;
  FT_Short          underline_thickness;

  FT_GlyphSlot      glyph;
  FT_Size           size;
  FT_CharMap        charmap;

  /* private part omitted. */

} FT_FaceRec;
```
