#include <stdio.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <assert.h>
#include <math.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_LCD_FILTER_H
#include FT_OUTLINE_H
#include FT_SYSTEM_H
#include FT_GLYPH_H

#ifdef _WIN32
#include <windows.h>
#include "utfconv.h"
#endif

#include "renderer.h"
#include "renwindow.h"

#define MAX_UNICODE 0x100000
#define GLYPHSET_SIZE 256
#define MAX_LOADABLE_GLYPHSETS (MAX_UNICODE / GLYPHSET_SIZE)
#define SUBPIXEL_BITMAPS_CACHED 3

// A pseudo-codepoint that when rendered, displays the "missing glyph" glyph.
// It is also used to indicate that such codepoint isn't found yet in a font.
#define MISSING_GLYPH_CODEPOINT UINT_MAX

// number of pixels to compensate for incorrect CBox predictions
#define CBOX_OVERFLOW_H_PIXELS 4
#define CBOX_OVERFLOW_W_PIXELS 8

// probability of CBox predictions being wrong out of all glyphs loaded in a GlyphSet
#define CBOX_OVERFLOW_H_PROB 0.2f

RenWindow* window_renderer = NULL;
static FT_Library library;

// draw_rect_surface is used as a 1x1 surface to simplify ren_draw_rect with blending
static SDL_Surface *draw_rect_surface;

static void* check_alloc(void *ptr) {
  if (!ptr) {
    fprintf(stderr, "Fatal error: memory allocation failed\n");
    exit(EXIT_FAILURE);
  }
  return ptr;
}

/************************* Fonts *************************/

/**
 * A glyph can be classififed into a few stages.
 * 0. The glyph isn't loaded
 * 1. The glyph is loaded, but it points to the missing glyph (glyph index 0)
 * 2. The glyph is loaded, but it has no bitmap representation (whitespace)
 * 3. The glyph is loaded and it has a bitmap
 *
 * For stage 0 and 1, the glyph, all fields are invalid.
 * For stage 2, xadvance is guaranteed to be valid (including 0).
 * For stage 3, x0, x1, y0, y1, bitmap_left and bitmap_top are guaranteed to be valid.
 *
 * GLYPH_NOT_LOADED corresponnds to stage 0, GLYPH_LOADED_MISSING corresponds to stage 1,
 * while GLYPH_LOADED_NORMAL corresponds to stage 2 and 3.
*/
typedef enum {
  GLYPH_NOT_LOADED,
  GLYPH_LOADED_MISSING,
  GLYPH_LOADED_NORMAL
} EGlyphLoadFlag;

typedef struct {
  EGlyphLoadFlag flags;
  unsigned int x0, x1, y0, y1;
  int bitmap_left, bitmap_top;
  float xadvance;
} GlyphMetric;

typedef struct {
  SDL_Surface* surface;
  unsigned int pen_y, max_width;
  GlyphMetric metrics[GLYPHSET_SIZE];
} GlyphSet;

typedef struct RenFont {
  FT_Face face;
  FT_StreamRec stream;
  GlyphSet* sets[SUBPIXEL_BITMAPS_CACHED][MAX_LOADABLE_GLYPHSETS];
  float size, space_advance, tab_advance;
  unsigned short baseline, height;
  ERenFontAntialiasing antialiasing;
  ERenFontHinting hinting;
  unsigned char style;
  unsigned short underline_thickness;
  /**
   * Each font will have a "missing glyph" codepoint.
   * This value is initially set to MISSING_GLYPH_CODEPOINT.
   * When a codepoint points to the missing glyph (glyph index 0) is loaded,
   * it is designated as the missing glyph codepoint.
   * Afterwards, all codepoints points to the missing glyph will be translated
   * into this codepoint and returned.
   * This means the missing glyph rendered once and stored in 1 place.
   */
  unsigned int missing_glyph_codepoint;
  char path[];
} RenFont;

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
      case FONT_HINTING_NONE:   FT_Library_SetLcdFilter(library, FT_LCD_FILTER_NONE); break;
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

