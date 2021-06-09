#ifndef RENCACHE_H
#define RENCACHE_H

#include <stdbool.h>
#include <lua.h>
#include "renderer.h"

/* a cache over the software renderer -- all drawing operations are stored as
** commands when issued. At the end of the frame we write the commands to a grid
** of hash values, take the cells that have changed since the previous frame,
** merge them into dirty rectangles and redraw only those regions */

#define CELLS_X 80
#define CELLS_Y 50
#define COMMAND_BUF_SIZE (1024 * 512)

struct RenCache {
  unsigned cells_buf1[CELLS_X * CELLS_Y];
  unsigned cells_buf2[CELLS_X * CELLS_Y];
  unsigned *cells_prev;
  unsigned *cells;
  RenRect rect_buf[CELLS_X * CELLS_Y / 2];
  char command_buf[COMMAND_BUF_SIZE];
  int command_buf_idx;
  RenRect screen_rect;
  bool show_debug;
};
typedef struct RenCache RenCache;

void rencache_show_debug(RenCache *rc, bool enable);
void rencache_set_clip_rect(RenCache *rc, RenRect rect);
void rencache_draw_rect(RenCache *rc, RenRect rect, RenColor color);
int  rencache_draw_text(RenCache *rc, lua_State *L, FontDesc *font_desc, int font_index, const char *text, int x, int y, RenColor color,
  bool draw_subpixel, CPReplaceTable *replacements, RenColor replace_color);
void rencache_invalidate(RenCache *rc);
void rencache_begin_frame(RenCache *rc, lua_State *L);
void rencache_end_frame(RenCache *rc, lua_State *L);

#endif
