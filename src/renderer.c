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


struct Renderer {
  SDL_Window *window;
  SDL_Renderer *renderer;
  SDL_Texture *texture;
  SDL_Surface *surface;
  FR_Clip_Area clip; /* Clipping rect in pixel coordinates. */
  int surface_scale;
};

static struct Renderer renderer = {0};

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


static int get_surface_scale() {
  int w_pixels, h_pixels;
  int w_points, h_points;
  SDL_GL_GetDrawableSize(renderer.window, &w_pixels, &h_pixels);
  SDL_GetWindowSize(renderer.window, &w_points, &h_points);
  /* We consider that the ratio pixel/point will always be an integer and
     it is the same along the x and the y axis. */
  assert(w_pixels % w_points == 0 && h_pixels % h_points == 0 && w_pixels / w_points == h_pixels / h_points);
  return w_pixels / w_points;
}


static FR_Clip_Area scaled_clip(const RenRect rect, const int scale) {
  return (FR_Clip_Area) {rect.x * scale, rect.y * scale, (rect.x + rect.width) * scale, (rect.y + rect.height) * scale};
}


static void init_window_surface() {
  if (renderer.surface) {
    SDL_FreeSurface(renderer.surface);
  }
  int w, h;
  SDL_GL_GetDrawableSize(renderer.window, &w, &h);
  renderer.surface = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_BGRA32);
  renderer.clip = scaled_clip((RenRect) { 0, 0, w, h }, 1);
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
  SDL_DestroyWindow(renderer.window);
  SDL_DestroyRenderer(renderer.renderer);
  SDL_DestroyTexture(renderer.texture);
  renderer.window = NULL;
  renderer.renderer = NULL;
}

static void setup_renderer(int w, int h) {
  /* Note that w and h here should always be in pixels and obtained from
     a call to SDL_GL_GetDrawableSize(). */
  if (renderer.renderer) {
    SDL_DestroyRenderer(renderer.renderer);
    SDL_DestroyTexture(renderer.texture);
  }
  renderer.renderer = SDL_CreateRenderer(renderer.window, -1, 0);
  // May be we could use: SDL_CreateTextureFromSurface(sdlRenderer, mySurface);
  renderer.texture = SDL_CreateTexture(renderer.renderer, SDL_PIXELFORMAT_BGRA32, SDL_TEXTUREACCESS_STREAMING, w, h);
  renderer.surface_scale = get_surface_scale();
}

void ren_init(SDL_Window *win) {
  assert(win);
  renderer.window = win;
  init_window_surface();
  renderer.surface_scale = get_surface_scale();
}


void ren_setup_renderer() {
  int new_w, new_h;
  SDL_GL_GetDrawableSize(renderer.window, &new_w, &new_h);
  /* Note that (w, h) may differ from (new_w, new_h) on retina displays. */
  if (new_w != renderer.surface->w || new_h != renderer.surface->h) {
    init_window_surface();
    setup_renderer(new_w, new_h);
  }
}


void ren_update_rects(RenRect *rects, int count) {
  static bool initial_frame = true;
  if (initial_frame) {
    int w, h;
    SDL_ShowWindow(renderer.window);
    SDL_GL_GetDrawableSize(renderer.window, &w, &h);
    setup_renderer(w, h);
    initial_frame = false;
  }

  const int scale = renderer.surface_scale;
  for (int i = 0; i < count; i++) {
    const RenRect *r = &rects[i];
    const int x = scale * r->x, y = scale * r->y;
    const int w = scale * r->width, h = scale * r->height;
    const SDL_Rect sr = {.x = x, .y = y, .w = w, .h = h};
    int32_t *pixels = ((int32_t *) renderer.surface->pixels) + x + renderer.surface->w * y;
    SDL_UpdateTexture(renderer.texture, &sr, pixels, renderer.surface->w * 4);
  }
  SDL_RenderCopy(renderer.renderer, renderer.texture, NULL, NULL);
  SDL_RenderPresent(renderer.renderer);
}


void ren_set_clip_rect(RenRect rect) {
  renderer.clip = scaled_clip(rect, renderer.surface_scale);
}