static int font_set_style(FT_Outline* outline, unsigned char style) {
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

static inline float font_get_whitespace_advance(RenFont* font, unsigned int codepoint) {
  unsigned int em = font->face->size->metrics.x_ppem;
  /**
   * https://en.wikipedia.org/wiki/Whitespace_character
   * Notes:
   * 0. OGHAM SPACE MARK isn't implemented because it may contain lines
   * 1. FIGURE SPACE, PUNCTUATION SPACE and IDEOGRAPHIC SPACE (CJK) isn't implemented correctly
   *    because it requires actually loading something (this may cause infinite recursion)
   * 2. MONGOLIAN VOWEL SEPARATOR is implemented as zero-width instead of narrow space
   */
  // SPACE, LF, CR, NL, LT, FF
  if (codepoint == 0x0020 || (codepoint >= 0x000A && codepoint <= 0x000D))
    return font->space_advance;
  else if (codepoint == 0x0009) // CHARACTER TABULATION
    return font->tab_advance;
  switch (codepoint) {
    case 0x00A0: case 0x2007: case 0x2008: // NO-BREAK SPACE, FIGURE SPACE, PUNCTUATION SPACE (we don't really support these)
      return font->space_advance;
    case 0x180E: case 0x200B: case 0x200C: case 0x200D: case 0x2060: case 0xFEFF: // MONGOLIAN VOWEL SEPARATOR, ZWS, ZWNJ, ZWJ, WJ, ZWNBS (BOM)
      return 0.0f;
    case 0x2000: case 0x2002: // EN SPACE
      return em / 2.0f;
    case 0x3000:              // IDEOGRAPHIC SPACE (CJK)
    case 0x2001: case 0x2003: // EM SPACE
      return em;
    case 0x2004:              // THREE-PER-EM SPACE
      return em / 3.0f;
    case 0x2005:              // FOUR-PER-EM SPACE
      return em / 4.0f;
    case 0x2006: case 0x2009: // SIX-PER-EM SPACE, THIN SPACE
      return em / 6.0f;
    case 0x200A:              // HAIR SPACE
      return em / 8.0f;
    case 0x202F:              // NARROW NO-BREAK SPACE
      return font->space_advance / 3.0f;
    case 0x205F:              // MEDIUM MATHEMATICAL SPACE
      return 4.0f/18.0f * em;
  }
  return -1.0f; // not a whitespace
}

static void font_allocate_glyphset(RenFont *font, int idx, bool cbox) {
  int bitmaps_cached = font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? SUBPIXEL_BITMAPS_CACHED : 1;
  unsigned int load_option = font_set_load_options(font);
  unsigned int render_option = font_set_render_options(font);

  unsigned int pen_y[SUBPIXEL_BITMAPS_CACHED] = { 0 };
  unsigned int max_width[SUBPIXEL_BITMAPS_CACHED] = { 0 };
  int glyphs_predicted = 0;

  // get the dimension of the GlyphSet with cbox or by rendering the glyph
  for (int i = 0; i < GLYPHSET_SIZE; ++i) {
    FT_GlyphSlot slot;
    int predicted_width, predicted_height;

    unsigned int codepoint = i + idx * GLYPHSET_SIZE;
    unsigned int glyph_index = FT_Get_Char_Index(font->face, codepoint);

    if (!glyph_index) {
      // Most fonts only map the SPACE character to an actual glyph, while other whitespaces
      // such as EM SPACE are mapped to the missing glyph (Glyph index 0).
      // If this is the case, we will use our own whitespace logic to determine the xadvance.
      // Here, we just want to check if we're dealing with an actual missing glyph.
      if (font_get_whitespace_advance(font, codepoint) >= 0)
        continue;

      // if a missing glyph codepoint is already found somewhere, we can skip rendering it
      // in this GlyphSet.
      if (font->missing_glyph_codepoint != MISSING_GLYPH_CODEPOINT)
        continue;
    }

    if (FT_Load_Glyph(font->face, glyph_index, load_option | FT_LOAD_BITMAP_METRICS_ONLY))
      continue;

    slot = font->face->glyph;
    predicted_width = -1;
    predicted_height = -1;

    /**
     * Use FT_Outline_Get_CBox to predict the glyph dimensions. This function is very, very fast.
     * Antialiasing, hinting and subpixel positioning can make the output inaccurate,
     * so we compensate it with a few extra pixels.
     * The control box is not accurate for 1-bit monochrome bitmaps due to pixel dropout when hinting.
     * We are not going to account for width mispredictions when the glyph is translated due to subpixel positioning.
     * unless the font is "tricky" or the glyphs are tiled vertically, the prediction is accurate enough.
     */
    if (cbox && slot->format == FT_GLYPH_FORMAT_OUTLINE && font->antialiasing != FONT_ANTIALIASING_NONE) {
      FT_BBox bbox;

      font_set_style(&slot->outline, font->style);
      FT_Outline_Get_CBox(&slot->outline, &bbox);
      predicted_width = ceilf((bbox.xMax - bbox.xMin) / 64.0f);
      predicted_height = ceilf((bbox.yMax - bbox.yMin) / 64.0f);

      if (predicted_width == 0 || predicted_height == 0)
        continue;

      predicted_width += CBOX_OVERFLOW_W_PIXELS;
      glyphs_predicted++;
    }

    // increment the dimensions for all subpixel bitmaps
    for (int j = 0; j < bitmaps_cached; ++j) {
      // Subpixel positioning is going to increase the bitmap size by a few pixels.
      // Combined with hinting, this amounts to 4-6 pixels at most, which is covered by CBOX_OVERFLOW_W_PIXELS.
      int width = predicted_width;
      int height = predicted_height;

      if (predicted_height == -1 || predicted_width == -1) {
        // Render the glyph to get an accurate dimension
        // As far as I know, there's no way to translate the outline incrementally and render it.
        // This means we need to call FT_Load_Glyph every time to "clear" the glyph slot.
        if (FT_Load_Glyph(font->face, glyph_index, load_option))
          continue;

        slot = font->face->glyph;
        if (slot->format == FT_GLYPH_FORMAT_OUTLINE) {
          if (slot->outline.n_points == 0) continue;
          // perform transformation and subpixel positioning
          font_set_style(&slot->outline, font->style);
          if (j > 0)
            FT_Outline_Translate(&slot->outline, j * (64 / SUBPIXEL_BITMAPS_CACHED), 0);
        }

        if (FT_Render_Glyph(slot, render_option))
          continue;

        width = slot->bitmap.width;
        height = slot->bitmap.rows;
        if (slot->bitmap.pixel_mode == FT_PIXEL_MODE_LCD)
          width /= 3;
      }

      pen_y[j] += height;
      max_width[j] = width > max_width[j] ? width : max_width[j];
    }

    // designate this codepoint as the missing glyph codepoint
    if (!glyph_index)
      font->missing_glyph_codepoint = codepoint;

  } // for (int i = 0; i < GLYPHSET_SIZE; ++i)

  for (int j = 0; j < bitmaps_cached; ++j) {
    GlyphSet *set = font->sets[j][idx];

    if (!set)
      font->sets[j][idx] = set = check_alloc(calloc(1, sizeof(GlyphSet)));

    // don't allocate empty surfaces
    if (pen_y[j] == 0 || max_width[j] == 0)
      continue;

    // Hinting and AA alone doesn't add a lot of extra height to a bitmap,
    // so we can try to be smart and only add Y overflow to a select few glyphs.
    // Here, we assume that 20% of all predictions are wrong, and this is adequate for most cases.
    pen_y[j] += glyphs_predicted * CBOX_OVERFLOW_H_PROB * CBOX_OVERFLOW_H_PIXELS;

    if (!set->surface || max_width[j] > set->surface->w || pen_y[j] > set->surface->h) {
      SDL_Surface *new_surface = check_alloc(SDL_CreateRGBSurface(0, max_width[j], pen_y[j], bitmaps_cached * 8, 0, 0, 0, 0));

      if (set->surface) {
        // copy the old surface data onto the new one
        for (unsigned int line = 0; line < set->surface->h; ++line) {
          uint8_t *src_row = ((uint8_t *) set->surface->pixels) + line * set->surface->pitch;
          uint8_t *dst_row = ((uint8_t *) new_surface->pixels) + line * new_surface->pitch;
          memcpy(dst_row, src_row, set->surface->w * set->surface->format->BytesPerPixel);
        }
        SDL_FreeSurface(set->surface);
      }

      set->surface = new_surface;
    }
  }
}

static void font_render_glyph(RenFont* font, unsigned int codepoint) {
  unsigned int bitmaps_cached = font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? SUBPIXEL_BITMAPS_CACHED : 1;
  unsigned int metrics_idx = codepoint % GLYPHSET_SIZE;
  unsigned int glyphset_idx = (codepoint / GLYPHSET_SIZE) % MAX_LOADABLE_GLYPHSETS;

  unsigned int load_flags = font_set_load_options(font);
  unsigned int render_flags = font_set_render_options(font);
  unsigned int glyph_index = FT_Get_Char_Index(font->face, codepoint);

  if (!glyph_index) {
    // We assume that the codepoint points to glyph index 0 because it is whitespace.
    // If it isn't, we'll see if the codepoint is the designated missing glyph codepoint.
    // If yes, we'll render the glyph. Otherwise, we'll skip.
    int flags = GLYPH_LOADED_NORMAL;
    float whitespace_advance = font_get_whitespace_advance(font, codepoint);

    if (whitespace_advance < 0) {
      // not whitespace
      flags = GLYPH_LOADED_MISSING;
      whitespace_advance = 0;
    }

    for (int j = 0; j < bitmaps_cached; ++j) {
      font->sets[j][glyphset_idx]->metrics[metrics_idx].flags = flags;
      font->sets[j][glyphset_idx]->metrics[metrics_idx].xadvance = whitespace_advance;
    }

    if (flags == GLYPH_LOADED_NORMAL || font->missing_glyph_codepoint != codepoint)
      return;
  }

  /**
   * There's an issue with monospaced fonts where the hinted xadvance is off (rounded)
   * when calculated with lsb_delta and rsb_delta;
   * we need to load the font without hinting and use that.
   * See #843.
   */
  if (FT_Load_Glyph(font->face, glyph_index, (load_flags | FT_LOAD_BITMAP_METRICS_ONLY | FT_LOAD_NO_HINTING) & ~FT_LOAD_FORCE_AUTOHINT))
    return;

  // subpixel positioning & transformations don't affect xadvance, so we don't run them
  for (int j = 0; j < bitmaps_cached; ++j) {
    // since we already have the xadvance, we can consider this codepoint loaded
    font->sets[j][glyphset_idx]->metrics[metrics_idx].flags = GLYPH_LOADED_NORMAL;
    font->sets[j][glyphset_idx]->metrics[metrics_idx].xadvance = font->face->glyph->advance.x / 64.0f;
  }

  for (int j = 0; j < bitmaps_cached; ++j) {

    int width, height;
    FT_GlyphSlot slot;
    uint8_t *src_pixels, *dst_pixels;
    GlyphSet *set = font->sets[j][glyphset_idx];
    GlyphMetric *metric = &set->metrics[metrics_idx];

    // we must reload the glyph instead of incrementally translating it because FT_Render_Glyph
    // will not re-render the glyph unless the slot is "cleared".
    if (FT_Load_Glyph(font->face, glyph_index, load_flags))
      return;

    slot = font->face->glyph;
    if (slot->format == FT_GLYPH_FORMAT_OUTLINE) {
      if (slot->outline.n_points == 0) continue;
      // perform style and subpixel positioning
      font_set_style(&slot->outline, font->style);
      if (j > 0)
        FT_Outline_Translate(&slot->outline, j * (64 / SUBPIXEL_BITMAPS_CACHED), 0);
    }

    if (FT_Render_Glyph(slot, render_flags))
      return;

    width = slot->bitmap.width;
    height = slot->bitmap.rows;
    if (slot->bitmap.pixel_mode == FT_PIXEL_MODE_LCD)
      width /= 3;

    if (width == 0 || height == 0)
      return;

    // save bitmap metrics
    metric->x0 = 0;
    metric->x1 = width;
    metric->y0 = set->pen_y;
    metric->y1 = metric->y0 + height;
    metric->bitmap_left = slot->bitmap_left;
    metric->bitmap_top = slot->bitmap_top;

    if (!set->surface || metric->x1 > set->surface->w || metric->y1 > set->surface->h) {
      // resize the glyphset with exact pixel sizing
      font_allocate_glyphset(font, glyphset_idx, false);
      assert(metric->x1 <= set->surface->w && metric->y1 <= set->surface->h);
    }

    // blit the bitmap onto the surface
    src_pixels = (uint8_t *) slot->bitmap.buffer;
    dst_pixels = (uint8_t *) set->surface->pixels;
    for (unsigned int line = 0; line < height; ++line) {
      unsigned int src_offset =  line * slot->bitmap.pitch;
      unsigned int dst_offset = (metric->y0 + line) * set->surface->pitch + metric->x0 * set->surface->format->BytesPerPixel;
      if (slot->bitmap.pixel_mode == FT_PIXEL_MODE_MONO) {
        for (unsigned int column = 0; column < slot->bitmap.width; ++column) {
          int current_source_offset = src_offset + (column / 8);
          int source_pixel = src_pixels[current_source_offset];
          dst_pixels[dst_offset++] = ((source_pixel >> (7 - (column % 8))) & 0x1) << 7;
        }
      } else {
        memcpy(&dst_pixels[dst_offset], &src_pixels[src_offset], slot->bitmap.width);
      }
    }
    set->pen_y += height;

  } // for (int j = 0; j < bitmaps_cached; ++j)
}

static EGlyphLoadFlag font_get_glyph(RenFont* font,
                                      unsigned int codepoint,
                                      int subpixel_idx,
                                      GlyphMetric **metric,
                                      SDL_Surface **surface) {
  int glyphset_idx = (codepoint / GLYPHSET_SIZE) % MAX_LOADABLE_GLYPHSETS;
  int metrics_idx = codepoint % GLYPHSET_SIZE;
  GlyphSet *set;

  subpixel_idx = font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? subpixel_idx : 0;
  subpixel_idx = subpixel_idx < 0 ? subpixel_idx + SUBPIXEL_BITMAPS_CACHED : subpixel_idx;

  if (!font->sets[subpixel_idx][glyphset_idx])
    font_allocate_glyphset(font, glyphset_idx, true);

  set = font->sets[subpixel_idx][glyphset_idx];
  if (!set->metrics[metrics_idx].flags)
    font_render_glyph(font, codepoint);

  if (metric) *metric = &set->metrics[metrics_idx];
  if (surface) *surface = set->surface;
  return set->metrics[metrics_idx].flags;
}

static RenFont *font_group_get_glyph(RenFont** fonts,
                                      unsigned int codepoint,
                                      int subpixel_idx,
                                      GlyphMetric **metric,
                                      SDL_Surface **glyph_surface,
                                      bool *glyph_missing) {
  int last_font = 0;

  // try to load the glyph from each font
  if (glyph_missing) *glyph_missing = false;
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; ++i) {
    if (font_get_glyph(fonts[i], codepoint, subpixel_idx, metric, glyph_surface) == GLYPH_LOADED_NORMAL)
      return fonts[i];
    last_font = i;
  }

  // cannot load glyph, try to load the missing glyph codepoint
  if (glyph_missing) *glyph_missing = true;
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; ++i) {
    if (fonts[i]->missing_glyph_codepoint == MISSING_GLYPH_CODEPOINT) continue;
    if (font_get_glyph(fonts[i], fonts[i]->missing_glyph_codepoint, subpixel_idx, metric, glyph_surface) == GLYPH_LOADED_NORMAL)
      return fonts[i];
    last_font = i;
  }

  // cannot load anything, just return the last enumerated font
  return fonts[last_font];
}

