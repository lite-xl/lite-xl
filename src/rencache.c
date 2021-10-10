#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include <lauxlib.h>
#include "rencache.h"

/* a cache over the software renderer -- all drawing operations are stored as
** commands when issued. At the end of the frame we write the commands to a grid
** of hash values, take the cells that have changed since the previous frame,
** merge them into dirty rectangles and redraw only those regions */

#define CELLS_X 80
#define CELLS_Y 50
#define CELL_SIZE 96
#define COMMAND_BUF_SIZE (1024 * 512)
#define COMMAND_BARE_SIZE offsetof(Command, text)

enum { SET_CLIP, DRAW_TEXT, DRAW_RECT, DRAW_TEXT_SUBPIXEL };

typedef struct {
  int8_t type;
  int8_t tab_size;
  int8_t subpixel_scale;
  int8_t x_subpixel_offset;
  int32_t size;
  RenRect rect;
  RenColor color;
  FontDesc *font_desc;
  CPReplaceTable *replacements;
  RenColor replace_color;
  char text[0];
} Command;

#define FONT_REFS_MAX 12
struct FontRef {
  FontDesc *font_desc;
  int index;
};
typedef struct FontRef FontRef;
FontRef font_refs[FONT_REFS_MAX];
int font_refs_len = 0;


static unsigned cells_buf1[CELLS_X * CELLS_Y];
static unsigned cells_buf2[CELLS_X * CELLS_Y];
static unsigned *cells_prev = cells_buf1;
static unsigned *cells = cells_buf2;
static RenRect rect_buf[CELLS_X * CELLS_Y / 2];
static char command_buf[COMMAND_BUF_SIZE];
static int command_buf_idx;
static RenRect screen_rect;
static bool show_debug;


static inline int min(int a, int b) { return a < b ? a : b; }
static inline int max(int a, int b) { return a > b ? a : b; }

static int font_refs_add(lua_State *L, FontDesc *font_desc, int index) {
  for (int i = 0; i < font_refs_len; i++) {
    if (font_refs[i].font_desc == font_desc) {
      return font_refs[i].index;
    }
  }

  if (font_refs_len >= FONT_REFS_MAX) {
    fprintf(stderr, "Warning: (" __FILE__ "): exhausted font reference buffer\n");
    return LUA_NOREF;
  }

  lua_pushvalue(L, index);
  int ref = luaL_ref(L, LUA_REGISTRYINDEX);

  font_refs[font_refs_len++] = (FontRef) { font_desc, ref };
  return ref;
}


static void font_refs_clear(lua_State *L) {
  for (int i = 0; i < font_refs_len; i++) {
    luaL_unref(L, LUA_REGISTRYINDEX, font_refs[i].index);
  }
  font_refs_len = 0;
}

/* 32bit fnv-1a hash */
#define HASH_INITIAL 2166136261

static void hash(unsigned *h, const void *data, int size) {
  const unsigned char *p = data;
  while (size--) {
    *h = (*h ^ *p++) * 16777619;
  }
}


static inline int cell_idx(int x, int y) {
  return x + y * CELLS_X;
}


static inline bool rects_overlap(RenRect a, RenRect b) {
  return b.x + b.width  >= a.x && b.x <= a.x + a.width
      && b.y + b.height >= a.y && b.y <= a.y + a.height;
}


static RenRect intersect_rects(RenRect a, RenRect b) {
  int x1 = max(a.x, b.x);
  int y1 = max(a.y, b.y);
  int x2 = min(a.x + a.width, b.x + b.width);
  int y2 = min(a.y + a.height, b.y + b.height);
  return (RenRect) { x1, y1, max(0, x2 - x1), max(0, y2 - y1) };
}


static RenRect merge_rects(RenRect a, RenRect b) {
  int x1 = min(a.x, b.x);
  int y1 = min(a.y, b.y);
  int x2 = max(a.x + a.width, b.x + b.width);
  int y2 = max(a.y + a.height, b.y + b.height);
  return (RenRect) { x1, y1, x2 - x1, y2 - y1 };
}


static Command* push_command(int type, int size) {
  Command *cmd = (Command*) (command_buf + command_buf_idx);
  int n = command_buf_idx + size;
  if (n > COMMAND_BUF_SIZE) {
    fprintf(stderr, "Warning: (" __FILE__ "): exhausted command buffer\n");
    return NULL;
  }
  command_buf_idx = n;
  memset(cmd, 0, COMMAND_BARE_SIZE);
  cmd->type = type;
  cmd->size = size;
  return cmd;
}


static bool next_command(Command **prev) {
  if (*prev == NULL) {
    *prev = (Command*) command_buf;
  } else {
    *prev = (Command*) (((char*) *prev) + (*prev)->size);
  }
  return *prev != ((Command*) (command_buf + command_buf_idx));
}


void rencache_show_debug(bool enable) {
  show_debug = enable;
}


void rencache_set_clip_rect(RenRect rect) {
  Command *cmd = push_command(SET_CLIP, COMMAND_BARE_SIZE);
  if (cmd) { cmd->rect = intersect_rects(rect, screen_rect); }
}


void rencache_draw_rect(RenRect rect, RenColor color) {
  if (!rects_overlap(screen_rect, rect) || rect.width == 0 || rect.height == 0) {
    return;
  }
  Command *cmd = push_command(DRAW_RECT, COMMAND_BARE_SIZE);
  if (cmd) {
    cmd->rect = rect;
    cmd->color = color;
  }
}

