#include <SDL.h>
#include <stdbool.h>
#include <ctype.h>
#include <dirent.h>
#include <unistd.h>
#include <errno.h>
#include <sys/stat.h>
#include "api.h"
#include "dirmonitor.h"
#include "rencache.h"
#ifdef _WIN32
  #include <direct.h>
  #include <windows.h>
  #include <fileapi.h>
#elif __linux__
  #include <sys/vfs.h>
#endif

extern SDL_Window *window;


static const char* button_name(int button) {
  switch (button) {
    case 1  : return "left";
    case 2  : return "middle";
    case 3  : return "right";
    default : return "?";
  }
}


static void str_tolower(char *p) {
  while (*p) {
    *p = tolower(*p);
    p++;
  }
}

struct HitTestInfo {
  int title_height;
  int controls_width;
  int resize_border;
};
typedef struct HitTestInfo HitTestInfo;

static HitTestInfo window_hit_info[1] = {{0, 0}};

#define RESIZE_FROM_TOP 0
#define RESIZE_FROM_RIGHT 0

static SDL_HitTestResult SDLCALL hit_test(SDL_Window *window, const SDL_Point *pt, void *data) {
  const HitTestInfo *hit_info = (HitTestInfo *) data;
  const int resize_border = hit_info->resize_border;
  const int controls_width = hit_info->controls_width;
  int w, h;

  SDL_GetWindowSize(window, &w, &h);

  if (pt->y < hit_info->title_height &&
    #if RESIZE_FROM_TOP
    pt->y > hit_info->resize_border &&
    #endif
    pt->x > resize_border && pt->x < w - controls_width) {
    return SDL_HITTEST_DRAGGABLE;
  }

  #define REPORT_RESIZE_HIT(name) { \
    return SDL_HITTEST_RESIZE_##name; \
  }

  if (pt->x < resize_border && pt->y < resize_border) {
    REPORT_RESIZE_HIT(TOPLEFT);
  #if RESIZE_FROM_TOP
  } else if (pt->x > resize_border && pt->x < w - controls_width && pt->y < resize_border) {
    REPORT_RESIZE_HIT(TOP);
  #endif
  } else if (pt->x > w - resize_border && pt->y < resize_border) {
    REPORT_RESIZE_HIT(TOPRIGHT);
  #if RESIZE_FROM_RIGHT
  } else if (pt->x > w - resize_border && pt->y > resize_border && pt->y < h - resize_border) {
    REPORT_RESIZE_HIT(RIGHT);
  #endif
  } else if (pt->x > w - resize_border && pt->y > h - resize_border) {
    REPORT_RESIZE_HIT(BOTTOMRIGHT);
  } else if (pt->x < w - resize_border && pt->x > resize_border && pt->y > h - resize_border) {
    REPORT_RESIZE_HIT(BOTTOM);
  } else if (pt->x < resize_border && pt->y > h - resize_border) {
    REPORT_RESIZE_HIT(BOTTOMLEFT);
  } else if (pt->x < resize_border && pt->y < h - resize_border && pt->y > resize_border) {
    REPORT_RESIZE_HIT(LEFT);
  }

  return SDL_HITTEST_NORMAL;
}

static const char *numpad[] = { "end", "down", "pagedown", "left", "", "right", "home", "up", "pageup", "ins", "delete" };

static const char *get_key_name(const SDL_Event *e, char *buf) {
  SDL_Scancode scancode = e->key.keysym.scancode;
  /* Is the scancode from the keypad and the number-lock off?
  ** We assume that SDL_SCANCODE_KP_1 up to SDL_SCANCODE_KP_9 and SDL_SCANCODE_KP_0
  ** and SDL_SCANCODE_KP_PERIOD are declared in SDL2 in that order. */
  if (scancode >= SDL_SCANCODE_KP_1 && scancode <= SDL_SCANCODE_KP_1 + 10 &&
    !(e->key.keysym.mod & KMOD_NUM)) {
    return numpad[scancode - SDL_SCANCODE_KP_1];
  } else {
    strcpy(buf, SDL_GetKeyName(e->key.keysym.sym));
    str_tolower(buf);
    return buf;
  }
}

