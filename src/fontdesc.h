#ifndef FONT_DESC_H
#define FONT_DESC_H

typedef struct RenFont RenFont;

struct FontInstance {
  RenFont *font;
  short int scale;
};
typedef struct FontInstance FontInstance;

#define FONT_CACHE_ARRAY_MAX 2

struct FontDesc {
  float size;
  unsigned int options;
  short int tab_size;
  FontInstance cache[FONT_CACHE_ARRAY_MAX];
  short int cache_length;
  short int cache_last_index; /* More recently used instance. */
  char filename[0];
};
typedef struct FontDesc FontDesc;

void font_desc_init(FontDesc *font_desc, const char *filename, float size, unsigned int font_options);
int font_desc_alloc_size(const char *filename);
int font_desc_get_tab_size(FontDesc *font_desc);
void font_desc_set_tab_size(FontDesc *font_desc, int tab_size);
void font_desc_clear(FontDesc *font_desc);
RenFont *font_desc_get_font_at_scale(FontDesc *font_desc, int scale);

#endif

