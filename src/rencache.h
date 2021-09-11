#ifndef RENCACHE_H
#define RENCACHE_H

#include <stdbool.h>
#include <lua.h>
#include "renderer.h"

void rencache_show_debug(bool enable);
void rencache_set_clip_rect(RenRect rect);
void rencache_draw_rect(RenRect rect, RenColor color);
int  rencache_draw_text(lua_State *L, RenFont *font, 
  const char *text, int x, int y, RenColor color);
void rencache_invalidate(void);
void rencache_begin_frame(lua_State *L);
void rencache_end_frame(lua_State *L);

#endif