static void font_clear_glyph_cache(RenFont* font) {
  for (int i = 0; i < SUBPIXEL_BITMAPS_CACHED; ++i) {
    for (int j = 0; j < MAX_LOADABLE_GLYPHSETS; ++j) {
      if (font->sets[i][j]) {
        if (font->sets[i][j]->surface)
          SDL_FreeSurface(font->sets[i][j]->surface);
        free(font->sets[i][j]);
        font->sets[i][j] = NULL;
      }
    }
  }
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
  if (stream && stream->descriptor.pointer) {
    SDL_RWclose((SDL_RWops *) stream->descriptor.pointer);
    stream->descriptor.pointer = NULL;
  }
}

RenFont* ren_font_load(RenWindow *window_renderer, const char* path, float size, ERenFontAntialiasing antialiasing, ERenFontHinting hinting, unsigned char style) {
  RenFont *font = NULL;
  FT_Face face = NULL;

  SDL_RWops *file = SDL_RWFromFile(path, "rb");
  if (!file)
    goto rwops_failure;

  int len = strlen(path);
  font = check_alloc(calloc(1, sizeof(RenFont) + len + 1));
  font->stream.read = font_file_read;
  font->stream.close = font_file_close;
  font->stream.descriptor.pointer = file;
  font->stream.pos = 0;
  font->stream.size = (unsigned long) SDL_RWsize(file);

  if (FT_Open_Face(library, &(FT_Open_Args){ .flags = FT_OPEN_STREAM, .stream = &font->stream }, 0, &face))
    goto failure;

  const int surface_scale = renwin_get_surface(window_renderer).scale;
  if (FT_Set_Pixel_Sizes(face, 0, (int)(size*surface_scale)))
    goto failure;

  strcpy(font->path, path);
  font->face = face;
  font->size = size;
  font->height = (short)((face->height / (float)face->units_per_EM) * font->size);
  font->baseline = (short)((face->ascender / (float)face->units_per_EM) * font->size);
  font->antialiasing = antialiasing;
  font->hinting = hinting;
  font->style = style;
  font->missing_glyph_codepoint = MISSING_GLYPH_CODEPOINT;

  if(FT_IS_SCALABLE(face))
    font->underline_thickness = (unsigned short)((face->underline_thickness / (float)face->units_per_EM) * font->size);
  if(!font->underline_thickness)
    font->underline_thickness = ceil((double) font->height / 14.0);

  if (FT_Load_Char(face, ' ', font_set_load_options(font)))
    goto failure;

  font->space_advance = face->glyph->advance.x / 64.0f;
  font->tab_advance = font->space_advance * 2;
  return font;

failure:
  if (face)
    FT_Done_Face(face);
  if (font)
    free(font);
  return NULL;

rwops_failure:
  if (file)
    SDL_RWclose(file);
  return NULL;
}

