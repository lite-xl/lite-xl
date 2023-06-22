#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <assert.h>
#include <math.h>
#include <ft2build.h>
#include <freetype/ftlcdfil.h>
#include <freetype/ftoutln.h>
#include FT_FREETYPE_H

#ifdef _WIN32
#include <windows.h>
#include "utfconv.h"
#endif

#include "renderer.h"
#include "renwindow.h"

#define MAX_GLYPHSET 256
#define MAX_LOADABLE_GLYPHSETS 4096
#define SUBPIXEL_BITMAPS_CACHED 3

RenWindow window_renderer = {0};
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

typedef struct {
  unsigned short x0, x1, y0, y1, loaded;
  short bitmap_left, bitmap_top;
  float xadvance;
} GlyphMetric;

typedef struct {
  SDL_Surface* surface;
  GlyphMetric metrics[MAX_GLYPHSET];
} GlyphSet;

typedef struct RenFont {
  FT_Face face;
  GlyphSet* sets[SUBPIXEL_BITMAPS_CACHED][MAX_LOADABLE_GLYPHSETS];

  SDL_Surface* missing_glyph_surface[SUBPIXEL_BITMAPS_CACHED];
  GlyphMetric missing_glyph_metric[SUBPIXEL_BITMAPS_CACHED];

  float size, space_advance, tab_advance;
  unsigned short max_height, baseline, height;
  ERenFontAntialiasing antialiasing;
  ERenFontHinting hinting;
  unsigned char style;
  unsigned short underline_thickness;
#ifdef _WIN32
  unsigned char *file;
  HANDLE file_handle;
#endif
  char path[];
} RenFont;

#ifndef min
#define min(a, b) ((a) > (b) ? (b) : (a))
#endif

#ifndef max
#define max(a, b) ((a) > (b) ? (a) : (b))
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

static FT_Error font_load_glyph_metric(RenFont* font,
                                        unsigned int glyph_index,
                                        unsigned int load_option,
                                        unsigned int render_option,
                                        int bitmap_index,
                                        GlyphMetric* metric) {
  FT_Error err = 0;
  FT_GlyphSlot slot;
  int glyph_width;

  if ((err = FT_Load_Glyph(font->face, glyph_index, load_option | FT_LOAD_BITMAP_METRICS_ONLY)))
    return err;

  if (font->face->glyph->format == FT_GLYPH_FORMAT_OUTLINE)
    font_set_style(&font->face->glyph->outline, bitmap_index * (64 / SUBPIXEL_BITMAPS_CACHED), font->style);

  if ((err = FT_Render_Glyph(font->face->glyph, render_option)))
    return err;

  slot = font->face->glyph;
  glyph_width = slot->bitmap.width;
  if (slot->bitmap.pixel_mode == FT_PIXEL_MODE_MONO)
    glyph_width *= 8;
  else if (slot->bitmap.pixel_mode == FT_PIXEL_MODE_LCD)
    glyph_width /= 3;

  // x0 and y0 are assumed correct
  metric->loaded = true;
  metric->x1 = metric->x0 + glyph_width;
  metric->y1 = metric->y1 + slot->bitmap.rows;
  metric->bitmap_left = slot->bitmap_left;
  metric->bitmap_top = slot->bitmap_top;
  metric->xadvance = (slot->advance.x + slot->lsb_delta - slot->rsb_delta) / 64.0f;

  font->max_height = max(font->max_height, slot->bitmap.rows);

  // workaround for wrong kerning when hinting is enabled on monospaced fonts, see #843
  // use the unhinted xadvance instead of calculating it from lsb_delta and rsb_delta
  if ((err = FT_Load_Glyph(font->face, glyph_index, (load_option | FT_LOAD_BITMAP_METRICS_ONLY | FT_LOAD_NO_HINTING) & ~FT_LOAD_FORCE_AUTOHINT)))
    return err;

  if (font->face->glyph->format == FT_GLYPH_FORMAT_OUTLINE)
    font_set_style(&font->face->glyph->outline, bitmap_index * (64 / SUBPIXEL_BITMAPS_CACHED), font->style);

  if ((err = FT_Render_Glyph(font->face->glyph, render_option)))
    return err;

  metric->xadvance = slot->advance.x / 64.0f;

  return err;
}

