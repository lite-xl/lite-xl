#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <assert.h>
#include <math.h>
#include <ft2build.h>
#include <freetype/ftlcdfil.h>
#include <freetype/ftoutln.h>
#include FT_CACHE_H
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

typedef struct RenFaceID RenFaceID;

RenWindow window_renderer = {0};

// FIXME: will not work if multiple threads are using the library and manager
static FT_Library library;
static FTC_Manager manager;
static RenFaceID** face_ids = NULL;
static int face_ids_capacity = 0;
static int face_ids_max_idx = -1;

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
  // the scaler contains the path as ((RenFaceID*)scaler.face_id)->path
  FTC_ScalerRec scaler;
  GlyphSet* sets[SUBPIXEL_BITMAPS_CACHED][MAX_LOADABLE_GLYPHSETS];
  float size, space_advance, tab_advance;
  unsigned short max_height, baseline, height;
  ERenFontAntialiasing antialiasing;
  ERenFontHinting hinting;
  unsigned char style;
  unsigned short underline_thickness;
} RenFont;

// A face ID intended to be used as FTC_FaceID, this is refcounted and stored at FTC_Scaler->face_id
struct RenFaceID {
  int refcount;
  char path[];
};

#ifndef max
#define max(a, b) ((a) > (b) ? (a) : (b))
#endif

#ifdef _WIN32
// used to store the handle and data so that the file is protected when it is used
typedef struct {
  HANDLE handle;
  char data[];
} RenFontFile;

static void ren_font_file_free(void* object) {
  RenFontFile* file = ((FT_Face) object)->generic.data;
  if (file->handle) CloseHandle(file->handle);
  free(file);
}
#endif

// FT_Face_Requester for FTC subsystem
static FT_Error open_face(FTC_FaceID face_id, FT_Library library, FT_Pointer req_data, FT_Face* aface) {
  FT_Error err = FT_Err_Ok;
  RenFaceID* id = (RenFaceID*) face_id;

#ifdef _WIN32
  HANDLE file_handle = NULL;
  wchar_t* wpath = NULL;
  RenFontFile* file = NULL;
  DWORD read = 0;

  wpath = utfconv_utf8towc(id->path);
  if (!wpath) {
    err = FT_Err_Out_Of_Memory;
    goto cleanup;
  }

  file_handle = CreateFileW(wpath,
                            GENERIC_READ,
                            FILE_SHARE_READ, // or else we can't copy fonts
                            NULL,
                            OPEN_EXISTING,
                            FILE_ATTRIBUTE_NORMAL,
                            NULL);
  if (file_handle == INVALID_HANDLE_VALUE) {
    err = FT_Err_Cannot_Open_Resource;
    goto cleanup;
  }

  read = GetFileSize(file_handle, NULL);
  if (read == INVALID_FILE_SIZE) {
    err = FT_Err_Cannot_Open_Resource;
    goto cleanup;
  }

  file = malloc(sizeof(RenFontFile) + read);
  if (!file) {
    err = FT_Err_Out_Of_Memory;
    goto cleanup;
  }

  file->handle = file_handle;
  if (!ReadFile(file_handle, file->data, read, &read, NULL)) {
    err = FT_Err_Cannot_Open_Resource;
    goto cleanup;
  }

  err = FT_New_Memory_Face(library, file->data, read, 0, aface);
  if (err)
    goto cleanup;

  // save the RenFontFile as client data so it gets freed up along with face
  (*aface)->generic.data = file;
  (*aface)->generic.finalizer = &ren_font_file_free;
#else
  err = FT_New_Face(library, id->path, 0, aface);
#endif

#ifdef _WIN32
cleanup:
  free(wpath);
  if (err != FT_Err_Ok) {
    free(file);
    if (file_handle) CloseHandle(file_handle);
  }
#endif
  return err;
}

