#include <stdio.h>
#include <stdbool.h>
#include <assert.h>
#include <math.h>
#include <ft2build.h>
#include <freetype/ftlcdfil.h>
#include <freetype/ftoutln.h>
#include FT_FREETYPE_H

#include "renderer.h"
#include "renwindow.h"

#define DIVIDE_BY_255_SIGNED(x, sign_val)  (((x) + (sign_val) + ((x)>>8)) >> 8)
#define DIVIDE_BY_255(x)    DIVIDE_BY_255_SIGNED(x, 1)
#define MAX_GLYPHSET 256
#define SUBPIXEL_BITMAPS_CACHED 3

static RenWindow window_renderer = {0};
static FT_Library library;

static void* check_alloc(void *ptr) {
  if (!ptr) {
    fprintf(stderr, "Fatal error: memory allocation failed\n");
    exit(EXIT_FAILURE);
  }
  return ptr;
}

/************************* Fonts *************************/

typedef struct {
  unsigned short x0, x1, y0, y1;
  short bitmap_left, bitmap_top;
  float xadvance;
} GlyphMetric;

typedef struct {
  SDL_Surface* surface[SUBPIXEL_BITMAPS_CACHED];
  GlyphMetric metrics[256]; 
} GlyphSet;

typedef struct RenFont {
  FT_Face face;
  GlyphSet* sets[MAX_GLYPHSET];
  float size;
  short max_height, space_advance, tab_advance;
  bool subpixel;
  ERenFontHinting hinting;
  unsigned char style;
  char path[0];
} RenFont;

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

static int font_set_load_options(RenFont* font) {
  switch (font->hinting) {
    case FONT_HINTING_SLIGHT: return FT_LOAD_TARGET_LIGHT | FT_LOAD_FORCE_AUTOHINT;
    case FONT_HINTING_FULL: return FT_LOAD_TARGET_NORMAL | FT_LOAD_FORCE_AUTOHINT;
    case FONT_HINTING_NONE: return FT_LOAD_TARGET_NORMAL | FT_LOAD_NO_HINTING;
  }
  return FT_LOAD_TARGET_NORMAL | FT_LOAD_NO_HINTING;
}

static int font_set_render_options(RenFont* font) {
  if (font->subpixel) {
    switch (font->hinting) {
      case FONT_HINTING_NONE:   FT_Library_SetLcdFilter(library, FT_LCD_FILTER_NONE); break;
      case FONT_HINTING_SLIGHT: FT_Library_SetLcdFilter(library, FT_LCD_FILTER_LIGHT); break;
      case FONT_HINTING_FULL:   FT_Library_SetLcdFilter(library, FT_LCD_FILTER_DEFAULT); break;
    }
    return FT_RENDER_MODE_LCD;
  } else {
    switch (font->hinting) {
      case FONT_HINTING_NONE:   return FT_RENDER_MODE_NORMAL; break;
      case FONT_HINTING_SLIGHT: return FT_RENDER_MODE_LIGHT; break;
      case FONT_HINTING_FULL:   return FT_RENDER_MODE_LIGHT; break;
    }
  }
  return 0;
}

static int font_set_style(FT_Outline* outline, int x_translation, unsigned char style) {
  FT_Outline_Translate(outline, x_translation, 0 );
  if (style & FONT_STYLE_BOLD)
    FT_Outline_EmboldenXY(outline, 1 << 5, 0);
  if (style & FONT_STYLE_ITALIC) {
    FT_Matrix matrix = { 1 << 16, 1 << 14, 0, 1 << 16 };
    FT_Outline_Transform(outline, &matrix);
  }
  return 0;
}

