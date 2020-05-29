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
So BakeFontBitmap gets, for pixel_height, (ascent - descent) * font->size / unitsPerEm.
This is equal almost equal to font->height except the 0.5, the missing linegap calculation
and the fact that this latter is an integer instead of a float.
