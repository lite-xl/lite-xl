#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <assert.h>
#include <math.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_LCD_FILTER_H
#include FT_OUTLINE_H
#include FT_SYSTEM_H

#ifdef _WIN32
#include <windows.h>
#include "utfconv.h"
#endif

#include "renderer.h"
#include "renwindow.h"

// uncomment the line below for more debugging information through printf
// #define RENDERER_DEBUG

static RenWindow **window_list = NULL;
static size_t window_count = 0;

// draw_rect_surface is used as a 1x1 surface to simplify ren_draw_rect with blending
static SDL_Surface *draw_rect_surface = NULL;
static FT_Library library = NULL;

#define check_alloc(P) _check_alloc(P, __FILE__, __LINE__)
static void* _check_alloc(void *ptr, const char *const file, size_t ln) {
  if (!ptr) {
    fprintf(stderr, "%s:%zu: memory allocation failed\n", file, ln);
    exit(EXIT_FAILURE);
  }
  return ptr;
}

/************************* Fonts *************************/

// approximate number of glyphs per atlas surface
#define GLYPH_PER_ATLAS 256
// some padding to add to atlas surface to store more glyphs
#define FONT_HEIGHT_OVERFLOW_PX 6
#define FONT_WIDTH_OVERFLOW_PX 6

// maximum unicode codepoint supported (https://stackoverflow.com/a/52203901)
#define MAX_UNICODE 0x10FFFF
// number of rows and columns in the codepoint map
#define CHARMAP_ROW 128
#define CHARMAP_COL (MAX_UNICODE / CHARMAP_ROW)

// the maximum number of glyphs for OpenType
#define MAX_GLYPHS 65535
// number of rows and columns in the glyph map
#define GLYPHMAP_ROW 128
#define GLYPHMAP_COL (MAX_GLYPHS / GLYPHMAP_ROW)

// number of subpixel bitmaps
#define SUBPIXEL_BITMAPS_CACHED 3

// special indexes that is used for glyph and atlas index
#define BITMAP_NOT_AVAILABLE ((unsigned short) -1)

// metrics for a loaded glyph
typedef struct {
  // 0 is a valid atlas and surface index. To check if a glyph is not loaded,
  // also check if x == y == 0, because for loaded glyphs with no bitmap,
  // atlas and surface index is set to BITMAP_NOT_AVAILABLE, and x and y are set to 0.
  unsigned short atlas_idx, surface_idx;
  unsigned int x0, x1, y0, y1;
  int bitmap_left, bitmap_top;
  float xadvance;
} GlyphMetric;

// maps codepoints -> glyph IDs
typedef struct {
  unsigned int *rows[CHARMAP_ROW];
} CharMap;

// a bitmap atlas with a fixed width, each surface acting as a bump allocator
typedef struct {
  SDL_Surface **surfaces;
  unsigned int width, nsurface, offset_y;
} GlyphAtlas;

// maps glyph IDs -> glyph metrics
typedef struct {
  // accessed with metrics[bitmap_idx][glyph_id / nrow][glyph_id - (row * ncol)]
  GlyphMetric *metrics[SUBPIXEL_BITMAPS_CACHED][GLYPHMAP_ROW];
  // accessed with atlas[bitmap_idx][atlas_idx].surfaces[surface_idx]
  GlyphAtlas *atlas[SUBPIXEL_BITMAPS_CACHED];
  size_t natlas, bytesize;
} GlyphMap;

typedef struct RenFont {
  FT_Face face;
  CharMap charmap;
  GlyphMap glyphs;
#ifdef LITE_USE_SDL_RENDERER
  int scale;
#endif
  float size, space_advance;
  unsigned short max_height, baseline, height, tab_size;
  unsigned short underline_thickness;
  ERenFontAntialiasing antialiasing;
  ERenFontHinting hinting;
  unsigned char style;
  char path[];
} RenFont;

#ifdef LITE_USE_SDL_RENDERER
void update_font_scale(RenWindow *window_renderer, RenFont **fonts) {
  if (window_renderer == NULL) return;
  const int surface_scale = renwin_get_surface(window_renderer).scale;
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; ++i) {
    if (fonts[i]->scale != surface_scale) {
      ren_font_group_set_size(fonts, fonts[0]->size, surface_scale);
      return;
    }
  }
}
#endif

