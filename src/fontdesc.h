#ifndef FONT_DESC_H
#define FONT_DESC_H

typedef struct RenFont RenFont;

// FIXME: find a better name for the struct below
struct FontScaled {
  RenFont *font;
  short int scale;
};
typedef struct FontScaled FontScaled;

#define FONT_SCALE_ARRAY_MAX 2

struct FontDesc {
  char *filename;
  float size;
  unsigned int options;
  short int tab_size;
// FIXME: find a better name for the array below
  FontScaled fonts_scale[FONT_SCALE_ARRAY_MAX];
  short int fonts_scale_length;
  short int recent_font_scale_index; /* More recently scale used. */
};
typedef struct FontDesc FontDesc;

int font_desc_get_tab_size(FontDesc *font_desc);
void font_desc_set_tab_size(FontDesc *font_desc, int tab_size);
void font_desc_free(FontDesc *font_desc);
RenFont *font_desc_get_font_at_scale(FontDesc *font_desc, int scale);

#endif