RenFont* ren_font_copy(RenWindow *window_renderer, RenFont* font, float size, ERenFontAntialiasing antialiasing, ERenFontHinting hinting, int style) {
  antialiasing = antialiasing == -1 ? font->antialiasing : antialiasing;
  hinting = hinting == -1 ? font->hinting : hinting;
  style = style == -1 ? font->style : style;

  return ren_font_load(window_renderer, font->path, size, antialiasing, hinting, style);
}

const char* ren_font_get_path(RenFont *font) {
  return font->path;
}

void ren_font_free(RenFont* font) {
  font_clear_glyph_cache(font);
  FT_Done_Face(font->face);
  free(font);
}

void ren_font_group_set_tab_size(RenFont **fonts, int n) {
  for (int j = 0; j < FONT_FALLBACK_MAX && fonts[j]; ++j) {
    int bitmaps_cached = fonts[j]->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? SUBPIXEL_BITMAPS_CACHED : 1;
    fonts[j]->tab_advance = fonts[j]->space_advance * n;

    for (int i = 0; i < bitmaps_cached; ++i) {
      GlyphMetric *metric = NULL;
      font_get_glyph(fonts[j], '\t', i, &metric, NULL);
      if (metric)
        metric->xadvance = fonts[j]->space_advance * n;
    }
  }
}