static RenFaceID* get_face_id(const char* path) {
  RenFaceID* id = NULL;
  int free_face_id_idx = -1;
  // find an existing face ID or find an unused slot
  for (int i = 0; i <= face_ids_max_idx; ++i) {
    if (free_face_id_idx == -1 && !face_ids[i])
      free_face_id_idx = i;

    if (face_ids[i] && strcmp(face_ids[i]->path, path) == 0) {
      id = face_ids[i];
      break;
    }
  }

  // if no unused slots are found we need to create a new slot
  if (!id && free_face_id_idx == -1)
    free_face_id_idx = ++face_ids_max_idx;

  if (!id) {
    // allocate RenFaceID
    int len = strlen(path);
    id = check_alloc(malloc(sizeof(RenFaceID) + len + 1));
    id->refcount = 0;
    strncpy(id->path, path, len + 1);

    if (free_face_id_idx >= face_ids_capacity) {
      int new_capacity = max(3, face_ids_capacity * 2);
      face_ids = check_alloc(realloc(face_ids, sizeof(RenFaceID*) * new_capacity));
      memset(face_ids + face_ids_capacity, 0, (new_capacity - face_ids_capacity) * sizeof(RenFaceID*));
      face_ids_capacity = new_capacity;
    }
    face_ids[free_face_id_idx] = id;
  }
  id->refcount++;
  return id;
}

static void free_face_id(RenFaceID* id) {
  id->refcount--;
  if (!id->refcount) {
    FTC_Manager_RemoveFaceID(manager, id);
    for (int i = 0; i <= face_ids_max_idx; ++i) {
      if (face_ids[i] == id) {
        face_ids[i] = NULL;
        break;
      }
    }
    free(id);
  }
}

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

static FT_Error font_get_face(RenFont* font, FT_Face* aface) {
  FT_Error err = FT_Err_Ok;
  FT_Size face_size;
  if ((err = FTC_Manager_LookupSize(manager, &font->scaler, &face_size)))
    return err;
  *aface = face_size->face;
  return err;
}