static int f_poll_event(lua_State *L) {
  char buf[16];
  int mx, my, wx, wy;
  SDL_Event e;

top:
  if ( !SDL_PollEvent(&e) ) {
    return 0;
  }

  switch (e.type) {
    case SDL_QUIT:
      lua_pushstring(L, "quit");
      return 1;

    case SDL_WINDOWEVENT:
      if (e.window.event == SDL_WINDOWEVENT_RESIZED) {
        ren_resize_window();
        lua_pushstring(L, "resized");
        /* The size below will be in points. */
        lua_pushnumber(L, e.window.data1);
        lua_pushnumber(L, e.window.data2);
        return 3;
      } else if (e.window.event == SDL_WINDOWEVENT_EXPOSED) {
        rencache_invalidate();
        lua_pushstring(L, "exposed");
        return 1;
      } else if (e.window.event == SDL_WINDOWEVENT_MINIMIZED) {
        lua_pushstring(L, "minimized");
        return 1;
      } else if (e.window.event == SDL_WINDOWEVENT_MAXIMIZED) {
        lua_pushstring(L, "maximized");
        return 1;
      } else if (e.window.event == SDL_WINDOWEVENT_RESTORED) {
        lua_pushstring(L, "restored");
        return 1;
      }
      if (e.window.event == SDL_WINDOWEVENT_FOCUS_LOST) {
        lua_pushstring(L, "focuslost");
        return 1;
      }
      /* on some systems, when alt-tabbing to the window SDL will queue up
      ** several KEYDOWN events for the `tab` key; we flush all keydown
      ** events on focus so these are discarded */
      if (e.window.event == SDL_WINDOWEVENT_FOCUS_GAINED) {
        SDL_FlushEvent(SDL_KEYDOWN);
      }
      goto top;

    case SDL_DROPFILE:
      SDL_GetGlobalMouseState(&mx, &my);
      SDL_GetWindowPosition(window, &wx, &wy);
      lua_pushstring(L, "filedropped");
      lua_pushstring(L, e.drop.file);
      lua_pushnumber(L, mx - wx);
      lua_pushnumber(L, my - wy);
      SDL_free(e.drop.file);
      return 4;

    case SDL_KEYDOWN:
#ifdef __APPLE__
      /* on macos 11.2.3 with sdl 2.0.14 the keyup handler for cmd+w below
      ** was not enough. Maybe the quit event started to be triggered from the
      ** keydown handler? In any case, flushing the quit event here too helped. */
      if ((e.key.keysym.sym == SDLK_w) && (e.key.keysym.mod & KMOD_GUI)) {
        SDL_FlushEvent(SDL_QUIT);
      }
#endif
      lua_pushstring(L, "keypressed");
      lua_pushstring(L, get_key_name(&e, buf));
      return 2;

    case SDL_KEYUP:
#ifdef __APPLE__
      /* on macos command+w will close the current window
      ** we want to flush this event and let the keymapper
      ** handle this key combination.
      ** Thanks to mathewmariani, taken from his lite-macos github repository. */
      if ((e.key.keysym.sym == SDLK_w) && (e.key.keysym.mod & KMOD_GUI)) {
        SDL_FlushEvent(SDL_QUIT);
      }
#endif
      lua_pushstring(L, "keyreleased");
      lua_pushstring(L, get_key_name(&e, buf));
      return 2;

    case SDL_TEXTINPUT:
      lua_pushstring(L, "textinput");
      lua_pushstring(L, e.text.text);
      return 2;

    case SDL_MOUSEBUTTONDOWN:
      if (e.button.button == 1) { SDL_CaptureMouse(1); }
      lua_pushstring(L, "mousepressed");
      lua_pushstring(L, button_name(e.button.button));
      lua_pushnumber(L, e.button.x);
      lua_pushnumber(L, e.button.y);
      lua_pushnumber(L, e.button.clicks);
      return 5;

    case SDL_MOUSEBUTTONUP:
      if (e.button.button == 1) { SDL_CaptureMouse(0); }
      lua_pushstring(L, "mousereleased");
      lua_pushstring(L, button_name(e.button.button));
      lua_pushnumber(L, e.button.x);
      lua_pushnumber(L, e.button.y);
      return 4;

    case SDL_MOUSEMOTION:
      SDL_PumpEvents();
      SDL_Event event_plus;
      while (SDL_PeepEvents(&event_plus, 1, SDL_GETEVENT, SDL_MOUSEMOTION, SDL_MOUSEMOTION) > 0) {
        e.motion.x = event_plus.motion.x;
        e.motion.y = event_plus.motion.y;
        e.motion.xrel += event_plus.motion.xrel;
        e.motion.yrel += event_plus.motion.yrel;
      }
      lua_pushstring(L, "mousemoved");
      lua_pushnumber(L, e.motion.x);
      lua_pushnumber(L, e.motion.y);
      lua_pushnumber(L, e.motion.xrel);
      lua_pushnumber(L, e.motion.yrel);
      return 5;

    case SDL_MOUSEWHEEL:
      lua_pushstring(L, "mousewheel");
      lua_pushnumber(L, e.wheel.y);
      return 2;

    case SDL_USEREVENT:
      lua_pushstring(L, "dirchange");
      lua_pushnumber(L, e.user.code >> 16);
      switch (e.user.code & 0xffff) {
        case DMON_ACTION_DELETE:
          lua_pushstring(L, "delete");
          break;
        case DMON_ACTION_CREATE:
          lua_pushstring(L, "create");
          break;
        case DMON_ACTION_MODIFY:
          lua_pushstring(L, "modify");
          break;
        default:
          return luaL_error(L, "unknown dmon event action: %d", e.user.code & 0xffff);
      }
      lua_pushstring(L, e.user.data1);
      free(e.user.data1);
      return 4;

    default:
      goto top;
  }

  return 0;
}