static GlyphSet* font_load_glyphset(RenFont* font, int idx) {
  GlyphSet* set = check_alloc(calloc(1, sizeof(GlyphSet)));
  unsigned int render_option = font_set_render_options(font), load_option = font_set_load_options(font);
  int pen_x = 0, bitmaps_cached = font->subpixel ? SUBPIXEL_BITMAPS_CACHED : 1;
  unsigned int byte_width = font->subpixel ? 3 : 1;
  for (int i = 0; i < 256; ++i) {
    int glyph_index = FT_Get_Char_Index( font->face, i + idx * MAX_GLYPHSET);
    if (!glyph_index || FT_Load_Glyph(font->face, glyph_index, load_option | FT_LOAD_BITMAP_METRICS_ONLY) || font_set_style(&font->face->glyph->outline, 0, font->style) || FT_Render_Glyph(font->face->glyph, render_option))
      continue;
    FT_GlyphSlot slot = font->face->glyph;
    int glyph_width = slot->bitmap.width / byte_width;
    set->metrics[i] = (GlyphMetric){ pen_x, pen_x + glyph_width, 0, slot->bitmap.rows, slot->bitmap_left, slot->bitmap_top, (slot->advance.x + slot->lsb_delta - slot->rsb_delta) / 64.0f};
    pen_x += glyph_width;
    font->max_height = slot->bitmap.rows > font->max_height ? slot->bitmap.rows : font->max_height;
    // xadvance for some reason should be computed like this.
    if (FT_Load_Glyph(font->face, glyph_index, FT_LOAD_BITMAP_METRICS_ONLY) || font_set_style(&slot->outline, 0, font->style) || FT_Render_Glyph(font->face->glyph, render_option))
      continue;
    set->metrics[i].xadvance = (slot->advance.x + slot->lsb_delta - slot->rsb_delta) / 64.0f;
      
  }
  for (int j = 0; j < bitmaps_cached; ++j) {
    set->surface[j] = check_alloc(SDL_CreateRGBSurface(0, pen_x, font->max_height, font->subpixel ? 24 : 8, 0, 0, 0, 0));
    unsigned char* pixels = set->surface[j]->pixels;
    for (int i = 0; i < 256; ++i) {
      int glyph_index = FT_Get_Char_Index(font->face, i + idx * MAX_GLYPHSET);
      if (!glyph_index || FT_Load_Glyph(font->face, glyph_index, load_option))
        continue;
      FT_GlyphSlot slot = font->face->glyph;
      font_set_style(&slot->outline, (64 / bitmaps_cached) * j, font->style);
      if (FT_Render_Glyph(slot, render_option))
        continue; 
      for (int line = 0; line < slot->bitmap.rows; ++line) {
        int target_offset = set->surface[j]->pitch * line + set->metrics[i].x0 * byte_width;
        int source_offset = line * slot->bitmap.pitch;
        memcpy(&pixels[target_offset], &slot->bitmap.buffer[source_offset], slot->bitmap.width);
      }
    }
  }
  return set;
}

static void font_free_glyphset(GlyphSet* set) {
  for (int i = 0; i < SUBPIXEL_BITMAPS_CACHED; ++i) {
    if (set->surface[i])
      SDL_FreeSurface(set->surface[i]);
  }
  free(set);
}

static GlyphSet* font_get_glyphset(RenFont* font, int codepoint) {
  int idx = (codepoint >> 8) % MAX_GLYPHSET;
  if (!font->sets[idx])
    font->sets[idx] = font_load_glyphset(font, idx);
  return font->sets[idx];
}

RenFont* ren_font_load(const char* path, float size, bool subpixel, unsigned char hinting, unsigned char style) {
  FT_Face face;
  if (FT_New_Face( library, path, 0, &face))
    return NULL;

  const int surface_scale = renwin_surface_scale(&window_renderer);
  if (FT_Set_Pixel_Sizes(face, 0, (int)(size*surface_scale)))
    goto failure;
  int len = strlen(path);
  RenFont* font = check_alloc(calloc(1, sizeof(RenFont) + len + 1));
  strcpy(font->path, path);
  font->face = face;
  font->size = size;
  font->subpixel = subpixel;
  font->hinting = hinting;
  font->style = style;
  GlyphSet* set = font_get_glyphset(font, ' ');
  font->space_advance = (int)set->metrics[' '].xadvance;
  font->tab_advance = font->space_advance * 2;
  return font;
  failure:  
  FT_Done_Face(face);
  return NULL;
}

