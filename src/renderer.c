#include <stdio.h>
#include <stdbool.h>
#include <assert.h>
#include <math.h>
#include "renderer.h"
#include "font_renderer.h"

#define MAX_GLYPHSET 256

struct RenImage {
  RenColor *pixels;
  int width, height;
};

// Important: when a subpixel scale is used the width below will be the width in logical pixel.
// As each logical pixel contains 3 subpixels it means that the 'pixels' pointer
// will hold enough space for '3 * width' uint8_t values.
typedef struct {
  uint8_t *pixels;
  int width, height;
} RenCoverageImage;

struct GlyphSet {
  RenCoverageImage *coverage;
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


static SDL_Window *window;
static struct { int left, top, right, bottom; } clip;


static void* check_alloc(void *ptr) {
  if (!ptr) {
    fprintf(stderr, "Fatal error: memory allocation failed\n");
    exit(EXIT_FAILURE);
  }
  return ptr;
}


static const char* utf8_to_codepoint(const char *p, unsigned *dst) {
  unsigned res, n;
  switch (*p & 0xf0) {
    case 0xf0 :  res = *p & 0x07;  n = 3;  break;
    case 0xe0 :  res = *p & 0x0f;  n = 2;  break;
    case 0xd0 :
    case 0xc0 :  res = *p & 0x1f;  n = 1;  break;
    default   :  res = *p;         n = 0;  break;
  }
  while (n--) {
    res = (res << 6) | (*(++p) & 0x3f);
  }
  *dst = res;
  return p + 1;
}


void ren_init(SDL_Window *win) {
  assert(win);
  window = win;
  SDL_Surface *surf = SDL_GetWindowSurface(window);
  ren_set_clip_rect( (RenRect) { 0, 0, surf->w, surf->h } );
}


void ren_update_rects(RenRect *rects, int count) {
  SDL_UpdateWindowSurfaceRects(window, (SDL_Rect*) rects, count);
  static bool initial_frame = true;
  if (initial_frame) {
    SDL_ShowWindow(window);
    initial_frame = false;
  }
}


void ren_set_clip_rect(RenRect rect) {
  clip.left   = rect.x;
  clip.top    = rect.y;
  clip.right  = rect.x + rect.width;
  clip.bottom = rect.y + rect.height;
}


void ren_get_size(int *x, int *y) {
  SDL_Surface *surf = SDL_GetWindowSurface(window);
  *x = surf->w;
  *y = surf->h;
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

RenCoverageImage* ren_new_coverage(int width, int height, int subpixel_scale) {
  assert(width > 0 && height > 0);
  RenCoverageImage *image = malloc(sizeof(RenCoverageImage) + width * height * subpixel_scale * sizeof(uint8_t));
  check_alloc(image);
  image->pixels = (void*) (image + 1);
  image->width = width;
  image->height = height;
  return image;
}

void ren_free_image(RenImage *image) {
  free(image);
}

void ren_free_coverage(RenCoverageImage *coverage) {
  free(coverage);
}

static GlyphSet* load_glyphset(RenFont *font, int idx) {
  GlyphSet *set = check_alloc(calloc(1, sizeof(GlyphSet)));

  const int subpixel_scale = 3;

  /* init image */
  int width = 128;
  int height = 128;
retry:
  set->coverage = ren_new_coverage(width, height, subpixel_scale);

  int res = FontRendererBakeFontBitmap(font->renderer, font->height,
    (void *) set->coverage->pixels, width, height,
    idx << 8, 256, set->glyphs, subpixel_scale);

  /* retry with a larger image buffer if the buffer wasn't large enough */
  if (res < 0) {
    width *= 2;
    height *= 2;
    ren_free_coverage(set->coverage);
    goto retry;
  }

  /* adjust glyph's xadvance */
  for (int i = 0; i < 256; i++) {
    set->glyphs[i].xadvance = floor(set->glyphs[i].xadvance + 0.5);
  }

  return set;
}


static GlyphSet* get_glyphset(RenFont *font, int codepoint) {
  int idx = (codepoint >> 8) % MAX_GLYPHSET;
  if (!font->sets[idx]) {
    font->sets[idx] = load_glyphset(font, idx);
  }
  return font->sets[idx];
}


RenFont* ren_load_font(const char *filename, float size) {
  RenFont *font = NULL;

  /* init font */
  font = check_alloc(calloc(1, sizeof(RenFont)));
  font->size = size;

  const float gamma = 1.5;
  font->renderer = FontRendererNew(FONT_RENDERER_HINTING|FONT_RENDERER_SUBPIXEL, gamma);
  if (FontRendererLoadFont(font->renderer, filename)) {
    free(font);
    return NULL;
  }
  font->height = FontRendererGetFontHeight(font->renderer, size);

  /* make tab and newline glyphs invisible */
  GlyphBitmapInfo *g = get_glyphset(font, '\n')->glyphs;
  g['\t'].x1 = g['\t'].x0;
  g['\n'].x1 = g['\n'].x0;

  return font;
}


void ren_free_font(RenFont *font) {
  for (int i = 0; i < MAX_GLYPHSET; i++) {
    GlyphSet *set = font->sets[i];
    if (set) {
      ren_free_coverage(set->coverage);
      free(set);
    }
  }
  FontRendererFree(font->renderer);
  free(font);
}


void ren_set_font_tab_width(RenFont *font, int n) {
  GlyphSet *set = get_glyphset(font, '\t');
  set->glyphs['\t'].xadvance = n;
}


int ren_get_font_width(RenFont *font, const char *text) {
  int x = 0;
  const char *p = text;
  unsigned codepoint;
  while (*p) {
    p = utf8_to_codepoint(p, &codepoint);
    GlyphSet *set = get_glyphset(font, codepoint);
    GlyphBitmapInfo *g = &set->glyphs[codepoint & 0xff];
    x += g->xadvance;
  }
  return x;
}


int ren_get_font_height(RenFont *font) {
  return font->height;
}


static inline RenColor blend_pixel(RenColor dst, RenColor src) {
  int ia = 0xff - src.a;
  dst.r = ((src.r * src.a) + (dst.r * ia)) >> 8;
  dst.g = ((src.g * src.a) + (dst.g * ia)) >> 8;
  dst.b = ((src.b * src.a) + (dst.b * ia)) >> 8;
  return dst;
}


static inline RenColor blend_pixel2(RenColor dst, RenColor src, RenColor color) {
  src.a = (src.a * color.a) >> 8;
  int ia = 0xff - src.a;
  dst.r = ((src.r * color.r * src.a) >> 16) + ((dst.r * ia) >> 8);
  dst.g = ((src.g * color.g * src.a) >> 16) + ((dst.g * ia) >> 8);
  dst.b = ((src.b * color.b * src.a) >> 16) + ((dst.b * ia) >> 8);
  return dst;
}


#define rect_draw_loop(expr)        \
  for (int j = y1; j < y2; j++) {   \
    for (int i = x1; i < x2; i++) { \
      *d = expr;                    \
      d++;                          \
    }                               \
    d += dr;                        \
  }

void ren_draw_rect(RenRect rect, RenColor color) {
  if (color.a == 0) { return; }

  int x1 = rect.x < clip.left ? clip.left : rect.x;
  int y1 = rect.y < clip.top  ? clip.top  : rect.y;
  int x2 = rect.x + rect.width;
  int y2 = rect.y + rect.height;
  x2 = x2 > clip.right  ? clip.right  : x2;
  y2 = y2 > clip.bottom ? clip.bottom : y2;

  SDL_Surface *surf = SDL_GetWindowSurface(window);
  RenColor *d = (RenColor*) surf->pixels;
  d += x1 + y1 * surf->w;
  int dr = surf->w - (x2 - x1);

  if (color.a == 0xff) {
    rect_draw_loop(color);
  } else {
    rect_draw_loop(blend_pixel(*d, color));
  }
}

static void clip_point_inside_rect(int *x, int *y, RenRect *sub) {
  /* clip */
  int n;
  if ((n = clip.left - (*x)) > 0) { sub->width  -= n; sub->x += n; (*x) += n; }
  if ((n = clip.top  - (*y)) > 0) { sub->height -= n; sub->y += n; (*y) += n; }
  if ((n = (*x) + sub->width  - clip.right ) > 0) { sub->width  -= n; }
  if ((n = (*y) + sub->height - clip.bottom) > 0) { sub->height -= n; }
}

void ren_draw_image(RenImage *image, RenRect *sub, int x, int y, RenColor color) {
  if (color.a == 0) { return; }

  clip_point_inside_rect(&x, &y, sub);

  if (sub->width <= 0 || sub->height <= 0) {
    return;
  }

  /* draw */
  SDL_Surface *surf = SDL_GetWindowSurface(window);
  RenColor *s = image->pixels;
  RenColor *d = (RenColor*) surf->pixels;
  s += sub->x + sub->y * image->width;
  d += x + y * surf->w;
  int sr = image->width - sub->width;
  int dr = surf->w - sub->width;

  for (int j = 0; j < sub->height; j++) {
    for (int i = 0; i < sub->width; i++) {
      *d = blend_pixel2(*d, *s, color);
      d++;
      s++;
    }
    d += dr;
    s += sr;
  }
}

static void ren_draw_coverage_with_color(FontRenderer *renderer, RenCoverageImage *image, RenRect *sub, int x, int y, RenColor color) {
  if (color.a == 0) { return; }

  clip_point_inside_rect(&x, &y, sub);

  if (sub->width <= 0 || sub->height <= 0) {
    return;
  }

  /* draw */
  SDL_Surface *surf = SDL_GetWindowSurface(window);
  const int subpixel_scale = 3;
  uint8_t *s = image->pixels;
  RenColor *d = (RenColor*) surf->pixels;
  s += (sub->x + sub->y * image->width) * subpixel_scale;
  d += x + y * surf->w;
  const int surf_pixel_size = 4;
  FontRendererBlendGammaSubpixel(
    renderer,
    (uint8_t *) d, surf->w * surf_pixel_size,
    s, image->width * subpixel_scale,
    sub->width, sub->height,
    (FontRendererColor) { .r = color.r, .g = color.g, .b = color.b });
}

int ren_draw_text(RenFont *font, const char *text, int x, int y, RenColor color) {
  RenRect rect;
  const char *p = text;
  unsigned codepoint;
  while (*p) {
    p = utf8_to_codepoint(p, &codepoint);
    GlyphSet *set = get_glyphset(font, codepoint);
    GlyphBitmapInfo *g = &set->glyphs[codepoint & 0xff];
    rect.x = g->x0;
    rect.y = g->y0;
    rect.width = g->x1 - g->x0;
    rect.height = g->y1 - g->y0;
    ren_draw_coverage_with_color(font->renderer, set->coverage, &rect, x + g->xoff, y + g->yoff, color);
    x += g->xadvance;
  }
  return x;
}