static int f_wait_event(lua_State *L) {
  int nargs = lua_gettop(L);
  if (nargs >= 1) {
    double n = luaL_checknumber(L, 1);
    lua_pushboolean(L, SDL_WaitEventTimeout(NULL, n * 1000));
  } else {
    lua_pushboolean(L, SDL_WaitEvent(NULL));
  }
  return 1;
}


static SDL_Cursor* cursor_cache[SDL_SYSTEM_CURSOR_HAND + 1];

static const char *cursor_opts[] = {
  "arrow",
  "ibeam",
  "sizeh",
  "sizev",
  "hand",
  NULL
};

static const int cursor_enums[] = {
  SDL_SYSTEM_CURSOR_ARROW,
  SDL_SYSTEM_CURSOR_IBEAM,
  SDL_SYSTEM_CURSOR_SIZEWE,
  SDL_SYSTEM_CURSOR_SIZENS,
  SDL_SYSTEM_CURSOR_HAND
};

static int f_set_cursor(lua_State *L) {
  int opt = luaL_checkoption(L, 1, "arrow", cursor_opts);
  int n = cursor_enums[opt];
  SDL_Cursor *cursor = cursor_cache[n];
  if (!cursor) {
    cursor = SDL_CreateSystemCursor(n);
    cursor_cache[n] = cursor;
  }
  SDL_SetCursor(cursor);
  return 0;
}


static int f_set_window_title(lua_State *L) {
  const char *title = luaL_checkstring(L, 1);
  SDL_SetWindowTitle(window, title);
  return 0;
}


static const char *window_opts[] = { "normal", "minimized", "maximized", "fullscreen", 0 };
enum { WIN_NORMAL, WIN_MINIMIZED, WIN_MAXIMIZED, WIN_FULLSCREEN };

static int f_set_window_mode(lua_State *L) {
  int n = luaL_checkoption(L, 1, "normal", window_opts);
  SDL_SetWindowFullscreen(window,
    n == WIN_FULLSCREEN ? SDL_WINDOW_FULLSCREEN_DESKTOP : 0);
  if (n == WIN_NORMAL) { SDL_RestoreWindow(window); }
  if (n == WIN_MAXIMIZED) { SDL_MaximizeWindow(window); }
  if (n == WIN_MINIMIZED) { SDL_MinimizeWindow(window); }
  return 0;
}


static int f_set_window_bordered(lua_State *L) {
  int bordered = lua_toboolean(L, 1);
  SDL_SetWindowBordered(window, bordered);
  return 0;
}


