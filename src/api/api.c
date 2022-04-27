#include "api.h"

int luaopen_system(lua_State *L);
int luaopen_renderer(lua_State *L);
int luaopen_regex(lua_State *L);
int luaopen_process(lua_State *L);
int luaopen_dirmonitor(lua_State* L);
int luaopen_utf8(lua_State* L);

static const luaL_Reg libs[] = {
  { "system",     luaopen_system     },
  { "renderer",   luaopen_renderer   },
  { "regex",      luaopen_regex      },
  { "process",    luaopen_process    },
  { "dirmonitor", luaopen_dirmonitor },
  { "utf8",       luaopen_utf8       },
  { NULL, NULL }
};


void api_load_libs(lua_State *L) {
  for (int i = 0; libs[i].name; i++)
    luaL_requiref(L, libs[i].name, libs[i].func, 1);
}

#ifdef _WIN32
int api_windows_dark_theme_activated()
 {
     DWORD   type;
     DWORD   value;
     DWORD   count = 4;
     LSTATUS st = RegGetValue(
         HKEY_CURRENT_USER,
         TEXT("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
         TEXT("AppsUseLightTheme"),
         RRF_RT_REG_DWORD,
         &type,
         &value,
         &count );
     if ( st == ERROR_SUCCESS && type == REG_DWORD )
         return value == 0? 1 : 0;
     return 0;
 }
 #endif
