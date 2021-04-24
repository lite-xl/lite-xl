#include "fontdesc.h"
#include "renderer.h"

void font_desc_set_tab_size(FontDesc *font_desc, int tab_size) {
  font_desc->tab_size = tab_size;
  for (int i = 0; i < font_desc->fonts_scale_length; i++) {
    ren_set_font_tab_size(font_desc->fonts_scale[i].font, tab_size);
  }
}

int font_desc_get_tab_size(FontDesc *font_desc) {
  return font_desc->tab_size;
}

void font_desc_free(FontDesc *font_desc) {
  for (int i = 0; i < font_desc->fonts_scale_length; i++) {
    ren_free_font(font_desc->fonts_scale[i].font);
  }
  font_desc->fonts_scale_length = 0;
  free(font_desc->filename);
}

static void load_scaled_font(FontDesc *font_desc, int index, int scale) {
  RenFont *font = ren_load_font(font_desc->filename, scale * font_desc->size, font_desc->options);
  font_desc->fonts_scale[index].font = font;
  font_desc->fonts_scale[index].scale = scale;
}

RenFont *font_desc_get_font_at_scale(FontDesc *font_desc, int scale) {
  int index = -1;
  for (int i = 0; i < font_desc->fonts_scale_length; i++) {
    if (font_desc->fonts_scale[i].scale == scale) {
      index = i;
      break;
    }
  }
  if (index < 0) {
    index = font_desc->fonts_scale_length;
    if (index < FONT_SCALE_ARRAY_MAX) {
      load_scaled_font(font_desc, index, scale);
      font_desc->fonts_scale_length = index + 1;
    } else {
      // FIXME: should not print into the stderr or stdout.
      fprintf(stderr, "Warning: max array of font scale reached.\n");
      index = (font_desc->recent_font_scale_index == 0 ? 1 : 0);
      ren_free_font(font_desc->fonts_scale[index].font);
      load_scaled_font(font_desc, index, scale);
    }
  }
  font_desc->recent_font_scale_index = index;
  return font_desc->fonts_scale[index].font;
}

