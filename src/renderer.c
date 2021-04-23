#include <stdio.h>
#include <stdbool.h>
#include <assert.h>
#include <math.h>
#include "renderer.h"
#include "font_renderer.h"

#define MAX_GLYPHSET 256
#define REPLACEMENT_CHUNK_SIZE 8

struct RenImage {
  RenColor *pixels;
  int width, height;
};

struct GlyphSet {
  FR_Bitmap *image;
  FR_Bitmap_Glyph_Metrics glyphs[256];
};
typedef struct GlyphSet GlyphSet;

/* The field "padding" below must be there just before GlyphSet *sets[MAX_GLYPHSET]
   because the field "sets" can be indexed and writted with an index -1. For this
   reason the "padding" field must be there but is never explicitly used. */
struct RenFont {
  GlyphSet *padding;
  GlyphSet *sets[MAX_GLYPHSET];
  float size;
  int height;
  int space_advance;
  FR_Renderer *renderer;
};


static SDL_Window *window;
static SDL_Renderer *window_renderer = NULL;
static SDL_Texture *window_texture = NULL;
static SDL_Surface *window_surface = NULL;
static int window_w = -1, window_h = -1;

static FR_Clip_Area clip;

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


static void init_window_surface() {
  if (window_surface) {
    SDL_FreeSurface(window_surface);
  }
  SDL_GL_GetDrawableSize(window, &window_w, &window_h);
  window_surface = SDL_CreateRGBSurfaceWithFormat(0, window_w, window_h, 32, SDL_PIXELFORMAT_BGRA32);
  ren_set_clip_rect( (RenRect) { 0, 0, window_w, window_h } );
}


static SDL_Surface *get_window_surface() {
  return window_surface;
}


void ren_cp_replace_init(CPReplaceTable *rep_table) {
  rep_table->size = 0;
  rep_table->replacements = NULL;
}


void ren_cp_replace_free(CPReplaceTable *rep_table) {
  free(rep_table->replacements);
}


void ren_cp_replace_add(CPReplaceTable *rep_table, const char *src, const char *dst) {
  int table_size = rep_table->size;
  if (table_size % REPLACEMENT_CHUNK_SIZE == 0) {
    CPReplace *old_replacements = rep_table->replacements;
    const int new_size = (table_size / REPLACEMENT_CHUNK_SIZE + 1) * REPLACEMENT_CHUNK_SIZE;
    rep_table->replacements = malloc(new_size * sizeof(CPReplace));
    if (!rep_table->replacements) {
      rep_table->replacements = old_replacements;
      return;
    }
    memcpy(rep_table->replacements, old_replacements, table_size * sizeof(CPReplace));
    free(old_replacements);
  }
  CPReplace *rep = &rep_table->replacements[table_size];
  utf8_to_codepoint(src, &rep->codepoint_src);
  utf8_to_codepoint(dst, &rep->codepoint_dst);
  rep_table->size = table_size + 1;
}

void ren_free_window_resources() {
  SDL_DestroyWindow(window);
  SDL_DestroyRenderer(window_renderer);
  SDL_DestroyTexture(window_texture);
  window = NULL;
  window_renderer = NULL;
}

static void setup_renderer(int w, int h) {
  /* Note that w and h here should always be in pixels and obtained from
     a call to SDL_GL_GetDrawableSize(). */
  if (window_renderer) {
    SDL_DestroyRenderer(window_renderer);
    SDL_DestroyTexture(window_texture);
  }
  window_renderer = SDL_CreateRenderer(window, -1, 0);
  // May be we could use: SDL_CreateTextureFromSurface(sdlRenderer, mySurface);
  window_texture = SDL_CreateTexture(window_renderer, SDL_PIXELFORMAT_BGRA32, SDL_TEXTUREACCESS_STREAMING, w, h);
}

void ren_init(SDL_Window *win) {
  assert(win);
  window = win;
  init_window_surface();
}


void ren_resize(int w, int h) {
  int new_w, new_h;
  SDL_GL_GetDrawableSize(window, &new_w, &new_h);
  /* Note that (w, h) may differ from (new_w, new_h) on retina displays. */
  if (new_w != window_h || new_h != window_h) {
    init_window_surface();
    setup_renderer(new_w, new_h);
  }
}


void ren_update_rects(RenRect *rects, int count) {
  static bool initial_frame = true;
  if (initial_frame) {
    int w, h;
    SDL_ShowWindow(window);
    SDL_GL_GetDrawableSize(window, &w, &h);
    setup_renderer(w, h);
    initial_frame = false;
  }

  // FIXME: we ignore the rects here.
  SDL_UpdateTexture(window_texture, NULL, window_surface->pixels, window_w * 4);
  SDL_RenderCopy(window_renderer, window_texture, NULL, NULL);
  SDL_RenderPresent(window_renderer);
}


void ren_set_clip_rect(RenRect rect) {
  clip.left   = rect.x;
  clip.top    = rect.y;
  clip.right  = rect.x + rect.width;
  clip.bottom = rect.y + rect.height;
}


