#include <stdio.h>
#include <stdlib.h>
#include <assert.h>

#include "SDL_surface.h"
#include "stb_truetype.h"

#define MAX_GLYPHSET 256

typedef struct { uint8_t b, g, r, a; } RenColor;
typedef struct { int x, y, width, height; } RenRect;

struct RenImage {
  RenColor *pixels;
  int width, height;
};
typedef struct RenImage RenImage;

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
typedef struct RenFont RenFont;

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

RenFont* ren_load_font(const char *filename, float size) {
  RenFont *font = NULL;
  FILE *fp = NULL;

  /* init font */
  font = check_alloc(calloc(1, sizeof(RenFont)));
  font->size = size;

  /* load font into buffer */
  fp = fopen(filename, "rb");
  if (!fp) { return NULL; }
  /* get size */
  fseek(fp, 0, SEEK_END); int buf_size = ftell(fp); fseek(fp, 0, SEEK_SET);
  /* load */
  font->data = check_alloc(malloc(buf_size));
  int _ = fread(font->data, 1, buf_size, fp); (void) _;
  fclose(fp);
  fp = NULL;

  /* init stbfont */
  int ok = stbtt_InitFont(&font->stbfont, font->data, 0);
  if (!ok) { goto fail; }

  /* get height and scale */
  int ascent, descent, linegap;
  fprintf(stderr, "Requesting font size: %g\n", size);
  stbtt_GetFontVMetrics(&font->stbfont, &ascent, &descent, &linegap);
  float scale = stbtt_ScaleForMappingEmToPixels(&font->stbfont, size);
  fprintf(stderr, "Font metrics ascent: %d descent: %d, linegap: %d scale: %g\n", ascent, descent, linegap, scale);
  font->height = (ascent - descent + linegap) * scale + 0.5;
  fprintf(stderr, "Font height: %d\n", font->height);

  return font;

fail:
  if (fp) { fclose(fp); }
  if (font) { free(font->data); }
  free(font);
  return NULL;
}

static GlyphSet* load_glyphset(RenFont *font, int idx) {
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