static const char* utf8_to_codepoint(const char *p, unsigned *dst) {
  const unsigned char *up = (unsigned char*)p;
  unsigned res, n;
  switch (*p & 0xf0) {
    case 0xf0 :  res = *up & 0x07;  n = 3;  break;
    case 0xe0 :  res = *up & 0x0f;  n = 2;  break;
    case 0xd0 :
    case 0xc0 :  res = *up & 0x1f;  n = 1;  break;
    default   :  res = *up;         n = 0;  break;
  }
  while (n--) {
    res = (res << 6) | (*(++up) & 0x3f);
  }
  *dst = res;
  return (const char*)up + 1;
}

static int font_set_load_options(RenFont* font) {
  int load_target = font->antialiasing == FONT_ANTIALIASING_NONE ? FT_LOAD_TARGET_MONO
    : (font->hinting == FONT_HINTING_SLIGHT ? FT_LOAD_TARGET_LIGHT : FT_LOAD_TARGET_NORMAL);
  int hinting = font->hinting == FONT_HINTING_NONE ? FT_LOAD_NO_HINTING : FT_LOAD_FORCE_AUTOHINT;
  return load_target | hinting;
}

static int font_set_render_options(RenFont* font) {
  if (font->antialiasing == FONT_ANTIALIASING_NONE)
    return FT_RENDER_MODE_MONO;
  if (font->antialiasing == FONT_ANTIALIASING_SUBPIXEL) {
    unsigned char weights[] = { 0x10, 0x40, 0x70, 0x40, 0x10 } ;
    switch (font->hinting) {
      case FONT_HINTING_NONE: FT_Library_SetLcdFilter(library, FT_LCD_FILTER_NONE); break;
      case FONT_HINTING_SLIGHT:
      case FONT_HINTING_FULL: FT_Library_SetLcdFilterWeights(library, weights); break;
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
  if (style & FONT_STYLE_SMOOTH)
    FT_Outline_Embolden(outline, 1 << 5);
  if (style & FONT_STYLE_BOLD)
    FT_Outline_EmboldenXY(outline, 1 << 5, 0);
  if (style & FONT_STYLE_ITALIC) {
    FT_Matrix matrix = { 1 << 16, 1 << 14, 0, 1 << 16 };
    FT_Outline_Transform(outline, &matrix);
  }
  return 0;
}

static unsigned int font_get_glyph_id(RenFont *font, unsigned int codepoint) {
  if (codepoint > MAX_UNICODE) return 0;
  size_t row = codepoint / CHARMAP_COL;
  size_t col = codepoint - (row * CHARMAP_COL);
  if (!font->charmap.rows[row]) font->charmap.rows[row] = check_alloc(calloc(sizeof(unsigned int), CHARMAP_COL));
  if (font->charmap.rows[row][col] == 0) {
    unsigned int glyph_id = FT_Get_Char_Index(font->face, codepoint);
    // use -1 as a sentinel value for "glyph not available", a bit risky, but OpenType
    // uses uint16 to store glyph IDs. In theory this cannot ever be reached
    font->charmap.rows[row][col] = glyph_id ? glyph_id : (unsigned int) -1;
  }
  return font->charmap.rows[row][col] == (unsigned int) -1 ? 0 : font->charmap.rows[row][col];
}

#define FONT_IS_SUBPIXEL(F) ((F)->antialiasing == FONT_ANTIALIASING_SUBPIXEL)
#define FONT_BITMAP_COUNT(F) ((F)->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? SUBPIXEL_BITMAPS_CACHED : 1)

static int font_load_glyph(RenFont *font, unsigned int glyph_id) {
  unsigned int render_option = font_set_render_options(font);
  unsigned int load_option = font_set_load_options(font);
  // load the font without hinting to fix an issue with monospaced fonts,
  // because freetype doesn't report the correct LSB and RSB delta. Transformation & subpixel positioning don't affect
  // the xadvance, so we can save some time by not doing this step multiple times
  if (FT_Load_Glyph(font->face, glyph_id, (load_option | FT_LOAD_BITMAP_METRICS_ONLY | FT_LOAD_NO_HINTING) & ~FT_LOAD_FORCE_AUTOHINT) != 0)
    return -1;
  double unhinted_xadv = font->face->glyph->advance.x / 64.0f;
  // render the glyph for all bitmap
  int bitmaps = FONT_BITMAP_COUNT(font);
  int row = glyph_id / GLYPHMAP_COL, col = glyph_id - (row * GLYPHMAP_COL);
  for (int bitmap_idx = 0; bitmap_idx < bitmaps; bitmap_idx++) {
    FT_GlyphSlot slot = font->face->glyph;
    if (FT_Load_Glyph(font->face, glyph_id, load_option | FT_LOAD_BITMAP_METRICS_ONLY) != 0
      || font_set_style(&slot->outline, bitmap_idx * (64 / SUBPIXEL_BITMAPS_CACHED), font->style) != 0
      || FT_Render_Glyph(slot, render_option) != 0)
    return -1;

    GlyphMetric metric = {0};
    metric.surface_idx = metric.atlas_idx = BITMAP_NOT_AVAILABLE; // overridden later
    metric.xadvance = unhinted_xadv;

    // if this bitmap is empty, or has a format we don't support, just store the xadvance
    if (!slot->bitmap.width || !slot->bitmap.rows ||
        (slot->bitmap.pixel_mode != FT_PIXEL_MODE_MONO
          && slot->bitmap.pixel_mode != FT_PIXEL_MODE_GRAY
          && slot->bitmap.pixel_mode != FT_PIXEL_MODE_LCD))
      goto save_metrics;
    
    unsigned int glyph_width = slot->bitmap.width / bitmaps;
    // FT_PIXEL_MODE_MONO uses 1 bit per pixel packed bitmap
    if (slot->bitmap.pixel_mode == FT_PIXEL_MODE_MONO) glyph_width *= 8;

    metric.x1 = glyph_width;
    metric.y1 = slot->bitmap.rows;
    metric.bitmap_left = slot->bitmap_left;
    metric.bitmap_top = slot->bitmap_top;

    // get an atlas with the correct height
    int atlas_idx = -1;
    for (int i = 0; i < font->glyphs.natlas; i++) {
      if (font->glyphs.atlas[bitmap_idx][i].width >= metric.x1) {
        atlas_idx = i;
        break;
      }
    }
    if (atlas_idx < 0) {
      // create a new atlas with the correct width, for each subpixel bitmap  
      for (int i = 0; i < bitmaps; i++) {
        font->glyphs.atlas[i] = check_alloc(realloc(font->glyphs.atlas[i], sizeof(GlyphAtlas) * (font->glyphs.natlas + 1)));
        font->glyphs.atlas[i][font->glyphs.natlas] = (GlyphAtlas) {
          .width = metric.x1 + FONT_WIDTH_OVERFLOW_PX, .offset_y = 0,
          .surfaces = NULL,                            .nsurface = 0,
        };
      }
      font->glyphs.bytesize += sizeof(GlyphAtlas);
      atlas_idx = font->glyphs.natlas++;
    }
    metric.atlas_idx = atlas_idx;
    GlyphAtlas *atlas = &font->glyphs.atlas[bitmap_idx][atlas_idx];

    // check if the surface can fit the glyph
    int surface_idx = atlas->nsurface - 1;
    if (!atlas->nsurface || metric.y1 > atlas->surfaces[surface_idx]->h - atlas->offset_y) {
      // allocate a new surface array
      int h = FONT_HEIGHT_OVERFLOW_PX + (double) font->face->size->metrics.height / 64.0f;
      if (h <= FONT_HEIGHT_OVERFLOW_PX) h += slot->bitmap.rows;
      if (h <= FONT_HEIGHT_OVERFLOW_PX) h += font->size;
      atlas->surfaces = check_alloc(realloc(atlas->surfaces, sizeof(SDL_Surface *) * (atlas->nsurface + 1)));
      atlas->surfaces[atlas->nsurface] = check_alloc(SDL_CreateRGBSurface(
        0, atlas->width, GLYPH_PER_ATLAS * h, bitmaps * 8,
        0, 0, 0, 0
      ));
      atlas->offset_y = 0;
      surface_idx = atlas->nsurface++;
      font->glyphs.bytesize += (sizeof(SDL_Surface *) + sizeof(SDL_Surface) + atlas->width * GLYPH_PER_ATLAS * h * bitmaps);
    }
    metric.surface_idx = surface_idx;
    metric.y0 = atlas->offset_y;
    atlas->offset_y += metric.y1;
    metric.y1 = atlas->offset_y;

    // copy the glyph to surface
    SDL_Surface *surface = atlas->surfaces[metric.surface_idx];
    uint8_t* pixels = surface->pixels;
    for (unsigned int line = 0; line < slot->bitmap.rows; ++line) {
      int target_offset = (surface->pitch * (line + metric.y0)) + (metric.x0 * surface->format->BytesPerPixel);
      int source_offset = line * slot->bitmap.pitch;  
      if (font->antialiasing == FONT_ANTIALIASING_NONE) {
        for (unsigned int column = 0; column < slot->bitmap.width; ++column) {
          int current_source_offset = source_offset + (column / 8);
          int source_pixel = slot->bitmap.buffer[current_source_offset];
          pixels[++target_offset] = ((source_pixel >> (7 - (column % 8))) & 0x1) * 0xFF;
        }
      } else {
        memcpy(&pixels[target_offset], &slot->bitmap.buffer[source_offset], slot->bitmap.width);
      }
    }

save_metrics:
    // save the metrics
    if (!font->glyphs.metrics[bitmap_idx][row]) {
      font->glyphs.metrics[bitmap_idx][row] = check_alloc(calloc(sizeof(GlyphMetric), GLYPHMAP_COL));
      font->glyphs.bytesize += sizeof(GlyphMetric) * GLYPHMAP_COL;
    }
    font->glyphs.metrics[bitmap_idx][row][col] = metric;
  }
  return 0;
}

// https://en.wikipedia.org/wiki/Whitespace_character
static inline int is_whitespace(unsigned int codepoint) {
  switch (codepoint) {
    case 0x20: case 0x85: case 0xA0: case 0x1680: case 0x2028: case 0x2029: case 0x202F: case 0x205F: case 0x3000: return 1;
  }
  return (codepoint >= 0x9 && codepoint <= 0xD) || (codepoint >= 0x2000 && codepoint <= 0x200A);
}

static RenFont *font_group_get_glyph(RenFont **fonts, unsigned int codepoint, int subpixel_idx, SDL_Surface **surface, GlyphMetric **metric) {
  if (subpixel_idx < 0) subpixel_idx += SUBPIXEL_BITMAPS_CACHED;
  RenFont *font = NULL;
  unsigned int glyph_id = 0;
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; i++) {
    font = fonts[i]; glyph_id = font_get_glyph_id(fonts[i], codepoint);
    // use the first font that has representation for the glyph ID, but for whitespaces always use the first font
    if (glyph_id || is_whitespace(codepoint)) break;
  }
  // if a glyph doesn't exist and is not whitespace, try using the unicode box drawing character (U+25A1)
  if (!glyph_id && !is_whitespace(codepoint) && codepoint != 0x25A1)
    return font_group_get_glyph(fonts, 0x25A1, subpixel_idx, surface, metric);
  // try to load the glyph
  subpixel_idx = FONT_IS_SUBPIXEL(font) ? subpixel_idx : 0;
  int row = glyph_id / GLYPHMAP_COL, col = glyph_id - (row * GLYPHMAP_COL);
  GlyphMetric *m = font->glyphs.metrics[subpixel_idx][row] ? &font->glyphs.metrics[subpixel_idx][row][col] : NULL;
  if (!m || (m->surface_idx == 0 && m->x0 == m->x1)) font_load_glyph(font, glyph_id);
  if (metric && m) *metric = m;
  if (surface && m && m->atlas_idx != BITMAP_NOT_AVAILABLE) *surface = font->glyphs.atlas[subpixel_idx][m->atlas_idx].surfaces[m->surface_idx];
  return font;
}

static void font_clear_glyph_cache(RenFont* font) {
  int bitmaps = FONT_BITMAP_COUNT(font);
  for (int bitmap_idx = 0; bitmap_idx < bitmaps; bitmap_idx++) {
    for (int atlas_idx = 0; atlas_idx < font->glyphs.natlas; atlas_idx++) {
      GlyphAtlas *atlas = &font->glyphs.atlas[bitmap_idx][atlas_idx];
      for (int surface_idx = 0; surface_idx < atlas->nsurface; surface_idx++) {
        SDL_FreeSurface(atlas->surfaces[surface_idx]);
      }
      free(atlas->surfaces);
    }
    free(font->glyphs.atlas[bitmap_idx]);
    font->glyphs.atlas[bitmap_idx] = NULL;
    // clear glyph metric
    for (int glyphmap_row = 0; glyphmap_row < GLYPHMAP_ROW; glyphmap_row++) {
      free(font->glyphs.metrics[bitmap_idx][glyphmap_row]);
      font->glyphs.metrics[bitmap_idx][glyphmap_row] = NULL;
    }
  }
  font->glyphs.bytesize = 0;
  font->glyphs.natlas = 0;
}

// based on https://github.com/libsdl-org/SDL_ttf/blob/2a094959055fba09f7deed6e1ffeb986188982ae/SDL_ttf.c#L1735
static unsigned long font_file_read(FT_Stream stream, unsigned long offset, unsigned char *buffer, unsigned long count) {
  uint64_t amount;
  SDL_RWops *file = (SDL_RWops *) stream->descriptor.pointer;
  SDL_RWseek(file, (int) offset, RW_SEEK_SET);
  if (count == 0)
    return 0;
  amount = SDL_RWread(file, buffer, sizeof(char), count);
  if (amount <= 0)
    return 0;
  return (unsigned long) amount;
}

static void font_file_close(FT_Stream stream) {
  if (stream && stream->descriptor.pointer)
    SDL_RWclose((SDL_RWops *) stream->descriptor.pointer);
  free(stream);
}

RenFont* ren_font_load(const char* path, float size, ERenFontAntialiasing antialiasing, ERenFontHinting hinting, unsigned char style) {
  SDL_RWops *file = NULL; RenFont *font = NULL;
  FT_Face face = NULL; FT_Stream stream = NULL;

  file = SDL_RWFromFile(path, "rb");
  if (!file) return NULL;
  
  int len = strlen(path);
  font = check_alloc(calloc(1, sizeof(RenFont) + len + 1));
  strcpy(font->path, path);
  font->size = size;
  font->antialiasing = antialiasing;
  font->hinting = hinting;
  font->style = style;
#ifdef LITE_USE_SDL_RENDERER
  font->scale = 1;
#endif

  stream = check_alloc(calloc(1, sizeof(FT_StreamRec)));
  if (!stream) goto failure;
  stream->read = &font_file_read;
  stream->close = &font_file_close;
  stream->descriptor.pointer = file;
  stream->pos = 0;
  stream->size = (unsigned long) SDL_RWsize(file);

  if (FT_Open_Face(library, &(FT_Open_Args) { .flags = FT_OPEN_STREAM, .stream = stream }, 0, &face) != 0) {
    free(stream);
    return NULL;
  }
  if (FT_Set_Pixel_Sizes(face, 0, (int) size) != 0)
    goto failure;

  font->face = face;
  font->height = (short)((face->height / (float)face->units_per_EM) * font->size);
  font->baseline = (short)((face->ascender / (float)face->units_per_EM) * font->size);

  if(FT_IS_SCALABLE(face))
    font->underline_thickness = (unsigned short)((face->underline_thickness / (float)face->units_per_EM) * font->size);
  if(!font->underline_thickness)
    font->underline_thickness = ceil((double) font->height / 14.0);

  if (FT_Load_Char(face, ' ', font_set_load_options(font)))
    goto failure;

  font->space_advance = face->glyph->advance.x / 64.0f;
  font->tab_size = 2;
  return font;

failure:
  if (face) FT_Done_Face(face);
  if (file) SDL_RWclose(file);
  if (font) free(font);
  return NULL;
}

RenFont* ren_font_copy(RenFont* font, float size, ERenFontAntialiasing antialiasing, ERenFontHinting hinting, int style) {
  antialiasing = antialiasing == -1 ? font->antialiasing : antialiasing;
  hinting = hinting == -1 ? font->hinting : hinting;
  style = style == -1 ? font->style : style;

  return ren_font_load(font->path, size, antialiasing, hinting, style);
}

const char* ren_font_get_path(RenFont *font) {
  return font->path;
}

void ren_font_free(RenFont* font) {
  font_clear_glyph_cache(font);
  // free codepoint cache as well
  for (int i = 0; i < CHARMAP_ROW; i++) {
    free(font->charmap.rows[i]);
  }
  FT_Done_Face(font->face);
  free(font);
}

void ren_font_group_set_tab_size(RenFont **fonts, int n) {
  for (int j = 0; j < FONT_FALLBACK_MAX && fonts[j]; ++j) {
    fonts[j]->tab_size = n;
  }
}

int ren_font_group_get_tab_size(RenFont **fonts) {
  return fonts[0]->tab_size;
}

float ren_font_group_get_size(RenFont **fonts) {
  return fonts[0]->size;
}

void ren_font_group_set_size(RenFont **fonts, float size, int surface_scale) {
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; ++i) {
    font_clear_glyph_cache(fonts[i]);
    FT_Set_Pixel_Sizes(fonts[i]->face, 0, (int)(size * surface_scale));
    fonts[i]->size = size;
#ifdef LITE_USE_SDL_RENDERER
    fonts[i]->scale = surface_scale;
#endif
    FT_Face face = fonts[i]->face;
    fonts[i]->height = (short)((face->height / (float)face->units_per_EM) * size);
    fonts[i]->baseline = (short)((face->ascender / (float)face->units_per_EM) * size);
    FT_Load_Char(face, ' ', font_set_load_options(fonts[i]));
    fonts[i]->space_advance = face->glyph->advance.x / 64.0f;
    fonts[i]->tab_size = 2;
  }
}