static int f_set_window_hit_test(lua_State *L) {
  if (lua_gettop(L) == 0) {
    SDL_SetWindowHitTest(window, NULL, NULL);
    return 0;
  }
  window_hit_info->title_height = luaL_checknumber(L, 1);
  window_hit_info->controls_width = luaL_checknumber(L, 2);
  window_hit_info->resize_border = luaL_checknumber(L, 3);
  SDL_SetWindowHitTest(window, hit_test, window_hit_info);
  return 0;
}


static int f_get_window_size(lua_State *L) {
  int x, y, w, h;
  SDL_GetWindowSize(window, &w, &h);
  SDL_GetWindowPosition(window, &x, &y);
  lua_pushnumber(L, w);
  lua_pushnumber(L, h);
  lua_pushnumber(L, x);
  lua_pushnumber(L, y);
  return 4;
}


static int f_set_window_size(lua_State *L) {
  double w = luaL_checknumber(L, 1);
  double h = luaL_checknumber(L, 2);
  double x = luaL_checknumber(L, 3);
  double y = luaL_checknumber(L, 4);
  SDL_SetWindowSize(window, w, h);
  SDL_SetWindowPosition(window, x, y);
  ren_resize_window();
  return 0;
}


static int f_window_has_focus(lua_State *L) {
  unsigned flags = SDL_GetWindowFlags(window);
  lua_pushboolean(L, flags & SDL_WINDOW_INPUT_FOCUS);
  return 1;
}


static int f_get_window_mode(lua_State *L) {
  unsigned flags = SDL_GetWindowFlags(window);
  if (flags & SDL_WINDOW_FULLSCREEN_DESKTOP) {
    lua_pushstring(L, "fullscreen");
  } else if (flags & SDL_WINDOW_MINIMIZED) {
    lua_pushstring(L, "minimized");
  } else if (flags & SDL_WINDOW_MAXIMIZED) {
    lua_pushstring(L, "maximized");
  } else {
    lua_pushstring(L, "normal");
  }
  return 1;
}


static int f_show_fatal_error(lua_State *L) {
  const char *title = luaL_checkstring(L, 1);
  const char *msg = luaL_checkstring(L, 2);

#ifdef _WIN32
  MessageBox(0, msg, title, MB_OK | MB_ICONERROR);

#else
  SDL_MessageBoxButtonData buttons[] = {
    { SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT, 0, "Ok" },
  };
  SDL_MessageBoxData data = {
    .title = title,
    .message = msg,
    .numbuttons = 1,
    .buttons = buttons,
  };
  int buttonid;
  SDL_ShowMessageBox(&data, &buttonid);
#endif
  return 0;
}


// removes an empty directory
static int f_rmdir(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);

#ifdef _WIN32
  int deleted = RemoveDirectoryA(path);
  if(deleted > 0) {
    lua_pushboolean(L, 1);
  } else {
    DWORD error_code = GetLastError();
    LPVOID message;

    FormatMessage(
      FORMAT_MESSAGE_ALLOCATE_BUFFER |
      FORMAT_MESSAGE_FROM_SYSTEM |
      FORMAT_MESSAGE_IGNORE_INSERTS,
      NULL,
      error_code,
      MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      (LPTSTR) &message,
      0,
      NULL
    );

    lua_pushboolean(L, 0);
    lua_pushlstring(L, (LPCTSTR)message, lstrlen((LPCTSTR)message));
    LocalFree(message);

    return 2;
  }
#else
  int deleted = remove(path);
  if(deleted < 0) {
    lua_pushboolean(L, 0);
    lua_pushstring(L, strerror(errno));

    return 2;
  } else {
    lua_pushboolean(L, 1);
  }
#endif

  return 1;
}


static int f_chdir(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  int err = chdir(path);
  if (err) { luaL_error(L, "chdir() failed"); }
  return 0;
}


static int f_list_dir(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);

  DIR *dir = opendir(path);
  if (!dir) {
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
  }

  lua_newtable(L);
  int i = 1;
  struct dirent *entry;
  while ( (entry = readdir(dir)) ) {
    if (strcmp(entry->d_name, "." ) == 0) { continue; }
    if (strcmp(entry->d_name, "..") == 0) { continue; }
    lua_pushstring(L, entry->d_name);
    lua_rawseti(L, -2, i);
    i++;
  }

  closedir(dir);
  return 1;
}


