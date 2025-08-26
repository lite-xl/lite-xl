#include "fonts.h"
#include "../api.h"
#include "lauxlib.h"
#include "lua.h"
#include <math.h>

bool font_retrieve(lua_State *L, RenFont **fonts, int idx) {
  bool is_table;
  memset(fonts, 0, sizeof(RenFont *) * FONT_FALLBACK_MAX);
  if (lua_type(L, idx) != LUA_TTABLE) {
    fonts[0] = *(RenFont **)luaL_checkudata(L, idx, API_TYPE_FONT);
    is_table = false;
  } else {
    is_table = true;
    int len = luaL_len(L, idx);
    len = len > FONT_FALLBACK_MAX ? FONT_FALLBACK_MAX : len;
    for (int i = 0; i < len; i++) {
      lua_rawgeti(L, idx, i + 1);
      fonts[i] = *(RenFont **)luaL_checkudata(L, -1, API_TYPE_FONT);
      lua_pop(L, 1);
    }
  }
#ifdef LITE_USE_SDL_RENDERER
  update_font_scale(ren_get_target_window(), fonts);
#endif
  return is_table;
}

RenTab checktab(lua_State *L, int idx) {
  RenTab tab = {.offset = NAN};
  if (lua_isnoneornil(L, idx)) {
    return tab;
  }
  luaL_checktype(L, idx, LUA_TTABLE);
  if (lua_getfield(L, idx, "tab_offset") == LUA_TNIL) {
    return tab;
  }
  tab.offset = luaL_checknumber(L, -1);
  return tab;
}
