#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include "SDL_surface.h"
#include "font_render_lcd.h"

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
  font_renderer_lcd *renderer;
  float size;
  int height;
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

  // FIXME: we should remove the gamma correction.
  // So that we have just the coverage.
  font->renderer = new font_renderer_lcd(true, false, false, 1.8);
  font->renderer->load_font(filename);

  int ascender, descender;
  font->renderer->get_font_vmetrics(ascender, descender);
  fprintf(stderr, "Font metrics ascender: %d descender: %d\n", ascender, descender);

  // FIXME: figure out correct calculation for font->height with
  // ascent, descent and linegap.
  font->height = size;
  return font;
}

static GlyphSetA* load_glyphset_agg(RenFontA *font, int idx) {
  const int pixel_size = 4;
  GlyphSetA *set = (GlyphSetA *) check_alloc(calloc(1, sizeof(GlyphSetA)));

  /* init image */
  int width = 512; // 128;
  int height = 512; // 128;
retry:
  set->image = ren_new_image(width, height);

  memset(set->image->pixels, 0xff, width * height * pixel_size);

  agg::rendering_buffer ren_buf((agg::int8u *) set->image->pixels, width, height, -width * pixel_size);
  double x = 4, y = height - font->size * 3 / 2;
  int res = 0;
  const agg::rgba8 text_color(0x00, 0x00, 0x00);
  for (int i = 0; i < 256; i++) {
    if (x + font->size * 3 / 2 > width) {
      x = 4;
      y -= font->size * 3 / 2;
    }
    if (y < 0) {
      res = -1;
      break;
    }
    // FIXME: we are ignoring idx and with a char we cannot pass codepoint > 255.
    char text[2] = {char(i % 256), 0};
    // FIXME: using font->size below is wrong.
    font->renderer->render_text(ren_buf, font->size, text_color, x, y, text);
  }

  /* retry with a larger image buffer if the buffer wasn't large enough */
  if (res < 0) {
    width *= 2;
    height *= 2;
    ren_free_image(set->image);
    goto retry;
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