#ifdef _WIN32
  #include <windows.h>
  #define realpath(x, y) _fullpath(y, x, MAX_PATH)
#endif

static int f_absolute_path(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  char *res = realpath(path, NULL);
  if (!res) { return 0; }
  lua_pushstring(L, res);
  free(res);
  return 1;
}


static int f_get_file_info(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);

  struct stat s;
  int err = stat(path, &s);
  if (err < 0) {
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
  }

  lua_newtable(L);
  lua_pushnumber(L, s.st_mtime);
  lua_setfield(L, -2, "modified");

  lua_pushnumber(L, s.st_size);
  lua_setfield(L, -2, "size");

  if (S_ISREG(s.st_mode)) {
    lua_pushstring(L, "file");
  } else if (S_ISDIR(s.st_mode)) {
    lua_pushstring(L, "dir");
  } else {
    lua_pushnil(L);
  }
  lua_setfield(L, -2, "type");

#if __linux__
  if (S_ISDIR(s.st_mode)) {
    if (lstat(path, &s) == 0) {
      lua_pushboolean(L, S_ISLNK(s.st_mode));
      lua_setfield(L, -2, "symlink");
    }
  }
#endif
  return 1;
}

#if __linux__
// https://man7.org/linux/man-pages/man2/statfs.2.html

struct f_type_names {
  uint32_t magic;
  const char *name;
};

static struct f_type_names fs_names[] = {
  { 0xef53,     "ext2/ext3" },
  { 0x6969,     "nfs"       },
  { 0x65735546, "fuse"      },
  { 0x517b,     "smb"       },
  { 0xfe534d42, "smb2"      },
  { 0x52654973, "reiserfs"  },
  { 0x01021994, "tmpfs"     },
  { 0x858458f6, "ramfs"     },
  { 0x5346544e, "ntfs"      },
  { 0x0,        NULL        },
};

static int f_get_fs_type(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  struct statfs buf;
  int status = statfs(path, &buf);
  if (status != 0) {
    return luaL_error(L, "error calling statfs on %s", path);
  }
  for (int i = 0; fs_names[i].magic; i++) {
    if (fs_names[i].magic == buf.f_type) {
      lua_pushstring(L, fs_names[i].name);
      return 1;
    }
  }
  lua_pushstring(L, "unknown");
  return 1;
}
#else
static int f_return_unknown(lua_State *L) {
  lua_pushstring(L, "unknown");
  return 1;
}
#endif


static int f_mkdir(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);

#ifdef _WIN32
  int err = _mkdir(path);
#else
  int err = mkdir(path, S_IRUSR|S_IWUSR|S_IXUSR|S_IRGRP|S_IXGRP|S_IROTH|S_IXOTH);
#endif
  if (err < 0) {
    lua_pushboolean(L, 0);
    lua_pushstring(L, strerror(errno));
    return 2;
  }

  lua_pushboolean(L, 1);
  return 1;
}


static int f_get_clipboard(lua_State *L) {
  char *text = SDL_GetClipboardText();
  if (!text) { return 0; }
  lua_pushstring(L, text);
  SDL_free(text);
  return 1;
}


static int f_set_clipboard(lua_State *L) {
  const char *text = luaL_checkstring(L, 1);
  SDL_SetClipboardText(text);
  return 0;
}


static int f_get_time(lua_State *L) {
  double n = SDL_GetPerformanceCounter() / (double) SDL_GetPerformanceFrequency();
  lua_pushnumber(L, n);
  return 1;
}


static int f_sleep(lua_State *L) {
  double n = luaL_checknumber(L, 1);
  SDL_Delay(n * 1000);
  return 0;
}


static int f_exec(lua_State *L) {
  size_t len;
  const char *cmd = luaL_checklstring(L, 1, &len);
  char *buf = malloc(len + 32);
  if (!buf) { luaL_error(L, "buffer allocation failed"); }
#if _WIN32
  sprintf(buf, "cmd /c \"%s\"", cmd);
  WinExec(buf, SW_HIDE);
#else
  sprintf(buf, "%s &", cmd);
  int res = system(buf);
  (void) res;
#endif
  free(buf);
  return 0;
}


