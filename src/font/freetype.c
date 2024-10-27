#include <assert.h>
#include <SDL.h>
#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_LCD_FILTER_H
#include FT_OUTLINE_H
#include FT_SYSTEM_H

#include "renderer.h"

typedef struct font_face {
  FT_Face face;
} font_face;

FT_Library library = NULL;

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

static int font_set_load_options(RenFont* font) {
  int load_target = ren_font_get_antialiasing(font) == FONT_ANTIALIASING_NONE ? FT_LOAD_TARGET_MONO
    : (ren_font_get_hinting(font) == FONT_HINTING_SLIGHT ? FT_LOAD_TARGET_LIGHT : FT_LOAD_TARGET_NORMAL);
  int hinting = ren_font_get_hinting(font) == FONT_HINTING_NONE ? FT_LOAD_NO_HINTING : FT_LOAD_FORCE_AUTOHINT;
  return load_target | hinting;
}

static int font_set_render_options(RenFont* font) {
  ERenFontAntialiasing antialiasing = ren_font_get_antialiasing(font);
  ERenFontHinting hinting = ren_font_get_hinting(font);

  if (antialiasing == FONT_ANTIALIASING_NONE)
    return FT_RENDER_MODE_MONO;

  if (antialiasing == FONT_ANTIALIASING_SUBPIXEL) {
    unsigned char weights[] = { 0x10, 0x40, 0x70, 0x40, 0x10 } ;
    switch (hinting) {
      case FONT_HINTING_NONE: FT_Library_SetLcdFilter(library, FT_LCD_FILTER_NONE); break;
      case FONT_HINTING_SLIGHT:
      case FONT_HINTING_FULL: FT_Library_SetLcdFilterWeights(library, weights); break;
    }
    return FT_RENDER_MODE_LCD;
  } else {
    switch (hinting) {
      case FONT_HINTING_NONE:   return FT_RENDER_MODE_NORMAL; break;
      case FONT_HINTING_SLIGHT: return FT_RENDER_MODE_LIGHT; break;
      case FONT_HINTING_FULL:   return FT_RENDER_MODE_LIGHT; break;
    }
  }
  return 0;
}

int font_face_is_scalable(font_face *face);

/* FT_Init_FreeType */
int font_init(void** plib) {
  assert(!library);

  return FT_Init_FreeType(&library);
}

/* FT_Done_FreeType */
void font_done(void) {
  assert(library);

  FT_Done_FreeType(library); 
}

/* FT_Open_Face */
int font_face_open(const char* path, font_face **face) {
  assert(library);

  SDL_RWops *file = NULL;
  FT_Stream stream = NULL;

  file = SDL_RWFromFile(path, "rb");
  if (!file) return 1;

  stream = calloc(1, sizeof(FT_StreamRec));
  if (!stream) goto stream_failure;
  stream->read = &font_file_read;
  stream->close = &font_file_close;
  stream->descriptor.pointer = file;
  stream->pos = 0;
  stream->size = (unsigned long) SDL_RWsize(file);

  *face = calloc(1, sizeof(**face));

  if (FT_Open_Face(library, &(FT_Open_Args) { .flags = FT_OPEN_STREAM, .stream = stream }, 0, &((*face)->face)) != 0)
    goto failure;

  return 0;

stream_failure:
  if (file) SDL_RWclose(file);
failure:
  if (*face) FT_Done_Face((*face)->face);
  return 1;
}

/* FT_Done_Face */
void font_face_close(font_face *face) {
  FT_Done_Face(face->face);
}

const char* font_face_get_family_name(font_face *face) {
  return face->face->family_name;
}

float font_face_get_height(font_face *face) {
  if (font_face_is_scalable(face))
    return face->face->height / (float)face->face->units_per_EM;

  return face->face->size->metrics.height / 64.0f;
}

float font_face_get_advanced_width(font_face* face) {
  return face->face->glyph->advance.x / 64.0f;
}

float font_face_get_ascender(font_face *face) {
  if (font_face_is_scalable(face))
    return (face->face->ascender / (float)face->face->units_per_EM);

  return face->face->size->metrics.ascender / 64.0f;
}

float font_face_underline_thickness(font_face *face) {
  return (face->face->underline_thickness / (float)face->face->units_per_EM);
}

/* FT_Load_Char */
int font_face_load_char(RenFont *font, font_face *face, unsigned long code)
{
  unsigned int load_option = font_set_load_options(font);

  return FT_Load_Char(face->face, code, (load_option | FT_LOAD_BITMAP_METRICS_ONLY | FT_LOAD_NO_HINTING) & ~FT_LOAD_FORCE_AUTOHINT);
}

/* FT_IS_SCALABLE */
int font_face_is_scalable(font_face *face) {
  return FT_IS_SCALABLE(face->face);
}

/* FT_Set_Pixel_Sizes */
int font_face_set_pixel_size(font_face *face, unsigned int width, unsigned int height) {
  return FT_Set_Pixel_Sizes(face->face, width, height);
}

/* FT_Get_Char_Index */
unsigned int font_get_char_index(font_face *face, unsigned long charcode) {
  return FT_Get_Char_Index(face->face, charcode);
}

FT_GlyphSlot font_face_get_glyph(font_face *face) {
  return face->face->glyph;
}

/* FT_Load_Glyph */
int font_load_glyph(RenFont *font, font_face *face, unsigned int glyph_index)
{
  unsigned int load_option = font_set_load_options(font);

  return FT_Load_Glyph(face->face, glyph_index, (load_option | FT_LOAD_BITMAP_METRICS_ONLY | FT_LOAD_NO_HINTING) & ~FT_LOAD_FORCE_AUTOHINT);
}

/* FT_Render_Glyph */
int font_render_glyph(RenFont *font, FT_GlyphSlot slot)
{
  unsigned int render_option = font_set_render_options(font);

  return FT_Render_Glyph(slot, render_option);
}