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

#define MAX_UNICODE 0x100000
#define GLYPHSET_SIZE 256
#define MAX_LOADABLE_GLYPHSETS (MAX_UNICODE / GLYPHSET_SIZE)
#define SUBPIXEL_BITMAPS_CACHED 3

#ifndef max
#define max(a, b) ((a) > (b) ? (a) : (b))
#endif

#ifndef min
#define min(a, b) ((a) > (b) ? (b) : (a))
#endif

#ifndef array_sizeof
#define array_sizeof(a) (sizeof((a)) / sizeof(*(a)))
#endif

RenWindow window_renderer = {0};
static FT_Library library;

// draw_rect_surface is used as a 1x1 surface to simplify ren_draw_rect with blending
static SDL_Surface *draw_rect_surface;

// color palette for rendering grayscale images
static SDL_Color grayscale_palette[256];

// color palette for rendering monochrome (1-bit) images
static SDL_Color monochrome_palette[] = { { 0, 0, 0, 0 }, { 0xFF, 0xFF, 0xFF, 0xFF } };

static void* __check_alloc(void *ptr, const char *src) {
  if (!ptr) {
    fprintf(stderr, "Fatal error (%s): memory allocation failed\n", src);
    exit(EXIT_FAILURE);
  }
  return ptr;
}

#define stringize(x) stringize2(x)
#define stringize2(x) #x
#define check_alloc(ptr) __check_alloc(ptr, __FILE__ ":" stringize(__LINE__))

/************************* Fonts *************************/

typedef struct {
  unsigned int x0, x1, y0, y1, loaded;
  int bitmap_left, bitmap_top;
  float xadvance;
} GlyphMetric;

typedef struct {
  SDL_Surface* surface;
  GlyphMetric metrics[GLYPHSET_SIZE];
} GlyphSet;

