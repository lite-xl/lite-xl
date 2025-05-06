#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdlib.h>
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
#include "renwindow.h"

/* a cache over the software renderer -- all drawing operations are stored as
** commands when issued. At the end of the frame we write the commands to a grid
** of hash values, take the cells that have changed since the previous frame,
** merge them into dirty rectangles and redraw only those regions */

#define CELLS_X 80
#define CELLS_Y 50
#define CELL_SIZE 96
#define CMD_BUF_RESIZE_RATE 1.2
#define CMD_BUF_INIT_SIZE (1024 * 512)
#define COMMAND_BARE_SIZE offsetof(Command, command)

enum CommandType { SET_CLIP, DRAW_TEXT, DRAW_RECT };

typedef struct {
  enum CommandType type;
  uint32_t size;
  /* Commands *must* always begin with a RenRect
  ** This is done to ensure alignment */
  RenRect command[];
} Command;

typedef struct {
  RenRect rect;
} SetClipCommand;

typedef struct {
  RenRect rect;
  RenColor color;
  RenFont *fonts[FONT_FALLBACK_MAX];
  float text_x;
  size_t len;
  int8_t tab_size;
  RenTab tab;
  char text[];
} DrawTextCommand;

typedef struct {
  RenRect rect;
  RenColor color;
} DrawRectCommand;

static unsigned cells_buf1[CELLS_X * CELLS_Y];
static unsigned cells_buf2[CELLS_X * CELLS_Y];
static unsigned *cells_prev = cells_buf1;
static unsigned *cells = cells_buf2;
static RenRect rect_buf[CELLS_X * CELLS_Y / 2];
static bool resize_issue;
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

static bool expand_command_buffer(RenWindow *window_renderer) {
  size_t new_size = window_renderer->command_buf_size * CMD_BUF_RESIZE_RATE;
  if (new_size == 0) {
    new_size = CMD_BUF_INIT_SIZE;
  }
  uint8_t *new_command_buf = SDL_realloc(window_renderer->command_buf, new_size);
  if (!new_command_buf) {
    return false;
  }
  window_renderer->command_buf_size = new_size;
  window_renderer->command_buf = new_command_buf;
  return true;
}

static void* push_command(RenWindow *window_renderer, enum CommandType type, int size) {
  if (!window_renderer || resize_issue) {
    // Don't push new commands as we had problems resizing the command buffer.
    // Or, we don't have an active buffer.
    // Let's wait for the next frame.
    return NULL;
  }
  size_t alignment = alignof(max_align_t) - 1;
  size += COMMAND_BARE_SIZE;
  size = (size + alignment) & ~alignment;
  int n = window_renderer->command_buf_idx + size;
  while (n > window_renderer->command_buf_size) {
    if (!expand_command_buffer(window_renderer)) {
      fprintf(stderr, "Warning: (" __FILE__ "): unable to resize command buffer (%zu)\n",
              (size_t)(window_renderer->command_buf_size * CMD_BUF_RESIZE_RATE));
      resize_issue = true;
      return NULL;
    }
  }
  Command *cmd = (Command*) (window_renderer->command_buf + window_renderer->command_buf_idx);
  window_renderer->command_buf_idx = n;
  memset(cmd, 0, size);
  cmd->type = type;
  cmd->size = size;
  return cmd->command;
}


static bool next_command(RenWindow *window_renderer, Command **prev) {
  if (*prev == NULL) {
    *prev = (Command*) window_renderer->command_buf;
  } else {
    *prev = (Command*) (((char*) *prev) + (*prev)->size);
  }
  return *prev != ((Command*) (window_renderer->command_buf + window_renderer->command_buf_idx));
}


void rencache_show_debug(bool enable) {
  show_debug = enable;
}


void rencache_set_clip_rect(RenWindow *window_renderer, RenRect rect) {
  SetClipCommand *cmd = push_command(window_renderer, SET_CLIP, sizeof(SetClipCommand));
  if (cmd) {
    cmd->rect = intersect_rects(rect, screen_rect);
    last_clip_rect = cmd->rect;
  }
}


void rencache_draw_rect(RenWindow *window_renderer, RenRect rect, RenColor color) {
  if (rect.width == 0 || rect.height == 0 || !rects_overlap(last_clip_rect, rect)) {
    return;
  }
  DrawRectCommand *cmd = push_command(window_renderer, DRAW_RECT, sizeof(DrawRectCommand));
  if (cmd) {
    cmd->rect = rect;
    cmd->color = color;
  }
}

double rencache_draw_text(RenWindow *window_renderer, RenFont **fonts, const char *text, size_t len, double x, int y, RenColor color, RenTab tab)
{
  int x_offset;
  double width = ren_font_group_get_width(fonts, text, len, tab, &x_offset);
  RenRect rect = { x + x_offset, y, (int)(width - x_offset), ren_font_group_get_height(fonts) };
  if (rects_overlap(last_clip_rect, rect)) {
    int sz = len + 1;
    DrawTextCommand *cmd = push_command(window_renderer, DRAW_TEXT, sizeof(DrawTextCommand) + sz);
    if (cmd) {
      memcpy(cmd->text, text, sz);
      cmd->color = color;
      memcpy(cmd->fonts, fonts, sizeof(RenFont*)*FONT_FALLBACK_MAX);
      cmd->rect = rect;
      cmd->text_x = x;
      cmd->len = len;
      cmd->tab_size = ren_font_group_get_tab_size(fonts);
      cmd->tab = tab;
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
  while (next_command(window_renderer, &cmd)) {
    /* cmd->command[0] should always be the Command rect */
    if (cmd->type == SET_CLIP) { cr = cmd->command[0]; }
    RenRect r = intersect_rects(cmd->command[0], cr);
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

  RenSurface rs = renwin_get_surface(window_renderer);
  /* redraw updated regions */
  for (int i = 0; i < rect_count; i++) {
    /* draw */
    RenRect r = rect_buf[i];
    ren_set_clip_rect(window_renderer, r);

    cmd = NULL;
    while (next_command(window_renderer, &cmd)) {
      SetClipCommand *ccmd = (SetClipCommand*)&cmd->command;
      DrawRectCommand *rcmd = (DrawRectCommand*)&cmd->command;
      DrawTextCommand *tcmd = (DrawTextCommand*)&cmd->command;
      switch (cmd->type) {
        case SET_CLIP:
          ren_set_clip_rect(window_renderer, intersect_rects(ccmd->rect, r));
          break;
        case DRAW_RECT:
          ren_draw_rect(&rs, rcmd->rect, rcmd->color);
          break;
        case DRAW_TEXT:
          ren_font_group_set_tab_size(tcmd->fonts, tcmd->tab_size);
          ren_draw_text(&rs, tcmd->fonts, tcmd->text, tcmd->len, tcmd->text_x, tcmd->rect.y, tcmd->color, tcmd->tab);
          break;
      }
    }

    if (show_debug) {
      RenColor color = { rand(), rand(), rand(), 50 };
      ren_draw_rect(&rs, r, color);
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
  window_renderer->command_buf_idx = 0;
}