static FT_Error font_render_glyph(RenFont* font,
                                  unsigned int glyph_index,
                                  unsigned int load_option,
                                  unsigned int render_option,
                                  int bitmap_index,
                                  GlyphMetric* metric,
                                  SDL_Surface* surface) {
  FT_Error err = 0;
  uint8_t* pixels = surface->pixels;
  FT_GlyphSlot slot;

  if ((err = FT_Load_Glyph(font->face, glyph_index, load_option | FT_LOAD_BITMAP_METRICS_ONLY)))
    return err;

  if (font->face->glyph->format == FT_GLYPH_FORMAT_OUTLINE)
    font_set_style(&font->face->glyph->outline, bitmap_index * (64 / SUBPIXEL_BITMAPS_CACHED), font->style);

  if ((err = FT_Render_Glyph(font->face->glyph, render_option)))
    return err;

  slot = font->face->glyph;
  for (unsigned int line = 0; line < slot->bitmap.rows; ++line) {
    int target_offset = surface->pitch * line + metric->x0 * surface->format->BytesPerPixel;
    int source_offset = line * slot->bitmap.pitch;
    if (font->antialiasing == FONT_ANTIALIASING_NONE) {
      for (unsigned int column = 0; column < slot->bitmap.width; ++column) {
        int current_source_offset = source_offset + (column / 8);
        int source_pixel = slot->bitmap.buffer[current_source_offset];
        pixels[++target_offset] = ((source_pixel >> (7 - (column % 8))) & 0x1) << 7;
      }
    } else
      memcpy(&pixels[target_offset], &slot->bitmap.buffer[source_offset], slot->bitmap.width);
  }

  return err;
}

static void font_load_glyphset(RenFont* font, int idx) {
  unsigned int load_option = font_set_load_options(font);
  unsigned int render_option = font_set_render_options(font);
  int bitmaps_cached = font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? SUBPIXEL_BITMAPS_CACHED : 1;
  int bytes_per_pixel = bitmaps_cached;

  for (int j = 0; j < bitmaps_cached; ++j) {
    int pen_x = 0;
    GlyphSet* set = check_alloc(calloc(1, sizeof(GlyphSet)));
    font->sets[j][idx] = set;

    for (int i = 0; i < MAX_GLYPHSET; ++i) {
      unsigned int glyph_index = FT_Get_Char_Index(font->face, i + idx * MAX_GLYPHSET);
      if (!glyph_index)
        continue;

      set->metrics[i].x0 = pen_x;
      if (font_load_glyph_metric(font, glyph_index, load_option, render_option, j, &set->metrics[i]))
        continue;
      pen_x = set->metrics[i].x1;
    }

    if (pen_x == 0)
      continue;

    set->surface = check_alloc(SDL_CreateRGBSurface(0,
                                                    pen_x, font->max_height,
                                                    bytes_per_pixel * 8,
                                                    0, 0, 0, 0));

    for (int i = 0; i < MAX_GLYPHSET; ++i) {
      unsigned int glyph_index = FT_Get_Char_Index(font->face, i + idx * MAX_GLYPHSET);
      if (!glyph_index)
        continue;

      if (font_render_glyph(font, glyph_index, load_option, render_option, j, &set->metrics[i], set->surface))
        continue;
    }
  }
}

static GlyphSet* font_get_glyphset(RenFont* font, unsigned int codepoint, int subpixel_idx) {
  int idx = (codepoint >> 8) % MAX_LOADABLE_GLYPHSETS;
  if (!font->sets[font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? subpixel_idx : 0][idx])
    font_load_glyphset(font, idx);
  return font->sets[font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? subpixel_idx : 0][idx];
}