int ren_font_group_get_height(RenFont **fonts) {
  return fonts[0]->height;
}

double ren_font_group_get_width(RenFont **fonts, const char *text, size_t len, int *x_offset) {
  double width = 0;
  const char* end = text + len;

  bool set_x_offset = x_offset == NULL;
  while (text < end) {
    unsigned int codepoint;
    text = utf8_to_codepoint(text, &codepoint);
    GlyphMetric *metric = NULL;
    font_group_get_glyph(fonts, codepoint, 0, NULL, &metric);
    if (codepoint == '\t')
      width += fonts[0]->space_advance * (float) fonts[0]->tab_size;
    else if (metric && metric->xadvance)
      width += metric->xadvance;
    else
      width += fonts[0]->space_advance;
    if (!set_x_offset && metric) {
      set_x_offset = true;
      *x_offset = metric->bitmap_left; // TODO: should this be scaled by the surface scale?
    }
  }
  if (!set_x_offset)
    *x_offset = 0;
#ifdef LITE_USE_SDL_RENDERER
  return width / fonts[0]->scale;
#else
  return width;
#endif
}

#ifdef RENDERER_DEBUG
// this function can be used to debug font atlases, it is not public
void ren_font_dump(RenFont *font) {
  char filename[1024];
  int bitmaps = FONT_BITMAP_COUNT(font);
  for (int bitmap_idx = 0; bitmap_idx < bitmaps; bitmap_idx++) {
    for (int atlas_idx = 0; atlas_idx < font->glyphs.natlas; atlas_idx++) {
      GlyphAtlas *atlas = &font->glyphs.atlas[bitmap_idx][atlas_idx];
      for (int surface_idx = 0; surface_idx < atlas->nsurface; surface_idx++) {
        snprintf(filename, 1024, "%s-%d-%d-%d.bmp", font->face->family_name, bitmap_idx, atlas_idx, surface_idx);
        SDL_SaveBMP(atlas->surfaces[surface_idx], filename);
      }
    }
  }
  fprintf(stderr, "%s: %zu bytes\n", font->face->family_name, font->glyphs.bytesize);
}
#endif