int rencache_draw_text(lua_State *L, FontDesc *font_desc, int font_index,
  const char *text, int x, int y, RenColor color, bool draw_subpixel,
  CPReplaceTable *replacements, RenColor replace_color)
{
  int subpixel_scale;
  int w_subpixel = ren_get_font_width(font_desc, text, &subpixel_scale);
  RenRect rect;
  rect.x = (draw_subpixel ? ren_font_subpixel_round(x, subpixel_scale, -1) : x);
  rect.y = y;
  rect.width = ren_font_subpixel_round(w_subpixel, subpixel_scale, 0);
  rect.height = ren_get_font_height(font_desc);

  if (rects_overlap(screen_rect, rect) && font_refs_add(L, font_desc, font_index) >= 0) {
    int sz = strlen(text) + 1;
    Command *cmd = push_command(draw_subpixel ? DRAW_TEXT_SUBPIXEL : DRAW_TEXT, COMMAND_BARE_SIZE + sz);
    if (cmd) {
      memcpy(cmd->text, text, sz);
      cmd->color = color;
      cmd->font_desc = font_desc;
      cmd->rect = rect;
      cmd->subpixel_scale = (draw_subpixel ? subpixel_scale : 1);
      cmd->x_subpixel_offset = x - subpixel_scale * rect.x;
      cmd->tab_size = font_desc_get_tab_size(font_desc);
      cmd->replacements = replacements;
      cmd->replace_color = replace_color;
    }
  }

  return x + (draw_subpixel ? w_subpixel : rect.width);
}


void rencache_invalidate(void) {
  memset(cells_prev, 0xff, sizeof(cells_buf1));
}


void rencache_begin_frame(lua_State *L) {
  /* reset all cells if the screen width/height has changed */
  int w, h;
  ren_get_size(&w, &h);
  if (screen_rect.width != w || h != screen_rect.height) {
    screen_rect.width = w;
    screen_rect.height = h;
    rencache_invalidate();
  }
  font_refs_clear(L);
}


static void update_overlapping_cells(RenRect r, unsigned h) {
  int x1 = r.x / CELL_SIZE;
  int y1 = r.y / CELL_SIZE;
  int x2 = (r.x + r.width) / CELL_SIZE;
  int y2 = (r.y + r.height) / CELL_SIZE;

  for (int y = y1; y <= y2; y++) {
    for (int x = x1; x <= x2; x++) {
      int idx = cell_idx(x, y);
      hash(&cells[idx], &h, sizeof(h));
    }
  }
}


static void push_rect(RenRect r, int *count) {
  /* try to merge with existing rectangle */
  for (int i = *count - 1; i >= 0; i--) {
    RenRect *rp = &rect_buf[i];
    if (rects_overlap(*rp, r)) {
      *rp = merge_rects(*rp, r);
      return;
    }
  }
  /* couldn't merge with previous rectangle: push */
  rect_buf[(*count)++] = r;
}


void rencache_end_frame(lua_State *L) {
  /* update cells from commands */
  Command *cmd = NULL;
  RenRect cr = screen_rect;
  while (next_command(&cmd)) {
    if (cmd->type == SET_CLIP) { cr = cmd->rect; }
    RenRect r = intersect_rects(cmd->rect, cr);
    if (r.width == 0 || r.height == 0) { continue; }
    unsigned h = HASH_INITIAL;
    hash(&h, cmd, cmd->size);
    update_overlapping_cells(r, h);
  }

  /* push rects for all cells changed from last frame, reset cells */
  int rect_count = 0;
  int max_x = screen_rect.width / CELL_SIZE + 1;
  int max_y = screen_rect.height / CELL_SIZE + 1;
  for (int y = 0; y < max_y; y++) {
    for (int x = 0; x < max_x; x++) {
      /* compare previous and current cell for change */
      int idx = cell_idx(x, y);
      if (cells[idx] != cells_prev[idx]) {
        push_rect((RenRect) { x, y, 1, 1 }, &rect_count);
      }
      cells_prev[idx] = HASH_INITIAL;
    }
  }

  /* expand rects from cells to pixels */
  for (int i = 0; i < rect_count; i++) {
    RenRect *r = &rect_buf[i];
    r->x *= CELL_SIZE;
    r->y *= CELL_SIZE;
    r->width *= CELL_SIZE;
    r->height *= CELL_SIZE;
    *r = intersect_rects(*r, screen_rect);
  }

  /* redraw updated regions */
  for (int i = 0; i < rect_count; i++) {
    /* draw */
    RenRect r = rect_buf[i];
    ren_set_clip_rect(r);

    cmd = NULL;
    while (next_command(&cmd)) {
      switch (cmd->type) {
        case SET_CLIP:
          ren_set_clip_rect(intersect_rects(cmd->rect, r));
          break;
        case DRAW_RECT:
          ren_draw_rect(cmd->rect, cmd->color);
          break;
        case DRAW_TEXT:
          font_desc_set_tab_size(cmd->font_desc, cmd->tab_size);
          ren_draw_text(cmd->font_desc, cmd->text, cmd->rect.x, cmd->rect.y, cmd->color,
            cmd->replacements, cmd->replace_color);
          break;
        case DRAW_TEXT_SUBPIXEL:
          font_desc_set_tab_size(cmd->font_desc, cmd->tab_size);
          ren_draw_text_subpixel(cmd->font_desc, cmd->text,
            cmd->subpixel_scale * cmd->rect.x + cmd->x_subpixel_offset, cmd->rect.y, cmd->color,
            cmd->replacements, cmd->replace_color);
          break;
      }
    }

    if (show_debug) {
      RenColor color = { rand(), rand(), rand(), 50 };
      ren_draw_rect(r, color);
    }
  }

  /* update dirty rects */
  if (rect_count > 0) {
    ren_update_rects(rect_buf, rect_count);
  }

  /* swap cell buffer and reset */
  unsigned *tmp = cells;
  cells = cells_prev;
  cells_prev = tmp;
  command_buf_idx = 0;
}