static RenFont* font_group_get_glyph(GlyphSet** set, GlyphMetric** metric, RenFont** fonts, unsigned int codepoint, int bitmap_index) {
  if (bitmap_index < 0)
    bitmap_index += SUBPIXEL_BITMAPS_CACHED;
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; ++i) {
    *set = font_get_glyphset(fonts[i], codepoint, bitmap_index);
    *metric = &(*set)->metrics[codepoint % 256];
    if ((*metric)->loaded)
      return fonts[i];
  }
  return NULL;
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

    memset(&font->missing_glyph_metric[i], 0, sizeof(GlyphMetric));
    if (font->missing_glyph_surface[i]) {
      SDL_FreeSurface(font->missing_glyph_surface[i]);
      font->missing_glyph_surface[i] = NULL;
    }
  }
}

RenFont* ren_font_load(RenWindow *window_renderer, const char* path, float size, ERenFontAntialiasing antialiasing, ERenFontHinting hinting, unsigned char style) {
  FT_Face face = NULL;

#ifdef _WIN32

  HANDLE file = INVALID_HANDLE_VALUE;
  DWORD read;
  int font_file_len = 0;
  unsigned char *font_file = NULL;
  wchar_t *wpath = NULL;

  if ((wpath = utfconv_utf8towc(path)) == NULL)
    return NULL;

  if ((file = CreateFileW(wpath,
                          GENERIC_READ,
                          FILE_SHARE_READ, // or else we can't copy fonts
                          NULL,
                          OPEN_EXISTING,
                          FILE_ATTRIBUTE_NORMAL,
                          NULL)) == INVALID_HANDLE_VALUE)
    goto failure;

  if ((font_file_len = GetFileSize(file, NULL)) == INVALID_FILE_SIZE)
    goto failure;

  font_file = check_alloc(malloc(font_file_len * sizeof(unsigned char)));
  if (!ReadFile(file, font_file, font_file_len, &read, NULL) || read != font_file_len)
    goto failure;

  free(wpath);
  wpath = NULL;

  if (FT_New_Memory_Face(library, font_file, read, 0, &face))
    goto failure;

#else

  if (FT_New_Face(library, path, 0, &face))
    return NULL;

#endif

  const int surface_scale = renwin_get_surface(window_renderer).scale;
  if (FT_Set_Pixel_Sizes(face, 0, (int)(size*surface_scale)))
    goto failure;
  int len = strlen(path);
  RenFont* font = check_alloc(calloc(1, sizeof(RenFont) + len + 1));
  strcpy(font->path, path);
  font->face = face;
  font->size = size;
  font->height = (short)((face->height / (float)face->units_per_EM) * font->size);
  font->baseline = (short)((face->ascender / (float)face->units_per_EM) * font->size);
  font->antialiasing = antialiasing;
  font->hinting = hinting;
  font->style = style;

#ifdef _WIN32
  // we need to keep this for freetype
  font->file = font_file;
  font->file_handle = file;
#endif

  if(FT_IS_SCALABLE(face))
    font->underline_thickness = (unsigned short)((face->underline_thickness / (float)face->units_per_EM) * font->size);
  if(!font->underline_thickness) font->underline_thickness = ceil((double) font->height / 14.0);

  if (FT_Load_Char(face, ' ', font_set_load_options(font))) {
    free(font);
    goto failure;
  }
  font->space_advance = face->glyph->advance.x / 64.0f;
  font->tab_advance = font->space_advance * 2;

  // load the missing glyph
  int bitmaps_cached = font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? SUBPIXEL_BITMAPS_CACHED : 1;
  unsigned int load_option = font_set_load_options(font);
  unsigned int render_option = font_set_render_options(font);
  for (int i = 0; i < bitmaps_cached; ++i) {
    if (font_load_glyph_metric(font, 0, load_option, render_option, i, &font->missing_glyph_metric[i])) {
      font->missing_glyph_metric[i].xadvance = font->space_advance;
      continue;
    }
  }
  for (int i = 0; i < bitmaps_cached; ++i) {
    if (font->missing_glyph_metric[i].x1 == 0 || font->missing_glyph_metric[i].y1 == 0)
      continue;
    font->missing_glyph_surface[i] = check_alloc(SDL_CreateRGBSurface(0,
                                                                      font->missing_glyph_metric[i].x1,
                                                                      font->missing_glyph_metric[i].y1,
                                                                      bitmaps_cached * 8,
                                                                      0, 0, 0, 0));
    if (font_render_glyph(font, 0, load_option, render_option, i, &font->missing_glyph_metric[i], font->missing_glyph_surface[i]))
      continue;
  }

  return font;

failure:
#ifdef _WIN32
  free(wpath);
  free(font_file);
  if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
#endif
  if (face != NULL)
    FT_Done_Face(face);
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
#ifdef _WIN32
  free(font->file);
  CloseHandle(font->file_handle);
#endif
  free(font);
}