RenFont* ren_font_copy(RenFont* font, float size) {
  return ren_font_load(font->path, size, font->subpixel, font->hinting, font->style);
}

void ren_font_free(RenFont* font) {
  for (int i = 0; i < MAX_GLYPHSET; ++i) {
    if (font->sets[i])
      font_free_glyphset(font->sets[i]);
  }
  FT_Done_Face(font->face);
  free(font);
}

void ren_font_set_tab_size(RenFont *font, int n) {
  font_get_glyphset(font, '\t')->metrics['\t'].xadvance = font->space_advance * n;
}

int ren_font_get_tab_size(RenFont *font) {
  return font_get_glyphset(font, '\t')->metrics['\t'].xadvance / font->space_advance;
}

int ren_font_get_width(RenFont *font, const char *text) {
  int width = 0;
  const char* end = text + strlen(text);
  while (text < end) {
    unsigned int codepoint;
    text = utf8_to_codepoint(text, &codepoint);
    width += font_get_glyphset(font, codepoint)->metrics[codepoint % 256].xadvance;
  }
  const int surface_scale = renwin_surface_scale(&window_renderer);
  return width / surface_scale;
}

float ren_font_get_size(RenFont *font) {
  return font->size;
}
int ren_font_get_height(RenFont *font) {
  return font->size + 3;
}

int ren_draw_text(RenFont *font, const char *text, float x, int y, RenColor color) {
  SDL_Surface *surface = renwin_get_surface(&window_renderer);
  const RenRect clip = window_renderer.clip;

  const int surface_scale = renwin_surface_scale(&window_renderer);
  float pen_x = x * surface_scale;
  y *= surface_scale;
  int bytes_per_pixel = surface->format->BytesPerPixel;
  const char* end = text + strlen(text);
  unsigned char* destination_pixels = surface->pixels;
  int clip_end_x = clip.x + clip.width, clip_end_y = clip.y + clip.height;
  while (text < end) {
    unsigned int codepoint, r, g, b;
    text = utf8_to_codepoint(text, &codepoint);
    GlyphSet* set = font_get_glyphset(font, codepoint);
    GlyphMetric* metric = &set->metrics[codepoint % 256];
    int bitmap_index = font->subpixel ? (int)(fmod(pen_x, 1.0) * SUBPIXEL_BITMAPS_CACHED) : 0;
    unsigned char* source_pixels = set->surface[bitmap_index]->pixels;
    int start_x = pen_x + metric->bitmap_left, end_x = metric->x1 - metric->x0 + pen_x;
    int glyph_end = metric->x1, glyph_start = metric->x0;
    if (color.a > 0 && end_x >= clip.x && start_x <= clip_end_x) {
      for (int line = metric->y0; line < metric->y1; ++line) {
        int target_y = line + y - metric->y0 - metric->bitmap_top + font->size * surface_scale;
        if (target_y < clip.y)
          continue;
        if (target_y >= clip_end_y)
          break;
        unsigned int* destination_pixel = (unsigned int*)&destination_pixels[surface->pitch * target_y + start_x * bytes_per_pixel];
        unsigned char* source_pixel = &source_pixels[line * set->surface[bitmap_index]->pitch + metric->x0 * (font->subpixel ? 3 : 1)];
        for (int x = glyph_start; x < glyph_end; ++x) {
          unsigned int destination_color = *destination_pixel;
          SDL_Color dst = { (destination_color >> 16) & 0xFF, (destination_color >> 8) & 0xFF, (destination_color >> 0) & 0xFF, (destination_color >> 24) & 0xFF };
          if (font->subpixel) {
            SDL_Color src = { *source_pixel++, *source_pixel++, *source_pixel++ };
            r = color.r * src.r + dst.r * (255 - src.r) + 127;
            r = DIVIDE_BY_255(r);
            g = color.g * src.g + dst.g * (255 - src.g) + 127;
            g = DIVIDE_BY_255(g);
            b = color.b * src.b + dst.b * (255 - src.b) + 127;
            b = DIVIDE_BY_255(b);
          } else {
            unsigned char intensity = *source_pixel++;
            r = color.r * intensity + dst.r * (255 - intensity) + 127;
            r = DIVIDE_BY_255(r);
            g = color.g * intensity + dst.g * (255 - intensity) + 127;
            g = DIVIDE_BY_255(g);
            b = color.b * intensity + dst.b * (255 - intensity) + 127;
            b = DIVIDE_BY_255(b);
          }
          *destination_pixel++ = dst.a << 24 | r << 16 | g << 8 | b;
        }
      }
    }
    pen_x += metric->xadvance ? metric->xadvance : font->space_advance;
  }
  if (font->style & FONT_STYLE_UNDERLINE)
    ren_draw_rect((RenRect){ x, y / surface_scale + ren_font_get_height(font) - 1, (pen_x - x) / surface_scale, 1 }, color);
  return pen_x / surface_scale;
}

