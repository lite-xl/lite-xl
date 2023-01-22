#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <string.h>

#ifdef _MSC_VER
  #ifndef alignof
    #define alignof _Alignof
  #endif
  /* max_align_t is a compiler defined type, but
  ** MSVC doesn't provide it, so we'll have to improvise */
  typedef long double max_align_t;
#else
  #include <stdalign.h>
#endif

#include <lauxlib.h>
#include "rencache.h"

/* a cache over the software renderer -- all drawing operations are stored as
** commands when issued. At the end of the frame we write the commands to a grid
** of hash values, take the cells that have changed since the previous frame,
** merge them into dirty rectangles and redraw only those regions */

#define CELLS_X 80
#define CELLS_Y 50
#define CELL_SIZE 96
#define CMD_BUF_RESIZE_RATE 1.2
#define CMD_BUF_INIT_SIZE (1024 * 512)
#define COMMAND_BARE_SIZE offsetof(Command, text)

enum { SET_CLIP, DRAW_TEXT, DRAW_RECT };

typedef struct {
  int8_t type;
  int8_t tab_size;
  int32_t size;
  RenRect rect;
  RenColor color;
  RenFont *fonts[FONT_FALLBACK_MAX];
  float text_x;
  size_t len;
  char text[];
} Command;

static unsigned cells_buf1[CELLS_X * CELLS_Y];
static unsigned cells_buf2[CELLS_X * CELLS_Y];
static unsigned *cells_prev = cells_buf1;
static unsigned *cells = cells_buf2;
static RenRect rect_buf[CELLS_X * CELLS_Y / 2];
size_t command_buf_size = 0;
uint8_t *command_buf = NULL;
static bool resize_issue;
static int command_buf_idx;
static RenRect screen_rect;
static RenRect last_clip_rect;
static bool show_debug;

static inline int rencache_min(int a, int b) { return a < b ? a : b; }
static inline int rencache_max(int a, int b) { return a > b ? a : b; }


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
  int x1 = rencache_max(a.x, b.x);
  int y1 = rencache_max(a.y, b.y);
  int x2 = rencache_min(a.x + a.width, b.x + b.width);
  int y2 = rencache_min(a.y + a.height, b.y + b.height);
  return (RenRect) { x1, y1, rencache_max(0, x2 - x1), rencache_max(0, y2 - y1) };
}


static RenRect merge_rects(RenRect a, RenRect b) {
  int x1 = rencache_min(a.x, b.x);
  int y1 = rencache_min(a.y, b.y);
  int x2 = rencache_max(a.x + a.width, b.x + b.width);
  int y2 = rencache_max(a.y + a.height, b.y + b.height);
  return (RenRect) { x1, y1, x2 - x1, y2 - y1 };
}

static bool expand_command_buffer() {
  size_t new_size = command_buf_size * CMD_BUF_RESIZE_RATE;
  if (new_size == 0) {
    new_size = CMD_BUF_INIT_SIZE;
  }
  uint8_t *new_command_buf = realloc(command_buf, new_size);
  if (!new_command_buf) {
    return false;
  }
  command_buf_size = new_size;
  command_buf = new_command_buf;
  return true;
}

static Command* push_command(int type, int size) {
  if (resize_issue) {
    // Don't push new commands as we had problems resizing the command buffer.
    // Let's wait for the next frame.
    return NULL;
  }
  size_t alignment = alignof(max_align_t) - 1;
  size = (size + alignment) & ~alignment;
  int n = command_buf_idx + size;
  while (n > command_buf_size) {
    if (!expand_command_buffer()) {
      fprintf(stderr, "Warning: (" __FILE__ "): unable to resize command buffer (%ld)\n",
              (size_t)(command_buf_size * CMD_BUF_RESIZE_RATE));
      resize_issue = true;
      return NULL;
    }
  }
  Command *cmd = (Command*) (command_buf + command_buf_idx);
  command_buf_idx = n;
  memset(cmd, 0, size);
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
  if (cmd) {
    cmd->rect = intersect_rects(rect, screen_rect);
    last_clip_rect = cmd->rect;
  }
}


void rencache_draw_rect(RenRect rect, RenColor color) {
  if (rect.width == 0 || rect.height == 0 || !rects_overlap(last_clip_rect, rect)) {
    return;
  }
  Command *cmd = push_command(DRAW_RECT, COMMAND_BARE_SIZE);
  if (cmd) {
    cmd->rect = rect;
    cmd->color = color;
  }
}

float rencache_draw_text(RenWindow *window_renderer, RenFont **fonts, const char *text, size_t len, float x, int y, RenColor color)
{
  float width = ren_font_group_get_width(window_renderer, fonts, text, len);
  RenRect rect = { x, y, (int)width, ren_font_group_get_height(fonts) };
  if (rects_overlap(last_clip_rect, rect)) {
    int sz = len + 1;
    Command *cmd = push_command(DRAW_TEXT, COMMAND_BARE_SIZE + sz);
    if (cmd) {
      memcpy(cmd->text, text, sz);
      cmd->color = color;
      memcpy(cmd->fonts, fonts, sizeof(RenFont*)*FONT_FALLBACK_MAX);
      cmd->rect = rect;
      cmd->text_x = x;
      cmd->len = len;
      cmd->tab_size = ren_font_group_get_tab_size(fonts);
    }
  }
  return x + width;
}


void rencache_invalidate(void) {
  memset(cells_prev, 0xff, sizeof(cells_buf1));
}


void rencache_begin_frame(RenWindow *window_renderer) {
  /* reset all cells if the screen width/height has changed */
  int w, h;
  resize_issue = false;
  ren_get_size(window_renderer, &w, &h);
  if (screen_rect.width != w || h != screen_rect.height) {
    screen_rect.width = w;
    screen_rect.height = h;
    rencache_invalidate();
  }
  last_clip_rect = screen_rect;
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


void rencache_end_frame(RenWindow *window_renderer) {
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
    ren_set_clip_rect(window_renderer, r);

    cmd = NULL;
    while (next_command(&cmd)) {
      switch (cmd->type) {
        case SET_CLIP:
          ren_set_clip_rect(window_renderer, intersect_rects(cmd->rect, r));
          break;
        case DRAW_RECT:
          ren_draw_rect(window_renderer, cmd->rect, cmd->color);
          break;
        case DRAW_TEXT:
          ren_font_group_set_tab_size(cmd->fonts, cmd->tab_size);
          ren_draw_text(window_renderer, cmd->fonts, cmd->text, cmd->len, cmd->text_x, cmd->rect.y, cmd->color);
          break;
      }
    }

    if (show_debug) {
      RenColor color = { rand(), rand(), rand(), 50 };
      ren_draw_rect(window_renderer, r, color);
    }
  }

  /* update dirty rects */
  if (rect_count > 0) {
    ren_update_rects(window_renderer, rect_buf, rect_count);
  }

  /* swap cell buffer and reset */
  unsigned *tmp = cells;
  cells = cells_prev;
  cells_prev = tmp;
  command_buf_idx = 0;
}

