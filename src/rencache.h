#ifndef RENCACHE_H
#define RENCACHE_H

#include <stdbool.h>
#include "renderer.h"

void rencache_show_debug(bool enable);
void rencache_free_font(FontDesc *font_desc);
void rencache_set_clip_rect(RenRect rect);
void rencache_draw_rect(RenRect rect, RenColor color);
int  rencache_draw_text(FontDesc *font_desc, const char *text, int x, int y, RenColor color,
  bool draw_subpixel, CPReplaceTable *replacements, RenColor replace_color);
void rencache_invalidate(void);
void rencache_begin_frame(void);
void rencache_end_frame(void);
void rencache_clear();

#endif