/******************* Rectangles **********************/
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

  const int surface_scale = renwin_surface_scale(&window_renderer);

  /* transforms coordinates in pixels. */
  rect.x      *= surface_scale;
  rect.y      *= surface_scale;
  rect.width  *= surface_scale;
  rect.height *= surface_scale;

  const RenRect clip = window_renderer.clip;
  int x1 = rect.x < clip.x ? clip.x : rect.x;
  int y1 = rect.y < clip.y ? clip.y : rect.y;
  int x2 = rect.x + rect.width;
  int y2 = rect.y + rect.height;
  x2 = x2 > clip.x + clip.width ? clip.x + clip.width : x2;
  y2 = y2 > clip.y + clip.height ? clip.y + clip.height : y2;

  SDL_Surface *surface = renwin_get_surface(&window_renderer);
  RenColor *d = (RenColor*) surface->pixels;
  d += x1 + y1 * surface->w;
  int dr = surface->w - (x2 - x1);

  if (color.a == 0xff) {
    SDL_Rect rect = { x1, y1, x2 - x1, y2 - y1 };
    SDL_FillRect(surface, &rect, SDL_MapRGBA(surface->format, color.r, color.g, color.b, color.a));
  } else {
    rect_draw_loop(blend_pixel(*d, color));
  }
}

/*************** Window Management ****************/
void ren_free_window_resources() {
  renwin_free(&window_renderer);
}

void ren_init(SDL_Window *win) {
  assert(win);
  int error = FT_Init_FreeType( &library );
  if ( error ) {
    fprintf(stderr, "internal font error when starting the application\n");
    return;
  }
  window_renderer.window = win;
  renwin_init_surface(&window_renderer);
  renwin_clip_to_surface(&window_renderer);
}


void ren_resize_window() {
  renwin_resize_surface(&window_renderer);
}


void ren_update_rects(RenRect *rects, int count) {
  static bool initial_frame = true;
  if (initial_frame) {
    renwin_show_window(&window_renderer);
    initial_frame = false;
  }
  renwin_update_rects(&window_renderer, rects, count);
}


void ren_set_clip_rect(RenRect rect) {
  renwin_set_clip_rect(&window_renderer, rect);
}


void ren_get_size(int *x, int *y) {
  RenWindow *ren = &window_renderer;
  const int scale = renwin_surface_scale(ren);
  SDL_Surface *surface = renwin_get_surface(ren);
  *x = surface->w / scale;
  *y = surface->h / scale;
}