void ren_get_size(int *x, int *y) {
  const int scale = renderer.surface_scale;
  *x = renderer.surface->w / scale;
  *y = renderer.surface->h / scale;
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


int ren_verify_font(const char *filename) {
  RenFont font[1];
  font->renderer = FR_Renderer_New(0);
  if (FR_Load_Font(font->renderer, filename)) {
    return 1;
  }
  FR_Renderer_Free(font->renderer);
  return 0;
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


/* Important: if subpixel_scale is NULL we will return width in points. Otherwise we will
   return width in subpixels. */
int ren_get_font_width(FontDesc *font_desc, const char *text, int *subpixel_scale) {
  int x = 0;
  const char *p = text;
  unsigned codepoint;
  const int surface_scale = renderer.surface_scale;
  RenFont *font = font_desc_get_font_at_scale(font_desc, surface_scale);
  while (*p) {
    p = utf8_to_codepoint(p, &codepoint);
    GlyphSet *set = get_glyphset(font, codepoint);
    FR_Bitmap_Glyph_Metrics *g = &set->glyphs[codepoint & 0xff];
    x += g->xadvance;
  }
  /* At this point here x is in subpixel units */
  const int x_scale_to_points = FR_Subpixel_Scale(font->renderer) * surface_scale;
  if (subpixel_scale) {
    *subpixel_scale = x_scale_to_points;
    return x;
  }
  return (x + x_scale_to_points / 2) / x_scale_to_points;
}


int ren_get_font_height(FontDesc *font_desc) {
  const int surface_scale = renderer.surface_scale;
  RenFont *font = font_desc_get_font_at_scale(font_desc, surface_scale);
  return (font->height + surface_scale / 2) / surface_scale;
}


static inline RenColor blend_pixel(RenColor dst, RenColor src) {
  int ia = 0xff - src.a;
  dst.r = ((src.r * src.a) + (dst.r * ia)) >> 8;
  dst.g = ((src.g * src.a) + (dst.g * ia)) >> 8;
  dst.b = ((src.b * src.a) + (dst.b * ia)) >> 8;
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

  const int surface_scale = renderer.surface_scale;

  /* transforms coordinates in pixels. */
  rect.x      *= surface_scale;
  rect.y      *= surface_scale;
  rect.width  *= surface_scale;
  rect.height *= surface_scale;

  int x1 = rect.x < renderer.clip.left ? renderer.clip.left : rect.x;
  int y1 = rect.y < renderer.clip.top  ? renderer.clip.top  : rect.y;
  int x2 = rect.x + rect.width;
  int y2 = rect.y + rect.height;
  x2 = x2 > renderer.clip.right  ? renderer.clip.right  : x2;
  y2 = y2 > renderer.clip.bottom ? renderer.clip.bottom : y2;

  RenColor *d = (RenColor*) renderer.surface->pixels;
  d += x1 + y1 * renderer.surface->w;
  int dr = renderer.surface->w - (x2 - x1);

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

static void draw_text_impl(RenFont *font, const char *text, int x_subpixel, int y_pixel, RenColor color,
  CPReplaceTable *replacements, RenColor replace_color)
{
  SDL_Surface *surf = renderer.surface;
  const char *p = text;
  unsigned codepoint;
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
      FR_Blend_Glyph(font->renderer, &renderer.clip,
        x_subpixel, y_pixel, (uint8_t *) surf->pixels, surf->w, set->image, g, color_rep);
    }
    x_subpixel += xadvance_original_cp;
  }
}


void ren_draw_text_subpixel(FontDesc *font_desc, const char *text, int x_subpixel, int y, RenColor color,
  CPReplaceTable *replacements, RenColor replace_color)
{
  const int surface_scale = renderer.surface_scale;
  RenFont *font = font_desc_get_font_at_scale(font_desc, surface_scale);
  draw_text_impl(font, text, x_subpixel, surface_scale * y, color, replacements, replace_color);
}

void ren_draw_text(FontDesc *font_desc, const char *text, int x, int y, RenColor color,
  CPReplaceTable *replacements, RenColor replace_color)
{
  const int surface_scale = renderer.surface_scale;
  RenFont *font = font_desc_get_font_at_scale(font_desc, surface_scale);
  const int subpixel_scale = surface_scale * FR_Subpixel_Scale(font->renderer);
  draw_text_impl(font, text, subpixel_scale * x, surface_scale * y, color, replacements, replace_color);
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


int ren_get_font_subpixel_scale(FontDesc *font_desc) {
  const int surface_scale = renderer.surface_scale;
  RenFont *font = font_desc_get_font_at_scale(font_desc, surface_scale);
  return FR_Subpixel_Scale(font->renderer) * surface_scale;
}