static int f_fuzzy_match(lua_State *L) {
  size_t strLen, ptnLen;
  const char *str = luaL_checklstring(L, 1, &strLen);
  const char *ptn = luaL_checklstring(L, 2, &ptnLen);
  bool files = false;
  if (lua_gettop(L) > 2 && lua_isboolean(L,3))
    files = lua_toboolean(L, 3);

  int score = 0;
  int run = 0;

  // Match things *backwards*. This allows for better matching on filenames than the above
  // function. For example, in the lite project, opening "renderer" has lib/font_render/build.sh
  // as the first result, rather than src/renderer.c. Clearly that's wrong.
  if (files) {
    const char* strEnd = str + strLen - 1;
    const char* ptnEnd = ptn + ptnLen - 1;
    while (strEnd >= str && ptnEnd >= ptn) {
      while (*strEnd == ' ') { strEnd--; }
      while (*ptnEnd == ' ') { ptnEnd--; }
      if (tolower(*strEnd) == tolower(*ptnEnd)) {
        score += run * 10 - (*strEnd != *ptnEnd);
        run++;
        ptnEnd--;
      } else {
        score -= 10;
        run = 0;
      }
      strEnd--;
    }
    if (ptnEnd >= ptn) { return 0; }
  } else {
    while (*str && *ptn) {
      while (*str == ' ') { str++; }
      while (*ptn == ' ') { ptn++; }
      if (tolower(*str) == tolower(*ptn)) {
        score += run * 10 - (*str != *ptn);
        run++;
        ptn++;
      } else {
        score -= 10;
        run = 0;
      }
      str++;
    }
    if (*ptn) { return 0; }
  }

  lua_pushnumber(L, score - (int)strLen);
  return 1;
}

static int f_set_window_opacity(lua_State *L) {
  double n = luaL_checknumber(L, 1);
  int r = SDL_SetWindowOpacity(window, n);
  lua_pushboolean(L, r > -1);
  return 1;
}

static int f_watch_dir(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  /* On linux we watch non-recursively and we add/remove each sub-directory explicitly
   * using the function system.watch_dir_add/rm. On other systems we watch recursively
   * and system.watch_dir_add/rm are dummy functions that always returns true. */
#if __linux__
  const uint32_t dmon_flags = DMON_WATCHFLAGS_FOLLOW_SYMLINKS;
#elif __APPLE__
  const uint32_t dmon_flags = DMON_WATCHFLAGS_FOLLOW_SYMLINKS | DMON_WATCHFLAGS_RECURSIVE;
#else
  const uint32_t dmon_flags = DMON_WATCHFLAGS_RECURSIVE;
#endif
  dmon_error error;
  dmon_watch_id watch_id = dmon_watch(path, dirmonitor_watch_callback, dmon_flags, NULL, &error);
  if (watch_id.id == 0) {
    lua_pushnil(L);
    lua_pushstring(L, dmon_error_str(error));
    return 2;
  }
  lua_pushnumber(L, watch_id.id);
  return 1;
}

static int f_unwatch_dir(lua_State *L) {
  dmon_watch_id watch_id;
  watch_id.id = luaL_checkinteger(L, 1);
  dmon_unwatch(watch_id);
  return 0;
}

#if __linux__
static int f_watch_dir_add(lua_State *L) {
  dmon_watch_id watch_id;
  watch_id.id = luaL_checkinteger(L, 1);
  const char *subdir = luaL_checkstring(L, 2);
  dmon_error error_code;
  int success = dmon_watch_add(watch_id, subdir, &error_code);
  if (!success) {
    lua_pushboolean(L, 0);
    lua_pushstring(L, dmon_error_str(error_code));
    return 2;
  }
  lua_pushboolean(L, 1);
  return 1;
}

static int f_watch_dir_rm(lua_State *L) {
  dmon_watch_id watch_id;
  watch_id.id = luaL_checkinteger(L, 1);
  const char *subdir = luaL_checkstring(L, 2);
  lua_pushboolean(L, dmon_watch_rm(watch_id, subdir));
  return 1;
}
#else
static int f_return_true(lua_State *L) {
  lua_pushboolean(L, 1);
  return 1;
}
#endif