int ren_font_group_get_tab_size(RenFont **fonts) {
  GlyphMetric *metric = NULL;
  font_get_glyph(fonts[0], '\t', 0, &metric, NULL);
  return metric && fonts[0]->space_advance ? (metric->xadvance / fonts[0]->space_advance) : fonts[0]->space_advance;
}

float ren_font_group_get_size(RenFont **fonts) {
  return fonts[0]->size;
}

void ren_font_group_set_size(RenWindow *window_renderer, RenFont **fonts, float size) {
  const int surface_scale = renwin_get_surface(window_renderer).scale;
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; ++i) {
    font_clear_glyph_cache(fonts[i]);
    FT_Face face = fonts[i]->face;
    FT_Set_Pixel_Sizes(face, 0, (int)(size*surface_scale));
    fonts[i]->size = size;
    fonts[i]->height = (short)((face->height / (float)face->units_per_EM) * size);
    fonts[i]->baseline = (short)((face->ascender / (float)face->units_per_EM) * size);
    FT_Load_Char(face, ' ', font_set_load_options(fonts[i]));
    fonts[i]->space_advance = face->glyph->advance.x / 64.0f;
    fonts[i]->tab_advance = fonts[i]->space_advance * 2;
  }
}

int ren_font_group_get_height(RenFont **fonts) {
  return fonts[0]->height;
}

