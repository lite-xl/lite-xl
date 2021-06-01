#include <stddef.h>
#include <stdlib.h>

#include "fontdesc.h"
#include "renderer.h"


int font_desc_alloc_size(const char *filename) {
  return offsetof(FontDesc, filename) + strlen(filename) + 1;
}

void font_desc_init(FontDesc *font_desc, const char *filename, float size, unsigned int font_options) {
  memcpy(font_desc->filename, filename, strlen(filename) + 1);
  font_desc->size = size;
  font_desc->options = font_options;
  font_desc->tab_size = 4;
  font_desc->cache_length = 0;
  font_desc->cache_last_index = 0; /* Normally no need to initialize. */
}

void font_desc_clear(FontDesc *font_desc) {
  for (int i = 0; i < font_desc->cache_length; i++) {
    ren_free_font(font_desc->cache[i].font);
  }
  font_desc->cache_length = 0;
  font_desc->cache_last_index = 0;
}

void font_desc_set_tab_size(FontDesc *font_desc, int tab_size) {
  font_desc->tab_size = tab_size;
  for (int i = 0; i < font_desc->cache_length; i++) {
    ren_set_font_tab_size(font_desc->cache[i].font, tab_size);
  }
}

int font_desc_get_tab_size(FontDesc *font_desc) {
  return font_desc->tab_size;
}

static void load_scaled_font(FontDesc *font_desc, int index, int scale) {
  RenFont *font = ren_load_font(font_desc->filename, scale * font_desc->size, font_desc->options);
  if (!font) {
    /* The font was able to load when initially loaded using renderer.load.font.
       If now is no longer available we just abort the application. */
    fprintf(stderr, "Fatal error: unable to load font %s. Application will abort.\n",
      font_desc->filename);
    exit(1);
  }
  font_desc->cache[index].font = font;
  font_desc->cache[index].scale = scale;
}

RenFont *font_desc_get_font_at_scale(FontDesc *font_desc, int scale) {
  int index = -1;
  for (int i = 0; i < font_desc->cache_length; i++) {
    if (font_desc->cache[i].scale == scale) {
      index = i;
      break;
    }
  }
  if (index < 0) {
    index = font_desc->cache_length;
    if (index < FONT_CACHE_ARRAY_MAX) {
      load_scaled_font(font_desc, index, scale);
      font_desc->cache_length = index + 1;
    } else {
      // FIXME: should not print into the stderr or stdout.
      fprintf(stderr, "Warning: max array of font scale reached.\n");
      index = (font_desc->cache_last_index == 0 ? 1 : 0);
      ren_free_font(font_desc->cache[index].font);
      load_scaled_font(font_desc, index, scale);
    }
  }
  font_desc->cache_last_index = index;
  return font_desc->cache[index].font;
}