void ren_get_size(int *x, int *y) {
  SDL_Surface *surf = get_window_surface(window);
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

void ren_free_image(RenImage *image) {
  free(image);
}

static GlyphSet* load_glyphset(RenFont *font, int idx) {
  GlyphSet *set = check_alloc(calloc(1, sizeof(GlyphSet)));

  set->image = FR_Bake_Font_Bitmap(font->renderer, font->height, idx << 8, 256, set->glyphs);
  check_alloc(set->image);

  return set;
}


static GlyphSet* get_glyphset(RenFont *font, int codepoint) {
  int idx = (codepoint >> 8) % MAX_GLYPHSET;
  if (!font->sets[idx]) {
    font->sets[idx] = load_glyphset(font, idx);
  }
  return font->sets[idx];
}


RenFont* ren_load_font(const char *filename, float size, unsigned int renderer_flags) {
  RenFont *font = NULL;

  /* init font */
  font = check_alloc(calloc(1, sizeof(RenFont)));
  font->size = size;

  unsigned int fr_renderer_flags = 0;
  if ((renderer_flags & RenFontAntialiasingMask) == RenFontSubpixel) {
    fr_renderer_flags |= FR_SUBPIXEL;
  }
  if ((renderer_flags & RenFontHintingMask) == RenFontHintingSlight) {
    fr_renderer_flags |= (FR_HINTING | FR_PRESCALE_X);
  } else if ((renderer_flags & RenFontHintingMask) == RenFontHintingFull) {
    fr_renderer_flags |= FR_HINTING;
  }
  font->renderer = FR_Renderer_New(fr_renderer_flags);
  if (FR_Load_Font(font->renderer, filename)) {
    free(font);
    return NULL;
  }
  font->height = FR_Get_Font_Height(font->renderer, size);

  FR_Bitmap_Glyph_Metrics *gs = get_glyphset(font, ' ')->glyphs;
  font->space_advance = gs[' '].xadvance;

  /* make tab and newline glyphs invisible */
  FR_Bitmap_Glyph_Metrics *g = get_glyphset(font, '\n')->glyphs;
  g['\t'].x1 = g['\t'].x0;
  g['\n'].x1 = g['\n'].x0;

  return font;
}


void ren_free_font(RenFont *font) {
  for (int i = 0; i < MAX_GLYPHSET; i++) {
    GlyphSet *set = font->sets[i];
    if (set) {
      FR_Bitmap_Free(set->image);
      free(set);
    }
  }
  FR_Renderer_Free(font->renderer);
  free(font);
}


void ren_set_font_tab_size(RenFont *font, int n) {
  GlyphSet *set = get_glyphset(font, '\t');
  set->glyphs['\t'].xadvance = font->space_advance * n;
}


int ren_get_font_tab_size(RenFont *font) {
  GlyphSet *set = get_glyphset(font, '\t');
  return set->glyphs['\t'].xadvance / font->space_advance;
}


int ren_get_font_width(RenFont *font, const char *text, int *subpixel_scale) {
  int x = 0;
  const char *p = text;
  unsigned codepoint;
  while (*p) {
    p = utf8_to_codepoint(p, &codepoint);
    GlyphSet *set = get_glyphset(font, codepoint);
    FR_Bitmap_Glyph_Metrics *g = &set->glyphs[codepoint & 0xff];
    x += g->xadvance;
  }
  if (subpixel_scale) {
    *subpixel_scale = FR_Subpixel_Scale(font->renderer);
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

  SDL_Surface *surf = get_window_surface(window);
  RenColor *d = (RenColor*) surf->pixels;
  d += x1 + y1 * surf->w;
  int dr = surf->w - (x2 - x1);

  if (color.a == 0xff) {
    rect_draw_loop(color);
  } else {
    rect_draw_loop(blend_pixel(*d, color));
  }
}


static int codepoint_replace(CPReplaceTable *rep_table, unsigned *codepoint) {
  for (int i = 0; i < rep_table->size; i++) {
    const CPReplace *rep = &rep_table->replacements[i];
    if (*codepoint == rep->codepoint_src) {
      *codepoint = rep->codepoint_dst;
      return 1;
    }
  }
  return 0;
}


void ren_draw_text_subpixel(RenFont *font, const char *text, int x_subpixel, int y, RenColor color,
  CPReplaceTable *replacements, RenColor replace_color)
{
  const char *p = text;
  unsigned codepoint;
  SDL_Surface *surf = get_window_surface(window);
  const FR_Color color_fr = { .r = color.r, .g = color.g, .b = color.b };
  while (*p) {
    FR_Color color_rep;
    p = utf8_to_codepoint(p, &codepoint);
    GlyphSet *set = get_glyphset(font, codepoint);
    FR_Bitmap_Glyph_Metrics *g = &set->glyphs[codepoint & 0xff];
    const int xadvance_original_cp = g->xadvance;
    const int replaced = replacements ? codepoint_replace(replacements, &codepoint) : 0;
    if (replaced) {
      set = get_glyphset(font, codepoint);
      g = &set->glyphs[codepoint & 0xff];
      color_rep = (FR_Color) { .r = replace_color.r, .g = replace_color.g, .b = replace_color.b};
    } else {
      color_rep = color_fr;
    }
    if (color.a != 0) {
      FR_Blend_Glyph(font->renderer, &clip,
        x_subpixel, y, (uint8_t *) surf->pixels, surf->w, set->image, g, color_rep);
    }
    x_subpixel += xadvance_original_cp;
  }
}

void ren_draw_text(RenFont *font, const char *text, int x, int y, RenColor color,
  CPReplaceTable *replacements, RenColor replace_color)
{
  const int subpixel_scale = FR_Subpixel_Scale(font->renderer);
  ren_draw_text_subpixel(font, text, subpixel_scale * x, y, color, replacements, replace_color);
}

// Could be declared as static inline
int ren_font_subpixel_round(int width, int subpixel_scale, int orientation) {
  int w_mult;
  if (orientation < 0) {
    w_mult = width;
  } else if (orientation == 0) {
    w_mult = width + subpixel_scale / 2;
  } else {
    w_mult = width + subpixel_scale - 1;
  }
  return w_mult / subpixel_scale;
}


int ren_get_font_subpixel_scale(RenFont *font) {
  return FR_Subpixel_Scale(font->renderer);
}