static void font_load_glyphset(RenFont* font, int idx) {
  unsigned int render_option = font_set_render_options(font), load_option = font_set_load_options(font);
  int bitmaps_cached = font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? SUBPIXEL_BITMAPS_CACHED : 1;
  unsigned int byte_width = font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? 3 : 1;
  FT_Face face;
  if (font_get_face(font, &face))
    return;

  for (int j = 0, pen_x = 0; j < bitmaps_cached; ++j) {
    GlyphSet* set = check_alloc(calloc(1, sizeof(GlyphSet)));
    font->sets[j][idx] = set;
    for (int i = 0; i < MAX_GLYPHSET; ++i) {
      int glyph_index = FT_Get_Char_Index(face, i + idx * MAX_GLYPHSET);
      if (!glyph_index || FT_Load_Glyph(face, glyph_index, load_option | FT_LOAD_BITMAP_METRICS_ONLY)
        || font_set_style(&face->glyph->outline, j * (64 / SUBPIXEL_BITMAPS_CACHED), font->style) || FT_Render_Glyph(face->glyph, render_option)) {
        continue;
      }
      FT_GlyphSlot slot = face->glyph;
      int glyph_width = slot->bitmap.width / byte_width;
      if (font->antialiasing == FONT_ANTIALIASING_NONE)
        glyph_width *= 8;
      set->metrics[i] = (GlyphMetric){ pen_x, pen_x + glyph_width, 0, slot->bitmap.rows, true, slot->bitmap_left, slot->bitmap_top, (slot->advance.x + slot->lsb_delta - slot->rsb_delta) / 64.0f};
      pen_x += glyph_width;
      font->max_height = slot->bitmap.rows > font->max_height ? slot->bitmap.rows : font->max_height;
      // In order to fix issues with monospacing; we need the unhinted xadvance; as FreeType doesn't correctly report the hinted advance for spaces on monospace fonts (like RobotoMono). See #843.
      if (!glyph_index || FT_Load_Glyph(face, glyph_index, (load_option | FT_LOAD_BITMAP_METRICS_ONLY | FT_LOAD_NO_HINTING) & ~FT_LOAD_FORCE_AUTOHINT)
        || font_set_style(&face->glyph->outline, j * (64 / SUBPIXEL_BITMAPS_CACHED), font->style) || FT_Render_Glyph(face->glyph, render_option)) {
        continue;
      }
      slot = face->glyph;
      set->metrics[i].xadvance = slot->advance.x / 64.0f;
    }
    if (pen_x == 0)
      continue;
    set->surface = check_alloc(SDL_CreateRGBSurface(0, pen_x, font->max_height, font->antialiasing == FONT_ANTIALIASING_SUBPIXEL ? 24 : 8, 0, 0, 0, 0));
    uint8_t* pixels = set->surface->pixels;
    for (int i = 0; i < MAX_GLYPHSET; ++i) {
      int glyph_index = FT_Get_Char_Index(face, i + idx * MAX_GLYPHSET);
      if (!glyph_index || FT_Load_Glyph(face, glyph_index, load_option))
        continue;
      FT_GlyphSlot slot = face->glyph;
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
            pixels[++target_offset] = ((source_pixel >> (7 - (column % 8))) & 0x1) << 7;
          }
        } else
          memcpy(&pixels[target_offset], &slot->bitmap.buffer[source_offset], slot->bitmap.width);
      }
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
  if (!metric) {
    return NULL;
  }
  if (bitmap_index < 0)
    bitmap_index += SUBPIXEL_BITMAPS_CACHED;
  for (int i = 0; i < FONT_FALLBACK_MAX && fonts[i]; ++i) {
    *set = font_get_glyphset(fonts[i], codepoint, bitmap_index);
    *metric = &(*set)->metrics[codepoint % 256];
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

RenFont* ren_font_load(RenWindow *window_renderer, const char* path, float size, ERenFontAntialiasing antialiasing, ERenFontHinting hinting, unsigned char style) {
  FT_Face face = NULL;
  RenFont* font = NULL;
  RenFaceID* id = get_face_id(path);

  const int surface_scale = renwin_get_surface(window_renderer).scale;
  font = check_alloc(calloc(1, sizeof(RenFont)));
  font->scaler = (FTC_ScalerRec) { .face_id = (FTC_FaceID) id, .height = size * surface_scale, .width = 0, .pixel = true };

  if (font_get_face(font, &face))
    goto failure;

  font->size = size;
  font->height = (short)((face->height / (float)face->units_per_EM) * font->size);
  font->baseline = (short)((face->ascender / (float)face->units_per_EM) * font->size);
  font->antialiasing = antialiasing;
  font->hinting = hinting;
  font->style = style;

  if(FT_IS_SCALABLE(face))
    font->underline_thickness = (unsigned short)((face->underline_thickness / (float)face->units_per_EM) * font->size);
  if(!font->underline_thickness) font->underline_thickness = ceil((double) font->height / 14.0);

  if (FT_Load_Char(face, ' ', font_set_load_options(font)))
    goto failure;

  font->space_advance = face->glyph->advance.x / 64.0f;
  font->tab_advance = font->space_advance * 2;
  return font;

failure:
  if (id) free_face_id(id);
  return NULL;
}

RenFont* ren_font_copy(RenWindow *window_renderer, RenFont* font, float size, ERenFontAntialiasing antialiasing, ERenFontHinting hinting, int style) {
  antialiasing = antialiasing == -1 ? font->antialiasing : antialiasing;
  hinting = hinting == -1 ? font->hinting : hinting;
  style = style == -1 ? font->style : style;

  return ren_font_load(window_renderer, ren_font_get_path(font), size, antialiasing, hinting, style);
}

const char* ren_font_get_path(RenFont *font) {
  return ((RenFaceID*) font->scaler.face_id)->path;
}

void ren_font_free(RenFont* font) {
  font_clear_glyph_cache(font);
  free_face_id((RenFaceID*) font->scaler.face_id);
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
    FT_Face face;
    font_clear_glyph_cache(fonts[i]);
    fonts[i]->scaler.height = size * surface_scale;
    if (font_get_face(fonts[i], &face))
      continue;
    fonts[i]->size = size;
    fonts[i]->height = (short)((face->height / (float)face->units_per_EM) * size);
    fonts[i]->baseline = (short)((face->ascender / (float)face->units_per_EM) * size);
    if (FT_Load_Char(face, ' ', font_set_load_options(fonts[i])))
      continue;
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

  for (int i = 0; i < face_ids_capacity; ++i) {
    if (face_ids[i])
      FTC_Manager_RemoveFaceID(manager, (FTC_FaceID) face_ids[i]);
    free(face_ids[i]);
  }
  free(face_ids);
  FTC_Manager_Done(manager);
  FT_Done_FreeType(library);

  face_ids = NULL;
  face_ids_capacity = 0;
  face_ids_max_idx = -1;
  manager = NULL;
  library = NULL;
}

// TODO remove global and return RenWindow*
void ren_init(SDL_Window *win) {
  assert(win);
  int error = FT_Init_FreeType( &library );
  if ( error ) {
    fprintf(stderr, "internal font error when starting the application\n");
    return;
  }
  error = FTC_Manager_New(library, 0, 0, 0, &open_face, NULL, &manager);
  if (error) {
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
