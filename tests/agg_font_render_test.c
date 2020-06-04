#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include "SDL_surface.h"
#include "font_renderer.h"

#define MAX_GLYPHSET 256

typedef struct { uint8_t b, g, r, a; } RenColor;
typedef struct { int x, y, width, height; } RenRect;

struct RenImage {
  RenColor *pixels;
  int width, height;
};
typedef struct RenImage RenImage;

struct GlyphSet {
  RenImage *image;
  GlyphBitmapInfo glyphs[256];
};
typedef struct GlyphSet GlyphSet;

struct RenFont {
  void *data;
  GlyphSet *sets[MAX_GLYPHSET];
  float size;
  int height;
  FontRenderer *renderer;
};
typedef struct RenFont RenFont;

static void* check_alloc(void *ptr) {
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

RenFont* ren_load_font_agg(const char *filename, float size) {
  RenFont *font = NULL;

  /* init font */
  font = check_alloc(calloc(1, sizeof(RenFont)));
  font->size = size;

  font->renderer = FontRendererNew(FONT_RENDERER_HINTING, 1.8);
  if (FontRendererLoadFont(font->renderer, filename)) {
    free(font);
    return NULL;
  }
  font->height = FontRendererGetFontHeight(font->renderer, size);

  fprintf(stderr, "Font height: %d\n", font->height);

  return font;
}

static GlyphSet* load_glyphset_agg(RenFont *font, int idx) {
  GlyphSet *set = check_alloc(calloc(1, sizeof(GlyphSet)));

  /* init image */
  int width = 128;
  int height = 128;
retry:
  set->image = ren_new_image(width, height);

  const int subpixel_scale = 3;
  int res = FontRendererBakeFontBitmap(font->renderer, font->height,
    (void *) set->image->pixels, width, height,
    idx << 8, 256, set->glyphs, subpixel_scale);

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

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <font-filename> <size>\n", argv[0]);
        return 1;
    }
    const char *filename = argv[1];
    const int size = atoi(argv[2]);
    RenFont *font = ren_load_font_agg(filename, size);
    GlyphSet *set = load_glyphset_agg(font, 0);
    SDL_Surface *surface = SDL_CreateRGBSurfaceWithFormatFrom(
        set->image->pixels,
        set->image->width, set->image->height, 32, set->image->width * 4,
        SDL_PIXELFORMAT_RGBA32);
    SDL_SaveBMP(surface, "agg-glyphset.bmp");
    return 0;
}
