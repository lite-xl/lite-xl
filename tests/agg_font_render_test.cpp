#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include "SDL_surface.h"
#include "font_renderer_alpha.h"

#define MAX_GLYPHSET 256

typedef struct { uint8_t b, g, r, a; } RenColor;
typedef struct { int x, y, width, height; } RenRect;

struct RenImage {
  RenColor *pixels;
  int width, height;
};

struct GlyphSetA {
  RenImage *image;
  // FIXME: add glyphs information for AGG implementation
  // stbtt_bakedchar glyphs[256];
};

struct RenFontA {
  font_renderer_alpha *renderer;
  float size;
  int height;
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

  int ascender, descender;
  font->renderer->get_font_vmetrics(ascender, descender);
  fprintf(stderr, "Font metrics ascender: %d descender: %d\n", ascender, descender);

  float scale = font->renderer->scale_for_em_to_pixels(size);
  font->height = (ascender - descender) * scale + 0.5;
  font->height_bitmap = (ascender - descender) * scale;

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

  fprintf(stderr, "Using height: %g in BakeFontBitmap\n", font->height_bitmap);

  agg::rendering_buffer ren_buf((agg::int8u *) set->image->pixels, width, height, -width * pixel_size);
  // FIXME: figure out how to precisely layout each glyph.
  double x = 4, y = height - font->height * 3 / 2;
  int res = 0;
  const agg::alpha8 text_color(0xff);
  for (int i = 0; i < 256; i++) {
    if (x + font->height * 3 / 2 > width) {
      x = 4;
      y -= font->height * 3 / 2;
    }
    if (y < 0) {
      res = -1;
      break;
    }
    // FIXME: we are ignoring idx and with a char we cannot pass codepoint > 255.
    char text[2] = {char(i % 256), 0};
    // FIXME: using font->size below is wrong.
    font->renderer->render_text(ren_buf, font->height_bitmap, text_color, x, y, text);
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
