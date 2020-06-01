#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include "SDL_surface.h"
#include "font_renderer_alpha.h"

#define MAX_GLYPHSET 256

typedef struct { uint8_t b, g, r, a; } RenColor;
typedef struct { int x, y, width, height; } RenRect;

// Mirrors stbtt_bakedchar.
struct GlyphBitmapInfo {
  unsigned short x0, y0, x1, y1;
  float xoff, yoff, xadvance;
};

struct RenImage {
  RenColor *pixels;
  int width, height;
};

struct GlyphSetA {
  RenImage *image;
  GlyphBitmapInfo glyphs[256];
};

struct RenFontA {
  font_renderer_alpha *renderer;
  float size;
  int height;
  float ascender, descender;
  // For some reason the font's height used in renderer.c
  // when calling BakeFontBitmap is 0.5 off from 'height'.
  float height_bitmap;
};

template <typename T>
static T* check_alloc(T *ptr) {
  if (ptr == 0) {
    fprintf(stderr, "Fatal error: memory allocation failed\n");
    exit(EXIT_FAILURE);
  }
  return ptr;
}

RenImage* ren_new_image(int width, int height) {
  assert(width > 0 && height > 0);
  RenImage *image = (RenImage *) malloc(sizeof(RenImage) + width * height * sizeof(RenColor));
  check_alloc(image);
  image->pixels = (RenColor*) (image + 1);
  image->width = width;
  image->height = height;
  return image;
}

void ren_free_image(RenImage *image) {
  free(image);
}

RenFontA* ren_load_font_agg(const char *filename, float size) {
  RenFontA *font = NULL;

  /* init font */
  font = (RenFontA *) check_alloc(calloc(1, sizeof(RenFontA)));
  font->size = size;

  font->renderer = new font_renderer_alpha(false, false);
  font->renderer->load_font(filename);

  double ascender, descender;
  font->renderer->get_font_vmetrics(ascender, descender);
  int face_height = font->renderer->get_face_height();
  // Gives the font's ascender and descender like stbtt.
  fprintf(stderr, "Font metrics ascender: %g descender: %g\n", ascender * face_height, descender * face_height);

  float scale = font->renderer->scale_for_em_to_pixels(size);
  font->height = (ascender - descender) * face_height * scale + 0.5;
  font->height_bitmap = (ascender - descender) * face_height * scale;

  font->descender = descender * font->height_bitmap;
  font->ascender  = ascender  * font->height_bitmap;

  fprintf(stderr, "Font's pixel ascender: %g descender: %g sum: %g\n", font->ascender, font->descender, font->ascender - font->descender);

  fprintf(stderr, "Font height: %d\n", font->height);

  return font;
}

static GlyphSetA* load_glyphset_agg(RenFontA *font, int idx) {
  const int pixel_size = 1;
  GlyphSetA *set = (GlyphSetA *) check_alloc(calloc(1, sizeof(GlyphSetA)));

  /* init image */
  int width = 128;
  int height = 128;
retry:
  set->image = ren_new_image(width, height);

  memset(set->image->pixels, 0x00, width * height * pixel_size);

  // NOTE here that render.c with stb_truetype is really using font->height_bitmap.
  fprintf(stderr, "Using height: %d in BakeFontBitmap\n", font->height);

  const int pad_y = font->height * 2 / 10;
  const int ascender_px = int(font->ascender + 0.5), descender_px = int(font->descender + 0.5);
  const int y_step = font->height + 2 * pad_y;

  agg::rendering_buffer ren_buf((agg::int8u *) set->image->pixels, width, height, -width * pixel_size);
  int x = 0, y = height;
  int res = 0;
  const agg::alpha8 text_color(0xff);
  for (int i = 0; i < 256; i++) {
    int codepoint = (idx << 8) | i;
    if (x + font->height > width) {
      x = 0;
      y -= y_step;
    }
    if (y - font->height - 2 * pad_y < 0) {
      res = -1;
      break;
    }
    const int y_baseline = y - pad_y - font->height;

    // FIXME: using font->height_bitmap below seems logically correct but
    // the font size is bigger than what printed by BakeFontBitmap.
    double x_next = x, y_next = y_baseline;
    font->renderer->render_codepoint(ren_buf, font->height, text_color, x_next, y_next, codepoint);
    int x_next_i = int(x_next + 0.5);
    GlyphBitmapInfo& glyph_info = set->glyphs[i];
    glyph_info.x0 = x;
    glyph_info.y0 = height - (y_baseline + ascender_px  + pad_y);
    glyph_info.x1 = x_next_i;
    glyph_info.y1 = height - (y_baseline + descender_px - pad_y);
    glyph_info.xoff = 0;
    glyph_info.yoff = -font->ascender;
    glyph_info.xadvance = x_next - x;
    fprintf(stderr,
      "glyph codepoint %3d (ascii: %1c), BOX (%3d, %3d) (%3d, %3d), "
      "OFFSET (%.5g, %.5g), X ADVANCE %.5g\n",
      codepoint, i,
      glyph_info.x0, glyph_info.y0, glyph_info.x1, glyph_info.y1,
      glyph_info.xoff, glyph_info.yoff, glyph_info.xadvance);
    x = x_next_i;
  }

  /* retry with a larger image buffer if the buffer wasn't large enough */
  if (res < 0) {
    width *= 2;
    height *= 2;
    ren_free_image(set->image);
    goto retry;
  }

  /* convert 8bit data to 32bit */
  for (int i = width * height - 1; i >= 0; i--) {
    uint8_t n = *((uint8_t*) set->image->pixels + i);
    RenColor c = {0xff, 0xff, 0xff, n};
    set->image->pixels[i] = c;
  }

  return set;
}

extern "C" int main(int argc, char *argv[]);

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <font-filename> <size>\n", argv[0]);
        return 1;
    }
    const char *filename = argv[1];
    const int size = atoi(argv[2]);
    RenFontA *font = ren_load_font_agg(filename, size);
    GlyphSetA *set = load_glyphset_agg(font, 0);
    SDL_Surface *surface = SDL_CreateRGBSurfaceWithFormatFrom(
        set->image->pixels,
        set->image->width, set->image->height, 32, set->image->width * 4,
        SDL_PIXELFORMAT_RGBA32);
    SDL_SaveBMP(surface, "agg-glyphset.bmp");
    return 0;
}
