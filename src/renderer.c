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

#include <libatures.h>

#ifdef _WIN32
#include <windows.h>
#include "utfconv.h"
#endif
#if defined(_MSC_VER)
#include <BaseTsd.h>
typedef SSIZE_T ssize_t;
#endif

#include "renderer.h"
#include "renwindow.h"

#define MAX_UNICODE 0x100000
#define GLYPHSET_SIZE 256
#define MAX_LOADABLE_GLYPHSETS (MAX_UNICODE / GLYPHSET_SIZE)
#define SUBPIXEL_BITMAPS_CACHED 3

static RenWindow **window_list = NULL;
static size_t window_count = 0;
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
  float size, space_advance, tab_advance;
#ifdef LITE_USE_SDL_RENDERER
  int scale;
#endif
  unsigned short max_height, baseline, height;
  ERenFontAntialiasing antialiasing;
  ERenFontHinting hinting;
  unsigned char style;
  unsigned short underline_thickness;
  RenFontLigatureOptions ligopt;
  LBT_ChainCreator *chain_creator;
  LBT_Chain *chain;
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

static void font_load_glyphset(RenFont* font, int idx) {
  unsigned int render_option = font_set_render_options(font), load_option = font_set_load_options(font);
  int bitmaps_cached = font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? SUBPIXEL_BITMAPS_CACHED : 1;
  unsigned int byte_width = font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? 3 : 1;
  for (int j = 0, pen_x = 0; j < bitmaps_cached; ++j) {
    GlyphSet* set = check_alloc(calloc(1, sizeof(GlyphSet)));
    font->sets[j][idx] = set;
    for (int i = 0; i < GLYPHSET_SIZE; ++i) {
      int glyph_index = i + idx * GLYPHSET_SIZE;
      if (FT_Load_Glyph(font->face, glyph_index, load_option | FT_LOAD_BITMAP_METRICS_ONLY)
        || font_set_style(&font->face->glyph->outline, j * (64 / SUBPIXEL_BITMAPS_CACHED), font->style) || FT_Render_Glyph(font->face->glyph, render_option)) {
        continue;
      }
      FT_GlyphSlot slot = font->face->glyph;
      unsigned int glyph_width = slot->bitmap.width / byte_width;
      if (font->antialiasing == FONT_ANTIALIASING_NONE)
        glyph_width *= 8;
      set->metrics[i] = (GlyphMetric){ pen_x, pen_x + glyph_width, 0, slot->bitmap.rows, true, slot->bitmap_left, slot->bitmap_top, (slot->advance.x + slot->lsb_delta - slot->rsb_delta) / 64.0f};
      pen_x += glyph_width;
      font->max_height = slot->bitmap.rows > font->max_height ? slot->bitmap.rows : font->max_height;
      // In order to fix issues with monospacing; we need the unhinted xadvance; as FreeType doesn't correctly report the hinted advance for spaces on monospace fonts (like RobotoMono). See #843.
      if (FT_Load_Glyph(font->face, glyph_index, (load_option | FT_LOAD_BITMAP_METRICS_ONLY | FT_LOAD_NO_HINTING) & ~FT_LOAD_FORCE_AUTOHINT)
        || font_set_style(&font->face->glyph->outline, j * (64 / SUBPIXEL_BITMAPS_CACHED), font->style) || FT_Render_Glyph(font->face->glyph, render_option)) {
        continue;
      }
      slot = font->face->glyph;
      set->metrics[i].xadvance = slot->advance.x / 64.0f;
    }
    if (pen_x == 0)
      continue;
    set->surface = check_alloc(SDL_CreateRGBSurface(0, pen_x, font->max_height, font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? 24 : 8, 0, 0, 0, 0));
    uint8_t* pixels = set->surface->pixels;
    for (int i = 0; i < GLYPHSET_SIZE; ++i) {
      int glyph_index = i + idx * GLYPHSET_SIZE;
      if (FT_Load_Glyph(font->face, glyph_index, load_option))
        continue;
      FT_GlyphSlot slot = font->face->glyph;
      font_set_style(&slot->outline, (64 / bitmaps_cached) * j, font->style);
      if (FT_Render_Glyph(slot, render_option))
        continue;
      for (unsigned int line = 0; line < slot->bitmap.rows; ++line) {
        int target_offset = set->surface->pitch * line + set->metrics[i].x0 * byte_width;
        int source_offset = line * slot->bitmap.pitch;
        if (font->antialiasing == FONT_ANTIALIASING_NONE) {
          for (unsigned int column = 0; column < slot->bitmap.width; ++column) {
            int current_source_offset = source_offset + (column / 8);
            int source_pixel = slot->bitmap.buffer[current_source_offset];
            pixels[++target_offset] = ((source_pixel >> (7 - (column % 8))) & 0x1) * 0xFF;
          }
        } else
          memcpy(&pixels[target_offset], &slot->bitmap.buffer[source_offset], slot->bitmap.width);
      }
    }
  }
}