double ren_font_group_get_width(RenWindow *window_renderer, RenFont **fonts, const char *text, size_t len, int *x_offset) {
  double width = 0;
  const char* end = text + len;
  bool set_x_offset = x_offset == NULL;
  while (text < end) {
    unsigned int codepoint;
    RenFont *font = NULL;
    GlyphMetric* metric = NULL;
    text = utf8_to_codepoint(text, &codepoint);
    font = font_group_get_glyph(fonts, codepoint, 0, &metric, NULL, NULL);
    width += (!font || metric->xadvance) ? metric->xadvance : fonts[0]->space_advance;
    if (!set_x_offset) {
      set_x_offset = true;
      *x_offset = metric->bitmap_left; // TODO: should this be scaled by the surface scale?
    }
  }
  const int surface_scale = renwin_get_surface(window_renderer).scale;
  if (!set_x_offset) {
    *x_offset = 0;
  }
  return width / surface_scale;
}

// 4-times unrolled loop
// https://github.com/libsdl-org/SDL_ttf/blob/2d50c3e9658ceba8272b13a8cc64ab072f19d4e3/SDL_ttf.c#L364
#define DUFFS_LOOP4(pixel_copy_increment, width)                        \
{ int n = (width+3)/4;                                                  \
    switch (width & 3) {                                                \
    case 0: do {    pixel_copy_increment;   /* fallthrough */           \
    case 3:     pixel_copy_increment;       /* fallthrough */           \
    case 2:     pixel_copy_increment;       /* fallthrough */           \
    case 1:     pixel_copy_increment;       /* fallthrough */           \
        } while (--n > 0);                                              \
    }                                                                   \
}