double ren_draw_text(RenSurface *rs, RenFont **fonts, const char *text, size_t len, float x, int y, RenColor color) {
  SDL_Surface *surface = rs->surface;
  SDL_Rect clip;
  SDL_GetClipRect(surface, &clip);

  const int surface_scale = rs->scale;
  double pen_x = x * surface_scale;
  y *= surface_scale;
  const char* end = text + len;
  uint8_t* destination_pixels = surface->pixels;
  int clip_end_x = clip.x + clip.w, clip_end_y = clip.y + clip.h;

  RenFont* last = NULL;
  double last_pen_x = x;
  bool underline = fonts[0]->style & FONT_STYLE_UNDERLINE;
  bool strikethrough = fonts[0]->style & FONT_STYLE_STRIKETHROUGH;

  while (text < end) {
    unsigned int codepoint, r, g, b;
    text = utf8_to_codepoint(text, &codepoint);
    SDL_Surface *font_surface = NULL; GlyphMetric *metric = NULL;
    RenFont* font = font_group_get_glyph(fonts, codepoint, (int)(fmod(pen_x, 1.0) * SUBPIXEL_BITMAPS_CACHED), &font_surface, &metric);
    if (!metric)
      break;
    int start_x = floor(pen_x) + metric->bitmap_left;
    int end_x = (metric->x1 - metric->x0) + start_x;
    int glyph_end = metric->x1, glyph_start = metric->x0;
    if (metric->atlas_idx == BITMAP_NOT_AVAILABLE && !is_whitespace(codepoint))
      ren_draw_rect(rs, (RenRect){ start_x + 1, y, font->space_advance - 1, ren_font_group_get_height(fonts) }, color);
    if (!is_whitespace(codepoint) && font_surface && color.a > 0 && end_x >= clip.x && start_x < clip_end_x) {
      uint8_t* source_pixels = font_surface->pixels;
      for (int line = metric->y0; line < metric->y1; ++line) {
        int target_y = line - metric->y0 + y - metric->bitmap_top + (fonts[0]->baseline * surface_scale);
        if (target_y < clip.y)
          continue;
        if (target_y >= clip_end_y)
          break;
        if (start_x + (glyph_end - glyph_start) >= clip_end_x)
          glyph_end = glyph_start + (clip_end_x - start_x);
        if (start_x < clip.x) {
          int offset = clip.x - start_x;
          start_x += offset;
          glyph_start += offset;
        }
        uint32_t* destination_pixel = (uint32_t*)&(destination_pixels[surface->pitch * target_y + start_x * surface->format->BytesPerPixel  ]);
        uint8_t* source_pixel = &source_pixels[line * font_surface->pitch + glyph_start * font_surface->format->BytesPerPixel];
        for (int x = glyph_start; x < glyph_end; ++x) {
          uint32_t destination_color = *destination_pixel;
          // the standard way of doing this would be SDL_GetRGBA, but that introduces a performance regression. needs to be investigated
          SDL_Color dst = { (destination_color & surface->format->Rmask) >> surface->format->Rshift, (destination_color & surface->format->Gmask) >> surface->format->Gshift, (destination_color & surface->format->Bmask) >> surface->format->Bshift, (destination_color & surface->format->Amask) >> surface->format->Ashift };
          SDL_Color src;

          if (font->antialiasing == FONT_ANTIALIASING_SUBPIXEL) {
            src.r = *(source_pixel++);
            src.g = *(source_pixel++);
          }
          else  {
            src.r = *(source_pixel);
            src.g = *(source_pixel);
          }

          src.b = *(source_pixel++);
          src.a = 0xFF;

          r = (color.r * src.r * color.a + dst.r * (65025 - src.r * color.a) + 32767) / 65025;
          g = (color.g * src.g * color.a + dst.g * (65025 - src.g * color.a) + 32767) / 65025;
          b = (color.b * src.b * color.a + dst.b * (65025 - src.b * color.a) + 32767) / 65025;
          // the standard way of doing this would be SDL_GetRGBA, but that introduces a performance regression. needs to be investigated
          *destination_pixel++ = (unsigned int) dst.a << surface->format->Ashift | r << surface->format->Rshift | g << surface->format->Gshift | b << surface->format->Bshift;
        }
      }
    }

    float adv;
    if (codepoint == '\t')
      adv = font->space_advance * font->tab_size;
    else if (metric->xadvance)
      adv = metric->xadvance;
    else
      adv = font->space_advance;

    if(!last) last = font;
    else if(font != last || text == end) {
      double local_pen_x = text == end ? pen_x + adv : pen_x;
      if (underline)
        ren_draw_rect(rs, (RenRect){last_pen_x, y / surface_scale + last->height - 1, (local_pen_x - last_pen_x) / surface_scale, last->underline_thickness * surface_scale}, color);
      if (strikethrough)
        ren_draw_rect(rs, (RenRect){last_pen_x, y / surface_scale + last->height / 2, (local_pen_x - last_pen_x) / surface_scale, last->underline_thickness * surface_scale}, color);
      last = font;
      last_pen_x = pen_x;
    }

    pen_x += adv;
  }
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

void ren_draw_rect(RenSurface *rs, RenRect rect, RenColor color) {
  if (color.a == 0) { return; }

  SDL_Surface *surface = rs->surface;
  const int surface_scale = rs->scale;

  SDL_Rect dest_rect = { rect.x * surface_scale,
                         rect.y * surface_scale,
                         rect.width * surface_scale,
                         rect.height * surface_scale };

  if (color.a == 0xff) {
    uint32_t translated = SDL_MapRGB(surface->format, color.r, color.g, color.b);
    SDL_FillRect(surface, &dest_rect, translated);
  } else {
    // Seems like SDL doesn't handle clipping as we expect when using
    // scaled blitting, so we "clip" manually.
    SDL_Rect clip;
    SDL_GetClipRect(surface, &clip);
    if (!SDL_IntersectRect(&clip, &dest_rect, &dest_rect)) return;

    uint32_t *pixel = (uint32_t *)draw_rect_surface->pixels;
    *pixel = SDL_MapRGBA(draw_rect_surface->format, color.r, color.g, color.b, color.a);
    SDL_BlitScaled(draw_rect_surface, NULL, surface, &dest_rect);
  }
}

/*************** Window Management ****************/
static void ren_add_window(RenWindow *window_renderer) {
  window_count += 1;
  window_list = realloc(window_list, window_count * sizeof(RenWindow*));
  window_list[window_count-1] = window_renderer;
}

static void ren_remove_window(RenWindow *window_renderer) {
  for (size_t i = 0; i < window_count; ++i) {
    if (window_list[i] == window_renderer) {
      window_count -= 1;
      memmove(&window_list[i], &window_list[i+1], window_count - i);
      return;
    }
  }
}

int ren_init(void) {
  int err;

  draw_rect_surface = SDL_CreateRGBSurface(0, 1, 1, 32,
                       0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF);

  if ((err = FT_Init_FreeType(&library)) != 0)
    return err;

  return 0;
}

void ren_free(void) {
  SDL_FreeSurface(draw_rect_surface);
  FT_Done_FreeType(library);    
}

RenWindow* ren_create(SDL_Window *win) {
  assert(win);
  RenWindow* window_renderer = calloc(1, sizeof(RenWindow));

  window_renderer->window = win;
  renwin_init_surface(window_renderer);
  renwin_init_command_buf(window_renderer);
  renwin_clip_to_surface(window_renderer);

  ren_add_window(window_renderer);
  return window_renderer;
}

void ren_destroy(RenWindow* window_renderer) {
  assert(window_renderer);
  ren_remove_window(window_renderer);
  renwin_free(window_renderer);
  free(window_renderer->command_buf);
  window_renderer->command_buf = NULL;
  window_renderer->command_buf_size = 0;
  free(window_renderer);
}

void ren_resize_window(RenWindow *window_renderer) {
  renwin_resize_surface(window_renderer);
  renwin_update_scale(window_renderer);
}

// TODO: Does not work nicely with multiple windows
void ren_update_rects(RenWindow *window_renderer, RenRect *rects, int count) {
  static bool initial_frame = true;
  renwin_update_rects(window_renderer, rects, count);
  if (initial_frame) {
    renwin_show_window(window_renderer);
    initial_frame = false;
  }
}


void ren_set_clip_rect(RenWindow *window_renderer, RenRect rect) {
  renwin_set_clip_rect(window_renderer, rect);
}


void ren_get_size(RenWindow *window_renderer, int *x, int *y) {
  RenSurface rs = renwin_get_surface(window_renderer);
  *x = rs.surface->w;
  *y = rs.surface->h;
#ifdef LITE_USE_SDL_RENDERER
  *x /= rs.scale;
  *y /= rs.scale;
#endif
}

size_t ren_get_window_list(RenWindow ***window_list_dest) {
  *window_list_dest = window_list;
  return window_count;
}

RenWindow* ren_find_window(SDL_Window *window) {
  for (size_t i = 0; i < window_count; ++i) {
    RenWindow* window_renderer = window_list[i];
    if (window_renderer->window == window) {
      return window_renderer;
    }
  }

  return NULL;
}

RenWindow* ren_find_window_from_id(uint32_t id) {
  SDL_Window *window = SDL_GetWindowFromID(id);
  return ren_find_window(window);
}