typedef struct RenFont {
  FT_Face face;
  FT_StreamRec stream;
  GlyphSet* sets[SUBPIXEL_BITMAPS_CACHED][MAX_LOADABLE_GLYPHSETS];
  float size, space_advance, tab_advance, bitmap_scale;
  unsigned short max_height, baseline, height;
  ERenFontAntialiasing antialiasing;
  ERenFontHinting hinting;
  unsigned char style;
  unsigned short underline_thickness;
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

static int font_get_load_options(RenFont* font) {
  int load_target, hinting;

  if (font->antialiasing == FONT_ANTIALIASING_NONE)
    load_target = FT_LOAD_TARGET_MONO;
  else if (font->hinting == FONT_HINTING_SLIGHT)
    load_target = FT_LOAD_TARGET_LIGHT;
  else
    load_target = FT_LOAD_TARGET_NORMAL;

  hinting = font->hinting == FONT_HINTING_NONE ? FT_LOAD_NO_HINTING : FT_LOAD_FORCE_AUTOHINT;

  return load_target | hinting | FT_LOAD_COLOR;
}

static int font_set_render_options(RenFont* font) {
  if (font->antialiasing == FONT_ANTIALIASING_NONE)
    return FT_RENDER_MODE_MONO;

  if (font->antialiasing == FONT_ANTIALIASING_SUBPIXEL) {
    unsigned char weights[] = { 0x10, 0x40, 0x70, 0x40, 0x10 };

    if (font->hinting == FONT_HINTING_NONE)
      FT_Library_SetLcdFilter(library, FT_LCD_FILTER_NONE);
    else
      FT_Library_SetLcdFilterWeights(library, weights);

    return FT_RENDER_MODE_LCD;
  } else {
    switch (font->hinting) {
      case FONT_HINTING_NONE:   return FT_RENDER_MODE_NORMAL;
      case FONT_HINTING_SLIGHT: return FT_RENDER_MODE_LIGHT;
      case FONT_HINTING_FULL:   return FT_RENDER_MODE_LIGHT;
    }
  }

  return 0;
}

static int font_set_style(FT_Outline* outline, int x_translation, unsigned char style) {
  FT_Outline_Translate(outline, x_translation, 0);

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

static void font_load_glyphset(RenFont* font, int idx) {
  unsigned int render_option = font_set_render_options(font);
  unsigned int load_option = font_get_load_options(font);
  int bitmaps_cached = font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? SUBPIXEL_BITMAPS_CACHED : 1;

  // we will derive this later when rendering
  unsigned int bits_per_pixel = 1;

  for (int j = 0, pen_x = 0; j < bitmaps_cached; ++j) {
    GlyphSet* set = check_alloc(calloc(1, sizeof(GlyphSet)));
    font->sets[j][idx] = set;

    for (int i = 0; i < GLYPHSET_SIZE; ++i) {
      int glyph_index = FT_Get_Char_Index(font->face, i + idx * GLYPHSET_SIZE);
      FT_GlyphSlot slot = font->face->glyph;

      if (!glyph_index) continue;
      if (FT_Load_Glyph(font->face, glyph_index, load_option | FT_LOAD_BITMAP_METRICS_ONLY)) continue;
      // only apply transformation to outline fonts
      if (slot->format == FT_GLYPH_FORMAT_OUTLINE
            && font_set_style(&slot->outline, j * (64 / SUBPIXEL_BITMAPS_CACHED), font->style)) continue;
      if (FT_Render_Glyph(slot, render_option)) continue;

      int glyph_width = slot->bitmap.width;

      switch (slot->bitmap.pixel_mode) {
        // we are not going to deal with 1-bit packed surfaces when rendering
        case FT_PIXEL_MODE_MONO: bits_per_pixel = max(bits_per_pixel, 8); break;
        case FT_PIXEL_MODE_GRAY: bits_per_pixel = max(bits_per_pixel, 8); break;
        // the LCD bitmap is 3 times larger due to subpixels
        case FT_PIXEL_MODE_LCD:  bits_per_pixel = max(bits_per_pixel, 24); glyph_width /= 3; break;
        case FT_PIXEL_MODE_BGRA: bits_per_pixel = max(bits_per_pixel, 32); break;
      }

      // scale glyph width accordingly
      glyph_width /= font->bitmap_scale;

      set->metrics[i] = (GlyphMetric) {
        .loaded = true,
        .x0 = pen_x,   .x1 = pen_x + glyph_width,
        .y0 = 0,       .y1 = slot->bitmap.rows / font->bitmap_scale,
        .bitmap_left = slot->bitmap_left / font->bitmap_scale,
        .bitmap_top =  slot->bitmap_top / font->bitmap_scale,
        .xadvance =    ((slot->advance.x + slot->lsb_delta - slot->rsb_delta) / 64.0f) / font->bitmap_scale
      };

      pen_x += glyph_width;
      font->max_height = max(font->max_height, slot->bitmap.rows / font->bitmap_scale);

      // In order to fix issues with monospacing; we need the unhinted xadvance; as FreeType doesn't correctly report the hinted advance for spaces on monospace fonts (like RobotoMono). See #843.
      if (FT_Load_Glyph(font->face, glyph_index, (load_option | FT_LOAD_BITMAP_METRICS_ONLY | FT_LOAD_NO_HINTING) & ~FT_LOAD_FORCE_AUTOHINT)) continue;
      if (slot->format == FT_GLYPH_FORMAT_OUTLINE
            && font_set_style(&slot->outline, j * (64 / SUBPIXEL_BITMAPS_CACHED), font->style)) continue;
      if (FT_Render_Glyph(slot, render_option)) continue;

      set->metrics[i].xadvance = (slot->advance.x / 64.0f) / font->bitmap_scale;
    }

    if (pen_x == 0)
      continue;

    // scale blit on a 8bpp bitmap is impossible in SDL2. This probably because of SIMD.
    if (font->bitmap_scale != 1.0f)
      bits_per_pixel = max(bits_per_pixel, 24);

    set->surface = check_alloc(SDL_CreateRGBSurface(0,
                                                    pen_x / font->bitmap_scale, font->max_height / font->bitmap_scale,
                                                    bits_per_pixel,
                                                    0, 0, 0, 0));

    // required for grayscale blitting
    if (bits_per_pixel == 8)
      SDL_SetPaletteColors(set->surface->format->palette, grayscale_palette, 0, array_sizeof(grayscale_palette));

    uint8_t *pixels = set->surface->pixels;

    for (int i = 0; i < GLYPHSET_SIZE; ++i) {
      int glyph_index = FT_Get_Char_Index(font->face, i + idx * GLYPHSET_SIZE);
      if (!glyph_index) continue;
      if (FT_Load_Glyph(font->face, glyph_index, load_option)) continue;

      FT_GlyphSlot slot = font->face->glyph;
      if (slot->format == FT_GLYPH_FORMAT_OUTLINE
            && font_set_style(&slot->outline, (64 / bitmaps_cached) * j, font->style)) continue;
      if (FT_Render_Glyph(slot, render_option)) continue;

      if (!slot->bitmap.width || !slot->bitmap.rows) continue;

      if (slot->bitmap.pixel_mode != FT_PIXEL_MODE_LCD) {
        unsigned int pixel_mode;
        switch (slot->bitmap.pixel_mode) {
          case FT_PIXEL_MODE_MONO: pixel_mode = SDL_PIXELFORMAT_INDEX1MSB; bits_per_pixel = 1; break;
          case FT_PIXEL_MODE_GRAY: pixel_mode = SDL_PIXELFORMAT_INDEX8;    bits_per_pixel = 8; break;
          case FT_PIXEL_MODE_BGRA: pixel_mode = SDL_PIXELFORMAT_BGRA8888;  bits_per_pixel = 32; break;
        }
        // for BGRA surfaces we need to convert it to a surface in case we need to perform a scaled blit
        SDL_Surface *glyph_surface = check_alloc(SDL_CreateRGBSurfaceWithFormatFrom(slot->bitmap.buffer,
                                                                                    slot->bitmap.width, slot->bitmap.rows,
                                                                                    bits_per_pixel, slot->bitmap.pitch,
                                                                                    pixel_mode));

        // set palettes for the indexed color modes
        if (pixel_mode == SDL_PIXELFORMAT_INDEX1MSB)
          SDL_SetPaletteColors(glyph_surface->format->palette, monochrome_palette, 0, array_sizeof(monochrome_palette));
        else if (pixel_mode == SDL_PIXELFORMAT_INDEX8)
          SDL_SetPaletteColors(glyph_surface->format->palette, grayscale_palette, 0, array_sizeof(grayscale_palette));

        SDL_Rect src = { .x = 0, .y = 0, .w = slot->bitmap.width, .h = slot->bitmap.rows };
        SDL_Rect dst = { .x = set->metrics[i].x0, .y = 0, .w = slot->bitmap.width / font->bitmap_scale, .h = slot->bitmap.rows / font->bitmap_scale };

        // perform a scaled blit if necessary
        if (font->bitmap_scale != 1.0f) {
          if (bits_per_pixel != 32) {
            // a scaled blit requires a 32bpp surface
            SDL_Surface *temp = check_alloc(SDL_ConvertSurface(glyph_surface, set->surface->format, 0));
            SDL_FreeSurface(glyph_surface);
            glyph_surface = temp;
          }

          SDL_BlitScaled(glyph_surface, &src, set->surface, &dst);
        } else {
          SDL_BlitSurface(glyph_surface, &src, set->surface, &dst);
        }

        SDL_FreeSurface(glyph_surface);
      } else {
        // copy the pixels over for custom blending later
        for (unsigned int line = 0; line < slot->bitmap.rows; ++line) {
          int target_offset = line * set->surface->pitch + set->metrics[i].x0 * 3;
          int source_offset = line * slot->bitmap.pitch;
          // copy the entire row
          memcpy(&pixels[target_offset], &slot->bitmap.buffer[source_offset], slot->bitmap.width);
        }
      }
    }
  }
}

static GlyphSet* font_get_glyphset(RenFont* font, unsigned int codepoint, int subpixel_idx) {
  int idx = (codepoint / GLYPHSET_SIZE) % MAX_LOADABLE_GLYPHSETS;
  if (!font->sets[font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? subpixel_idx : 0][idx])
    font_load_glyphset(font, idx);
  return font->sets[font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? subpixel_idx : 0][idx];
}

static RenFont* font_group_get_glyph(GlyphSet** set, GlyphMetric** metric, RenFont** fonts, unsigned int codepoint, int bitmap_index) {
  if (!metric) {
    return NULL;
  }
  if (bitmap_index < 0)
    bitmap_index += SUBPIXEL_BITMAPS_CACHED;
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; ++i) {
    *set = font_get_glyphset(fonts[i], codepoint, bitmap_index);
    *metric = &(*set)->metrics[codepoint % GLYPHSET_SIZE];
    if ((*metric)->loaded || codepoint < 0xFF)
      return fonts[i];
  }
  if (*metric && !(*metric)->loaded && codepoint > 0xFF && codepoint != 0x25A1)
    return font_group_get_glyph(set, metric, fonts, 0x25A1, bitmap_index);
  return fonts[0];
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

static FT_Error font_select_optimal_size(FT_Face face, int size) {
  if (FT_IS_SCALABLE(face))
    return FT_Set_Pixel_Sizes(face, 0, size);

  if (face->num_fixed_sizes == 0) return FT_Err_Missing_Bitmap;

  int best_idx = 0;
  float best_diff = fabs(face->available_sizes[0].height - size);
  for (int i = 1; i < face->num_fixed_sizes; ++i) {
    float current_diff = fabs(face->available_sizes[i].height - size);
    if (current_diff < best_diff) {
      best_idx = i;
      best_diff = current_diff;
    }
  }

  return FT_Select_Size(face, best_idx);
}

static FT_Error font_set_metrics(RenFont *font) {
  FT_Error err;

  if (FT_IS_SCALABLE(font->face)) {
    font->height = (short)((font->face->height / (float)font->face->units_per_EM) * font->size);
    font->baseline = (short)((font->face->ascender / (float)font->face->units_per_EM) * font->size);
    font->underline_thickness = (unsigned short)((font->face->underline_thickness / (float) font->face->units_per_EM) * font->size);
  } else {
    font->height = (short) font->face->size->metrics.height / 64.0f;
    font->baseline = (short) font->face->size->metrics.ascender / 64.0f;

    // disable AA and hinting for non-scalable fonts
    font->antialiasing = FONT_ANTIALIASING_NONE;
    font->hinting = FONT_HINTING_NONE;
    font->style = 0;

    // scale font metrics based on the scale
    font->bitmap_scale = font->height / font->size;
    font->height = font->height / font->bitmap_scale;
    font->baseline = font->baseline / font->bitmap_scale;
  }

  // fallback for underline thickness
  if(!font->underline_thickness)
    font->underline_thickness = ceil((double) font->height / 14.0);

  // calculate the space advance and tab advance
  if (( err = FT_Load_Char(font->face, ' ', font_get_load_options(font)) ))
    return err;

  font->space_advance = font->face->glyph->advance.x / 64.0f / font->bitmap_scale;
  font->tab_advance = font->space_advance * 2;

  return FT_Err_Ok;
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
  if (font_select_optimal_size(face, size * surface_scale))
    goto failure;

  strcpy(font->path, path);
  font->face = face;
  font->size = size;
  font->antialiasing = antialiasing;
  font->hinting = hinting;
  font->style = style;
  font->bitmap_scale = 1.0f;

  font_set_metrics(font);

  if(FT_IS_SCALABLE(face))
    font->underline_thickness = (unsigned short)((face->underline_thickness / (float)face->units_per_EM) * font->size);
  if(!font->underline_thickness)
    font->underline_thickness = ceil((double) font->height / 14.0);

  if (FT_Load_Char(face, ' ', font_get_load_options(font)))
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
  unsigned int tab_index = '\t' % GLYPHSET_SIZE;
  for (int j = 0; j < FONT_FALLBACK_MAX && fonts[j]; ++j) {
    for (int i = 0; i < (fonts[j]->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? SUBPIXEL_BITMAPS_CACHED : 1); ++i)
      font_get_glyphset(fonts[j], '\t', i)->metrics[tab_index].xadvance = fonts[j]->space_advance * n;
  }
}

int ren_font_group_get_tab_size(RenFont **fonts) {
  unsigned int tab_index = '\t' % GLYPHSET_SIZE;
  float advance = font_get_glyphset(fonts[0], '\t', 0)->metrics[tab_index].xadvance;
  if (fonts[0]->space_advance) {
    advance /= fonts[0]->space_advance;
  }
  return advance;
}

float ren_font_group_get_size(RenFont **fonts) {
  return fonts[0]->size;
}

void ren_font_group_set_size(RenWindow *window_renderer, RenFont **fonts, float size) {
  const int surface_scale = renwin_get_surface(window_renderer).scale;
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; ++i) {
    font_clear_glyph_cache(fonts[i]);
    font_select_optimal_size(fonts[i]->face, size * surface_scale);
    fonts[i]->size = size;
    font_set_metrics(fonts[i]);
  }
}

int ren_font_group_get_height(RenFont **fonts) {
  return fonts[0]->height;
}

double ren_font_group_get_width(RenWindow *window_renderer, RenFont **fonts, const char *text, size_t len) {
  double width = 0;
  const char* end = text + len;
  GlyphMetric* metric = NULL; GlyphSet* set = NULL;
  while (text < end) {
    unsigned int codepoint;
    text = utf8_to_codepoint(text, &codepoint);
    RenFont* font = font_group_get_glyph(&set, &metric, fonts, codepoint, 0);
    if (!metric)
      break;
    width += (!font || metric->xadvance) ? metric->xadvance : fonts[0]->space_advance;
  }
  const int surface_scale = renwin_get_surface(window_renderer).scale;
  return width / surface_scale;
}

double ren_draw_text(RenSurface *rs, RenFont **fonts, const char *text, size_t len, float x, int y, RenColor color) {
  SDL_Surface *surface = rs->surface;
  SDL_Rect clip;
  SDL_GetClipRect(surface, &clip);

  const int surface_scale = rs->scale;
  double pen_x = x * surface_scale;
  y *= surface_scale;
  int bytes_per_pixel = surface->format->BytesPerPixel;
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
    GlyphSet* set = NULL; GlyphMetric* metric = NULL;
    RenFont* font = font_group_get_glyph(&set, &metric, fonts, codepoint, (int)(fmod(pen_x, 1.0) * SUBPIXEL_BITMAPS_CACHED));
    if (!metric)
      break;
    int start_x = floor(pen_x) + metric->bitmap_left;
    int end_x = (metric->x1 - metric->x0) + start_x;
    int glyph_end = metric->x1, glyph_start = metric->x0;
    if (!metric->loaded && codepoint > 0xFF)
      ren_draw_rect(rs, (RenRect){ start_x + 1, y, font->space_advance - 1, ren_font_group_get_height(fonts) }, color);
    if (set->surface && color.a > 0 && end_x >= clip.x && start_x < clip_end_x) {
      uint8_t* source_pixels = set->surface->pixels;
      for (int line = metric->y0; line < metric->y1; ++line) {
        int target_y = line + y - metric->bitmap_top + font->baseline * surface_scale;
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
        uint32_t* destination_pixel = (uint32_t*)&(destination_pixels[surface->pitch * target_y + start_x * bytes_per_pixel]);
        uint8_t* source_pixel = &source_pixels[line * set->surface->pitch + glyph_start * set->surface->format->BytesPerPixel];
        for (int x = glyph_start; x < glyph_end; ++x) {
          uint32_t destination_color = *destination_pixel;
          // the standard way of doing this would be SDL_GetRGBA, but that introduces a performance regression. needs to be investigated
          SDL_Color dst = {
            (destination_color & surface->format->Rmask) >> surface->format->Rshift,
            (destination_color & surface->format->Gmask) >> surface->format->Gshift,
            (destination_color & surface->format->Bmask) >> surface->format->Bshift,
            (destination_color & surface->format->Amask) >> surface->format->Ashift
          };
          SDL_Color src;

          switch (set->surface->format->BytesPerPixel) {
            case 3: // RGB888 from freetype
            src.r = *(source_pixel++);
            src.g = *(source_pixel++);
            src.b = *(source_pixel++);
            src.a = 0xFF;
            break;

            case 4: // RGBA/BGRA888
            src.r = (*((uint32_t *) source_pixel) & set->surface->format->Rmask) >> set->surface->format->Rshift;
            src.g = (*((uint32_t *) source_pixel) & set->surface->format->Gmask) >> set->surface->format->Gshift;
            src.b = (*((uint32_t *) source_pixel) & set->surface->format->Bmask) >> set->surface->format->Bshift;
            src.a = (*((uint32_t *) source_pixel) & set->surface->format->Amask) >> set->surface->format->Ashift;
            source_pixel += 4;
            break;

            case 1: // grayscale
            src.r = *source_pixel;
            src.g = *source_pixel;
            src.b = *(source_pixel++);
            src.a = 0xFF;
            break;
          }

          r = (color.r * src.r * color.a + dst.r * (65025 - src.r * color.a) + 32767) / 65025;
          g = (color.g * src.g * color.a + dst.g * (65025 - src.g * color.a) + 32767) / 65025;
          b = (color.b * src.b * color.a + dst.b * (65025 - src.b * color.a) + 32767) / 65025;
          // the standard way of doing this would be SDL_GetRGBA, but that introduces a performance regression. needs to be investigated
          *destination_pixel++ = dst.a << surface->format->Ashift | r << surface->format->Rshift | g << surface->format->Gshift | b << surface->format->Bshift;
        }
      }
    }

    float adv = metric->xadvance ? metric->xadvance : font->space_advance;

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
void ren_free_window_resources(RenWindow *window_renderer) {
  renwin_free(window_renderer);
  SDL_FreeSurface(draw_rect_surface);
  free(window_renderer->command_buf);
  window_renderer->command_buf = NULL;
  window_renderer->command_buf_size = 0;
}

// TODO remove global and return RenWindow*
void ren_init(SDL_Window *win) {
  assert(win);
  int error = FT_Init_FreeType( &library );
  if ( error ) {
    fprintf(stderr, "internal font error when starting the application\n");
    return;
  }
  window_renderer.window = win;
  renwin_init_surface(&window_renderer);
  renwin_init_command_buf(&window_renderer);
  renwin_clip_to_surface(&window_renderer);
  draw_rect_surface = SDL_CreateRGBSurface(0, 1, 1, 32,
                       0xFF000000, 0x00FF0000, 0x0000FF00, 0x000000FF);

  // initialize the grayscale palette
  for (int i = 0; i < sizeof(grayscale_palette) / sizeof(*grayscale_palette); ++i)
    grayscale_palette[i].r = grayscale_palette[i].g = grayscale_palette[i].b = i;
}


void ren_resize_window(RenWindow *window_renderer) {
  renwin_resize_surface(window_renderer);
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