static GlyphSet* font_get_glyphset(RenFont* font, LBT_Glyph glyphID, int subpixel_idx) {
  int idx = (glyphID / GLYPHSET_SIZE) % MAX_LOADABLE_GLYPHSETS;
  if (!font->sets[font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? subpixel_idx : 0][idx])
    font_load_glyphset(font, idx);
  return font->sets[font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? subpixel_idx : 0][idx];
}

static void font_get_glyph(GlyphSet** set, GlyphMetric** metric, RenFont* font, LBT_Glyph glyphID, int bitmap_index) {
  if (!metric) {
    return;
  }
  if (bitmap_index < 0)
    bitmap_index += SUBPIXEL_BITMAPS_CACHED;
  *set = font_get_glyphset(font, glyphID, bitmap_index);
  *metric = &(*set)->metrics[glyphID % GLYPHSET_SIZE];
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

RenFont* ren_font_load(const char* path, float size, ERenFontAntialiasing antialiasing, ERenFontHinting hinting, unsigned char style, RenFontLigatureOptions ligopt) {
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

  font->ligopt = ligopt;

  font->chain_creator = LBT_new(face);
  if (font->chain_creator == NULL)
    goto failure;

  font->chain = LBT_generate_chain(font->chain_creator, ligopt.script, ligopt.language, ligopt.features, ligopt.n_features);

  if (FT_Set_Pixel_Sizes(face, 0, (int)(size)))
    goto failure;

  strcpy(font->path, path);
  font->face = face;
  font->size = size;
#ifdef LITE_USE_SDL_RENDERER
  font->scale = 1;
#endif
  font->height = (short)((face->height / (float)face->units_per_EM) * font->size);
  font->baseline = (short)((face->ascender / (float)face->units_per_EM) * font->size);
  font->antialiasing = antialiasing;
  font->hinting = hinting;
  font->style = style;

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

RenFont* ren_font_copy(RenFont* font, float size, ERenFontAntialiasing antialiasing, ERenFontHinting hinting, int style, const RenFontLigatureOptions *ligopt) {
  antialiasing = antialiasing == -1 ? font->antialiasing : antialiasing;
  hinting = hinting == -1 ? font->hinting : hinting;
  style = style == -1 ? font->style : style;
  RenFontLigatureOptions _ligopt;
  if (ligopt == NULL) {
    _ligopt = font->ligopt;
    _ligopt.features = malloc(sizeof(unsigned char [4]) * font->ligopt.n_features);
    memcpy(_ligopt.features, font->ligopt.features, sizeof(unsigned char [4]) * font->ligopt.n_features);
  } else {
    _ligopt = *ligopt;
  }

  return ren_font_load(font->path, size, antialiasing, hinting, style, _ligopt);
}

const char* ren_font_get_path(RenFont *font) {
  return font->path;
}

void ren_font_free(RenFont* font) {
  font_clear_glyph_cache(font);
  FT_Done_Face(font->face);
  free(font->ligopt.features);
  LBT_destroy_chain(font->chain);
  LBT_destroy(font->chain_creator);
  free(font);
}

void ren_font_group_set_tab_size(RenFont **fonts, int n) {
  fonts[0]->tab_advance = fonts[0]->space_advance * n;
}

int ren_font_group_get_tab_size(RenFont **fonts) {
  return fonts[0]->tab_advance / fonts[0]->space_advance;
}

float ren_font_group_get_size(RenFont **fonts) {
  return fonts[0]->size;
}

void ren_font_group_set_size(RenFont **fonts, float size, int surface_scale) {
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; ++i) {
    font_clear_glyph_cache(fonts[i]);
    FT_Face face = fonts[i]->face;
    FT_Set_Pixel_Sizes(face, 0, (int)(size*surface_scale));
    fonts[i]->size = size;
#ifdef LITE_USE_SDL_RENDERER
    fonts[i]->scale = surface_scale;
#endif
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

typedef struct GlyphRun {
  LBT_Glyph* glyphs;
  size_t n_glyphs;
} GlyphRun;

typedef struct GlyphRun_gen {
  GlyphRun run;
  RenFont *font;
} GlyphRun_gen;

GlyphRun_gen* get_runs(RenFont **fonts, const char *string, size_t len, size_t *n_runs) {
  GlyphRun_gen* gr_array = NULL;
  *n_runs = 0;
  const char* end = string + len;
  ssize_t last_font_idx = FONT_FALLBACK_MAX;
  while (string < end) {
    ssize_t font_idx = 0;
    uint32_t codepoint;
    string = utf8_to_codepoint(string, &codepoint);
    LBT_Glyph g = 0;
    if (codepoint == '\t' || codepoint == '\n') {
      font_idx = -1;
      g = codepoint;
    } else {
      while (g == 0 && fonts[font_idx] != NULL && font_idx < FONT_FALLBACK_MAX) {
        g = FT_Get_Char_Index(fonts[font_idx]->face, codepoint);
        if (g == 0)
          font_idx++;
      }
      // If the glyph wasn't found, fallback to the main font
      if (font_idx >= FONT_FALLBACK_MAX || fonts[font_idx] == NULL)
        font_idx = 0;
    }
    if (font_idx != last_font_idx) {
      gr_array = realloc(gr_array, sizeof(GlyphRun_gen) * (*n_runs + 1));
      memset(&gr_array[*n_runs], 0, sizeof(GlyphRun_gen));
      if (font_idx >= 0) {
        gr_array[*n_runs].font = fonts[font_idx];
      }
      (*n_runs)++;
    }
    gr_array[*n_runs - 1].run.glyphs = realloc(gr_array[*n_runs - 1].run.glyphs, sizeof(LBT_Glyph) * (gr_array[*n_runs - 1].run.n_glyphs + 1));
    gr_array[*n_runs - 1].run.glyphs[gr_array[*n_runs - 1].run.n_glyphs] = g;
    gr_array[*n_runs - 1].run.n_glyphs++;
    last_font_idx = font_idx;
  }
  return gr_array;
}

double ren_font_group_get_width(RenFont **fonts, const char *text, size_t len, int *x_offset) {
  double width = 0;
  size_t n_runs = 0;
  GlyphRun_gen* gr_array = get_runs(fonts, text, len, &n_runs);

  GlyphMetric* metric = NULL; GlyphSet* set = NULL;
  bool set_x_offset = x_offset == NULL;
  for (size_t z = 0; z < n_runs; z++) {
    RenFont *font = gr_array[z].font;
    if (font == NULL) { // The glyphs are "special"
      for (size_t i = 0; i < gr_array[z].run.n_glyphs; i++) {
        width += gr_array[z].run.glyphs[i] == '\t' ? fonts[0]->tab_advance : fonts[0]->space_advance;
      }
      free(gr_array[z].run.glyphs);
      continue;
    }
    size_t n_glyphs = 0;
    LBT_Glyph *ligated = LBT_apply_chain(font->chain, gr_array[z].run.glyphs, gr_array[z].run.n_glyphs, &n_glyphs);
    free(gr_array[z].run.glyphs);
    for (size_t i = 0; i < n_glyphs; i++) {
      font_get_glyph(&set, &metric, font, ligated[i], 0);
      if (!metric)
        break;
      width += (!font || metric->xadvance) ? metric->xadvance : fonts[0]->space_advance;
      if (!set_x_offset) {
        set_x_offset = true;
        *x_offset = metric->bitmap_left; // TODO: should this be scaled by the surface scale?
      }
    }
    free(ligated);
  }
  free(gr_array);
  if (!set_x_offset) {
    *x_offset = 0;
  }
#ifdef LITE_USE_SDL_RENDERER
  return width / fonts[0]->scale;
#else
  return width;
#endif
}

double ren_draw_text(RenSurface *rs, RenFont **fonts, const char *text, size_t len, float x, int y, RenColor color) {
  SDL_Surface *surface = rs->surface;
  SDL_Rect clip;
  SDL_GetClipRect(surface, &clip);

  size_t n_runs = 0;
  GlyphRun_gen* gr_array = get_runs(fonts, text, len, &n_runs);
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

  for (size_t z = 0; z < n_runs; z++) {
    RenFont *font = gr_array[z].font;
    if (font == NULL) { // The glyphs are "special"
      for (size_t i = 0; i < gr_array[z].run.n_glyphs; i++) {
        pen_x += gr_array[z].run.glyphs[i] == '\t' ? fonts[0]->tab_advance : fonts[0]->space_advance;
      }
      free(gr_array[z].run.glyphs);
      continue;
    }
    size_t n_glyphs = 0;
    LBT_Glyph *ligated = LBT_apply_chain(font->chain, gr_array[z].run.glyphs, gr_array[z].run.n_glyphs, &n_glyphs);
    free(gr_array[z].run.glyphs);
    for (size_t i = 0; i < n_glyphs; i++) {
      // unsigned int codepoint, r, g, b;
      unsigned int r, g, b;
      // text = utf8_to_codepoint(text, &codepoint);
      GlyphSet* set = NULL; GlyphMetric* metric = NULL;
      font_get_glyph(&set, &metric, font, ligated[i], (int)(fmod(pen_x, 1.0) * SUBPIXEL_BITMAPS_CACHED));
      if (!metric)
        break;
      int start_x = floor(pen_x) + metric->bitmap_left;
      int end_x = (metric->x1 - metric->x0) + start_x;
      int glyph_end = metric->x1, glyph_start = metric->x0;
      if (!metric->loaded)// && codepoint > 0xFF)
        ren_draw_rect(rs, (RenRect){ start_x + 1, y, font->space_advance - 1, ren_font_group_get_height(fonts) }, color);
      if (set->surface && color.a > 0 && end_x >= clip.x && start_x < clip_end_x) {
        uint8_t* source_pixels = set->surface->pixels;
        for (int line = metric->y0; line < metric->y1; ++line) {
          int target_y = line + y - metric->bitmap_top + fonts[0]->baseline * surface_scale;
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
          uint8_t* source_pixel = &source_pixels[line * set->surface->pitch + glyph_start * (font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? 3 : 1)];
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
    free(ligated);
  }
  free(gr_array);
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

  if ((err = FT_Init_FreeType( &library )))
    return err;

  return 0;
}

void ren_free(void) {
   SDL_FreeSurface(draw_rect_surface);
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
