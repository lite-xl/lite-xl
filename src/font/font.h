#ifndef FONT_H
#define FONT_H

#include "renderer.h"

typedef struct font_face font_face;

int font_init(void);
void font_done(void);

int font_face_open(const char* path, font_face **face);
void font_face_close(void *face);
const char* font_face_get_family_name(font_face *face);
float font_face_get_height(font_face *face);
float font_face_get_advanced_width(font_face *face);
float font_face_get_ascender(font_face *face);
float font_face_underline_thickness(font_face *face);
int font_face_load_char(RenFont *font, font_face *face, unsigned long code);
int font_face_is_scalable(font_face *face);
int font_face_set_pixel_size(font_face *face, unsigned int width, unsigned int height);
unsigned int font_get_char_index(font_face *face, unsigned long charcode);
void *font_face_get_glyph(font_face *face);

int font_load_glyph(RenFont *font, font_face *face, unsigned int glyph_index);
int font_render_glyph(RenFont *font, void* slot);

#endif