#ifdef _WIN32
#define PATHSEP '\\'
#else
#define PATHSEP '/'
#endif

/* Special purpose filepath compare function. Corresponds to the
   order used in the TreeView view of the project's files. Returns true iff
   path1 < path2 in the TreeView order. */
static int f_path_compare(lua_State *L) {
  const char *path1 = luaL_checkstring(L, 1);
  const char *type1_s = luaL_checkstring(L, 2);
  const char *path2 = luaL_checkstring(L, 3);
  const char *type2_s = luaL_checkstring(L, 4);
  const int len1 = strlen(path1), len2 = strlen(path2);
  int type1 = strcmp(type1_s, "dir") != 0;
  int type2 = strcmp(type2_s, "dir") != 0;
  /* Find the index of the common part of the path. */
  int offset = 0, i;
  for (i = 0; i < len1 && i < len2; i++) {
    if (path1[i] != path2[i]) break;
    if (path1[i] == PATHSEP) {
      offset = i + 1;
    }
  }
  /* If a path separator is present in the name after the common part we consider
     the entry like a directory. */
  if (strchr(path1 + offset, PATHSEP)) {
    type1 = 0;
  }
  if (strchr(path2 + offset, PATHSEP)) {
    type2 = 0;
  }
  /* If types are different "dir" types comes before "file" types. */
  if (type1 != type2) {
    lua_pushboolean(L, type1 < type2);
    return 1;
  }
  /* If types are the same compare the files' path alphabetically. */
  int cfr = 0;
  int len_min = (len1 < len2 ? len1 : len2);
  for (int j = offset; j <= len_min; j++) {
    if (path1[j] == path2[j]) continue;
    if (path1[j] == 0 || path2[j] == 0) {
      cfr = (path1[j] == 0);
    } else if (path1[j] == PATHSEP || path2[j] == PATHSEP) {
      /* For comparison we treat PATHSEP as if it was the string terminator. */
      cfr = (path1[j] == PATHSEP);
    } else {
      cfr = (path1[j] < path2[j]);
    }
    break;
  }
  lua_pushboolean(L, cfr);
  return 1;
}


static const luaL_Reg lib[] = {
  { "poll_event",          f_poll_event          },
  { "wait_event",          f_wait_event          },
  { "set_cursor",          f_set_cursor          },
  { "set_window_title",    f_set_window_title    },
  { "set_window_mode",     f_set_window_mode     },
  { "get_window_mode",     f_get_window_mode     },
  { "set_window_bordered", f_set_window_bordered },
  { "set_window_hit_test", f_set_window_hit_test },
  { "get_window_size",     f_get_window_size     },
  { "set_window_size",     f_set_window_size     },
  { "window_has_focus",    f_window_has_focus    },
  { "show_fatal_error",    f_show_fatal_error    },
  { "rmdir",               f_rmdir               },
  { "chdir",               f_chdir               },
  { "mkdir",               f_mkdir               },
  { "list_dir",            f_list_dir            },
  { "absolute_path",       f_absolute_path       },
  { "get_file_info",       f_get_file_info       },
  { "get_clipboard",       f_get_clipboard       },
  { "set_clipboard",       f_set_clipboard       },
  { "get_time",            f_get_time            },
  { "sleep",               f_sleep               },
  { "exec",                f_exec                },
  { "fuzzy_match",         f_fuzzy_match         },
  { "set_window_opacity",  f_set_window_opacity  },
  { "watch_dir",           f_watch_dir           },
  { "unwatch_dir",         f_unwatch_dir         },
  { "path_compare",        f_path_compare        },
#if __linux__
  { "watch_dir_add",       f_watch_dir_add       },
  { "watch_dir_rm",        f_watch_dir_rm        },
  { "get_fs_type",         f_get_fs_type         },
#else
  { "watch_dir_add",       f_return_true         },
  { "watch_dir_rm",        f_return_true         },
  { "get_fs_type",         f_return_unknown      },
#endif
  { NULL, NULL }
};


int luaopen_system(lua_State *L) {
  luaL_newlib(L, lib);
  return 1;
}