// dual source blending for LCD (subpixel rendering)
static inline void lcd_blend(SDL_Surface *dst, SDL_Surface *src, RenRect *src_rect, RenRect *dst_rect, RenColor *color) {
  unsigned char src_r, src_g, src_b, dst_r, dst_g, dst_b, dst_a, r, g, b;
  uint8_t *src_row = (uint8_t *) src->pixels + src_rect->y * src->pitch + src_rect->x * src->format->BytesPerPixel;
  uint32_t *dst_row = (uint32_t *) ((uint8_t *) dst->pixels + dst_rect->y * dst->pitch + dst_rect->x * dst->format->BytesPerPixel);
  int src_skip = src->pitch - (src_rect->width * src->format->BytesPerPixel);
  int dst_skip = dst->pitch - (src_rect->width * dst->format->BytesPerPixel);

  for (int y = 0; y < src_rect->height; ++y) {
    DUFFS_LOOP4(
      // the correct way to do this is with SDL_GetRGBA() but it introduces performance regression
      dst_r = (*dst_row & dst->format->Rmask) >> dst->format->Rshift;
      dst_g = (*dst_row & dst->format->Gmask) >> dst->format->Gshift;
      dst_b = (*dst_row & dst->format->Bmask) >> dst->format->Bshift;
      dst_a = (*dst_row & dst->format->Amask) >> dst->format->Ashift;
      src_r = *(src_row++);
      src_g = *(src_row++);
      src_b = *(src_row++);

      // magic equations that does dual source blending
      r = (color->r * src_r * color->a + dst_r * (65025 - src_r * color->a) + 32767) / 65025;
      g = (color->g * src_g * color->a + dst_g * (65025 - src_g * color->a) + 32767) / 65025;
      b = (color->b * src_b * color->a + dst_b * (65025 - src_b * color->a) + 32767) / 65025;

      // the correct way to do this is with SDL_MapRGBA() but it introduces performance regression
      *(dst_row++) = (r << dst->format->Rshift) | (g << dst->format->Gshift) | (b << dst->format->Bshift) | (dst_a << dst->format->Ashift);
    , src_rect->width);

    src_row += src_skip;
    dst_row = (uint32_t *) ((uint8_t *) dst_row + dst_skip);
  }
}

// dual source blending for grayscale
static inline void grayscale_blend(SDL_Surface *dst, SDL_Surface *src, RenRect *src_rect, RenRect *dst_rect, RenColor *color) {
  unsigned char src_r, src_g, src_b, dst_r, dst_g, dst_b, dst_a, r, g, b;
  uint8_t *src_row = (uint8_t *) src->pixels + src_rect->y * src->pitch + src_rect->x * src->format->BytesPerPixel;
  uint32_t *dst_row = (uint32_t *) ((uint8_t *) dst->pixels + dst_rect->y * dst->pitch + dst_rect->x * dst->format->BytesPerPixel);
  int src_skip = src->pitch - (src_rect->width * src->format->BytesPerPixel);
  int dst_skip = dst->pitch - (src_rect->width * dst->format->BytesPerPixel);

  for (int y = 0; y < src_rect->height; ++y) {

    DUFFS_LOOP4(
      // the correct way to do this is with SDL_GetRGBA() but it introduces performance regression
      dst_r = (*dst_row & dst->format->Rmask) >> dst->format->Rshift;
      dst_g = (*dst_row & dst->format->Gmask) >> dst->format->Gshift;
      dst_b = (*dst_row & dst->format->Bmask) >> dst->format->Bshift;
      dst_a = (*dst_row & dst->format->Amask) >> dst->format->Ashift;
      src_r = *(src_row);
      src_g = *(src_row);
      src_b = *(src_row++);

      // magic equations that does dual source blending
      r = (color->r * src_r * color->a + dst_r * (65025 - src_r * color->a) + 32767) / 65025;
      g = (color->g * src_g * color->a + dst_g * (65025 - src_g * color->a) + 32767) / 65025;
      b = (color->b * src_b * color->a + dst_b * (65025 - src_b * color->a) + 32767) / 65025;

      // the correct way to do this is with SDL_MapRGBA() but it introduces performance regression
      *(dst_row++) = (r << dst->format->Rshift) | (g << dst->format->Gshift) | (b << dst->format->Bshift) | (dst_a << dst->format->Ashift);
    , src_rect->width)

    src_row += src_skip;
    dst_row = (uint32_t *) ((uint8_t *) dst_row + dst_skip);
  }
}

