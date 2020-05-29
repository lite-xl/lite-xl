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

static void* check_alloc(void *ptr) {
  if (!ptr) {
    fprintf(stderr, "Fatal error: memory allocation failed\n");
    exit(EXIT_FAILURE);
  }
  return ptr;
}

RenImage* ren_new_image(int width, int height) {
  assert(width > 0 && height > 0);
  RenImage *image = malloc(sizeof(RenImage) + width * height * sizeof(RenColor));
  check_alloc(image);
  image->pixels = (void*) (image + 1);
  image->width = width;
  image->height = height;
  return image;
}

void ren_free_image(RenImage *image) {
  free(image);
}

RenFontA* ren_load_font_agg(const char *filename, float size) {
  RenFont *font = NULL;

  /* init font */
  font = check_alloc(calloc(1, sizeof(RenFontA)));
  font->size = size;

  font->renderer = new font_renderer_lcd(true, false, true, 1.8);
  font->renderer->load_font(filename);

  // FIXME: figure out correct calculation for font->height with
  // ascent, descent and linegap.
  fit->height = size;
  return font;
}

static GlyphSet* load_glyphset_agg(RenFont *font, int idx) {
  GlyphSet *set = check_alloc(calloc(1, sizeof(GlyphSet)));

  /* init image */
  int width = 128;
  int height = 128;
retry:
  set->image = ren_new_image(width, height);

  /* load glyphs */
  float s =
    stbtt_ScaleForMappingEmToPixels(&font->stbfont, 1) /
    stbtt_ScaleForPixelHeight(&font->stbfont, 1);
  int res = stbtt_BakeFontBitmap(
    font->data, 0, font->size * s, (void*) set->image->pixels,
    width, height, idx * 256, 256, set->glyphs);

  /* retry with a larger image buffer if the buffer wasn't large enough */
  if (res < 0) {
    width *= 2;
    height *= 2;
    ren_free_image(set->image);
    goto retry;
  }

  /* adjust glyph yoffsets and xadvance */
  int ascent, descent, linegap;
  stbtt_GetFontVMetrics(&font->stbfont, &ascent, &descent, &linegap);
  float scale = stbtt_ScaleForMappingEmToPixels(&font->stbfont, font->size);
  int scaled_ascent = ascent * scale + 0.5;
  for (int i = 0; i < 256; i++) {
    set->glyphs[i].yoff += scaled_ascent;
    set->glyphs[i].xadvance = floor(set->glyphs[i].xadvance);
  }

  /* convert 8bit data to 32bit */
  for (int i = width * height - 1; i >= 0; i--) {
    uint8_t n = *((uint8_t*) set->image->pixels + i);
    set->image->pixels[i] = (RenColor) { .r = 255, .g = 255, .b = 255, .a = n };
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
    RenFont *font = ren_load_font(filename, size);
    GlyphSet *set = load_glyphset(font, 0);
    SDL_Surface *surface = SDL_CreateRGBSurfaceWithFormatFrom(
        set->image->pixels,
        set->image->width, set->image->height, 32, set->image->width * 4,
        SDL_PIXELFORMAT_RGBA32);
    SDL_SaveBMP(surface, "stb-glyphset.bmp");
    return 0;
}