void ren_font_group_set_tab_size(RenFont **fonts, int n) {
  for (int j = 0; j < FONT_FALLBACK_MAX && fonts[j]; ++j) {
    for (int i = 0; i < (fonts[j]->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? SUBPIXEL_BITMAPS_CACHED : 1); ++i)
      font_get_glyphset(fonts[j], '\t', i)->metrics['\t'].xadvance = fonts[j]->space_advance * n;
  }
}

int ren_font_group_get_tab_size(RenFont **fonts) {
  float advance = font_get_glyphset(fonts[0], '\t', 0)->metrics['\t'].xadvance;
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

double ren_font_group_get_width(RenWindow *window_renderer, RenFont **fonts, const char *text, size_t len) {
  double width = 0;
  const char* end = text + len;
  GlyphMetric* metric = NULL; GlyphSet* set = NULL;
  while (text < end) {
    unsigned int codepoint;
    text = utf8_to_codepoint(text, &codepoint);
    font_group_get_glyph(&set, &metric, fonts, codepoint, 0);
    if (!metric)
      break;
    if (metric->loaded)
      width += metric->xadvance;
    else
      width += max(fonts[0]->missing_glyph_metric[0].xadvance, fonts[0]->space_advance);
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
    GlyphSet* set = NULL;
    GlyphMetric* metric = NULL;
    SDL_Surface* glyph_surface = NULL;
    RenFont* font = font_group_get_glyph(&set, &metric, fonts, codepoint, (int)(fmod(pen_x, 1.0) * SUBPIXEL_BITMAPS_CACHED));
    if (!metric)
      break;

    glyph_surface = set->surface;
    if (!metric->loaded) {
      int bitmap_idx = (int)(fmod(pen_x, 1.0) * SUBPIXEL_BITMAPS_CACHED);
      font = fonts[0]; // FIXME: check fallback as well?
      metric = &font->missing_glyph_metric[bitmap_idx];
      glyph_surface = font->missing_glyph_surface[bitmap_idx];
    }
    int start_x = floor(pen_x) + metric->bitmap_left;
    int end_x = (metric->x1 - metric->x0) + start_x;
    int glyph_end = metric->x1, glyph_start = metric->x0;
    if (!glyph_surface) {
      // draw rectangle for fallback
      ren_draw_rect(rs, (RenRect) { start_x + 1, y, min(metric->xadvance, font->space_advance) - 1, ren_font_group_get_height(fonts) }, color);
    } else if (color.a > 0 && end_x >= clip.x && start_x < clip_end_x) {
      uint8_t* source_pixels = glyph_surface->pixels;
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
        uint8_t* source_pixel = &source_pixels[line * glyph_surface->pitch + glyph_start * (font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? 3 : 1)];
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