double ren_draw_text(RenSurface *rs, RenFont **fonts, const char *text, size_t len, float x, int y, RenColor color) {
  SDL_Rect clip;
  SDL_Surface *dst_surface = rs->surface;
  SDL_GetClipRect(dst_surface, &clip);

  const int surface_scale = rs->scale;
  double pen_x = x * surface_scale;
  y *= surface_scale;
  const char* end = text + len;
  int clip_end_x = clip.x + clip.w;
  int clip_end_y = clip.y + clip.h;

  double last_pen_x = x;
  RenFont* last_font = NULL;

  while (text < end) {
    unsigned int codepoint;
    RenFont *font = NULL;
    GlyphMetric* metric = NULL;
    SDL_Surface* src_surface = NULL;
    bool glyph_missing = false;
    RenRect src_rect = { 0 }, dst_rect = { 0 };
    float adv;

    text = utf8_to_codepoint(text, &codepoint);
    font = font_group_get_glyph(fonts, codepoint, (int)(fmod(pen_x, 1.0) * SUBPIXEL_BITMAPS_CACHED), &metric, &src_surface, &glyph_missing);
    adv = font->space_advance;

    if (metric && metric->flags == GLYPH_LOADED_NORMAL) {
      adv = metric->xadvance;
      src_rect = (RenRect) {
        .x =     metric->x0,              .y =      metric->y0,
        .width = metric->x1 - metric->x0, .height = metric->y1 - metric->y0
      };
      dst_rect = (RenRect) {
        .x     = floor(pen_x) + metric->bitmap_left, .y      = y - metric->bitmap_top + font->baseline * surface_scale,
        .width = 0,                                  .height = 0
      };

      // perform clipping and clamping
      if (dst_rect.x >= clip_end_x)
        break;

      if (dst_rect.x + src_rect.width >= clip_end_x)
        src_rect.width = clip_end_x - dst_rect.x;
      if (dst_rect.y + src_rect.height >= clip_end_y)
        src_rect.height = clip_end_y - dst_rect.y;

      if (dst_rect.x < clip.x) {
        int offset = clip.x - dst_rect.x;
        src_rect.x += offset;
        src_rect.width -= offset;
        dst_rect.x += offset;
      }
      if (dst_rect.y < clip.y) {
        int offset = clip.y - dst_rect.y;
        src_rect.y += offset;
        src_rect.height -= offset;
        dst_rect.y += offset;
      }
    }

    if (glyph_missing && (src_rect.width == 0 || src_rect.height == 0)) {
      // if the original glyph for the codepoint cannot be found, and we don't have a bitmap for the missing
      // glyph, we'll draw a rectangle.
      dst_rect = (RenRect) {
        .x     = floor(pen_x) + 1, .y      = y + 1,
        .width = adv - 2,          .height = font->height - 2
      };
      ren_draw_rect(rs, dst_rect, color);
    } else if (color.a > 0 && src_rect.width > 0 && src_rect.height > 0) {
      // if we're drawing something opaque, and the glyph is loaded, and the glyph has a bitmap, then we blit it
      if (font->antialiasing == FONT_ANTIALIASING_SUBPIXEL)
        lcd_blend(dst_surface, src_surface, &src_rect, &dst_rect, &color);
      else
        grayscale_blend(dst_surface, src_surface, &src_rect, &dst_rect, &color);
    }

    if(!last_font) {
      last_font = font;
    } else if(font != last_font || text == end) {
      bool underline = last_font->style & FONT_STYLE_UNDERLINE;
      bool strikethrough = last_font->style & FONT_STYLE_STRIKETHROUGH;
      double local_pen_x = text == end ? pen_x + adv : pen_x;

      if (underline)
        ren_draw_rect(rs, (RenRect){last_pen_x, y / surface_scale + last_font->height - 1, (local_pen_x - last_pen_x) / surface_scale, last_font->underline_thickness * surface_scale}, color);
      if (strikethrough)
        ren_draw_rect(rs, (RenRect){last_pen_x, y / surface_scale + last_font->height / 2, (local_pen_x - last_pen_x) / surface_scale, last_font->underline_thickness * surface_scale}, color);

      last_font = font;
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
RenWindow* ren_init(SDL_Window *win) {
  assert(win);
  int error = FT_Init_FreeType( &library );
  if ( error ) {
    fprintf(stderr, "internal font error when starting the application\n");
    return NULL;
  }
  RenWindow* window_renderer = calloc(1, sizeof(RenWindow));

  window_renderer->window = win;
  renwin_init_surface(window_renderer);
  renwin_init_command_buf(window_renderer);
  renwin_clip_to_surface(window_renderer);
  draw_rect_surface = SDL_CreateRGBSurface(0, 1, 1, 32,
                       0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF);

  return window_renderer;
}

void ren_free(RenWindow* window_renderer) {
  assert(window_renderer);
  renwin_free(window_renderer);
  SDL_FreeSurface(draw_rect_surface);
  free(window_renderer->command_buf);
  window_renderer->command_buf = NULL;
  window_renderer->command_buf_size = 0;
  free(window_renderer);
}

void ren_resize_window(RenWindow *window_renderer) {
  renwin_resize_surface(window_renderer);
  renwin_update_scale(window_renderer);
}


void ren_update_rects(RenWindow *window_renderer, RenRect *rects, int count) {
  static bool initial_frame = true;
  if (initial_frame) {
    renwin_show_window(window_renderer);
    initial_frame = false;
  }
  renwin_update_rects(window_renderer, rects, count);
}


void ren_set_clip_rect(RenWindow *window_renderer, RenRect rect) {
  renwin_set_clip_rect(window_renderer, rect);
}


void ren_get_size(RenWindow *window_renderer, int *x, int *y) {
  RenSurface rs = renwin_get_surface(window_renderer);
  *x = rs.surface->w / rs.scale;
  *y = rs.surface->h / rs.scale;
}
