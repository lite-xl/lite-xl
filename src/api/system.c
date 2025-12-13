#include <SDL3/SDL.h>
#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdlib.h>
#include <ctype.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include "api.h"
#include "../rencache.h"
#include "../renwindow.h"
#include "arena_allocator.h"
#include "custom_events.h"
#ifdef _WIN32
  #include <direct.h>
  #include <windows.h>
  #include <fileapi.h>
  #include "../utfconv.h"
  #define fileno _fileno
  #define ftruncate _chsize
#else

#include <dirent.h>
#include <unistd.h>

#ifdef __linux__
  #include <sys/vfs.h>
#endif
#endif

#define dialogfinished_event_name "dialogfinished"

typedef enum {
  DIALOG_OK,
  DIALOG_CANCEL,
  DIALOG_ERROR,
} DialogState;

static const char* button_name(int button) {
  switch (button) {
    case SDL_BUTTON_LEFT   : return "left";
    case SDL_BUTTON_MIDDLE : return "middle";
    case SDL_BUTTON_RIGHT  : return "right";
    case SDL_BUTTON_X1     : return "x";
    case SDL_BUTTON_X2     : return "y";
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

static HitTestInfo window_hit_info[1] = {{0, 0, 0}};

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
  SDL_Scancode scancode = e->key.scancode;
  /* Is the scancode from the keypad and the number-lock off?
  ** We assume that SDL_SCANCODE_KP_1 up to SDL_SCANCODE_KP_9 and SDL_SCANCODE_KP_0
  ** and SDL_SCANCODE_KP_PERIOD are declared in SDL2 in that order. */
  if (scancode >= SDL_SCANCODE_KP_1 && scancode <= SDL_SCANCODE_KP_1 + 10 &&
    !(e->key.mod & SDL_KMOD_NUM)) {
    return numpad[scancode - SDL_SCANCODE_KP_1];
  } else {
    /* We need to correctly handle non-standard layouts such as dvorak.
       Therefore, if a Latin letter(code<128) is pressed in the current layout,
       then we transmit it as it is. But we also need to support shortcuts in
       other languages, so for non-Latin characters(code>128) we pass the
       scancode based name that matches the letter in the QWERTY layout.

       In SDL, the codes of all special buttons such as control, shift, arrows
       and others, are masked with SDLK_SCANCODE_MASK, which moves them outside
       the unicode range (>0x10FFFF). Users can remap these buttons, so we need
       to return the correct name, not scancode based. */
    if ((e->key.key < 128) || (e->key.key & SDLK_SCANCODE_MASK))
      strcpy(buf, SDL_GetKeyName(e->key.key));
    else
      strcpy(buf, SDL_GetScancodeName(scancode));
    str_tolower(buf);
    return buf;
  }
}

#ifdef _WIN32
static char *win32_error(DWORD rc) {
  LPSTR message;
  FormatMessage(
    FORMAT_MESSAGE_ALLOCATE_BUFFER |
    FORMAT_MESSAGE_FROM_SYSTEM |
    FORMAT_MESSAGE_IGNORE_INSERTS,
    NULL,
    rc,
    MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
    (LPTSTR) &message,
    0,
    NULL
  );

  return message;
}

static void push_win32_error(lua_State *L, DWORD rc) {
  LPSTR message = win32_error(rc);
  lua_pushstring(L, message);
  LocalFree(message);
}
#endif

static int f_poll_event(lua_State *L) {
  char buf[16];
  float mx, my;
  int w, h;
  SDL_Event e;
  SDL_Event event_plus;

top:
  if ( !SDL_PollEvent(&e) ) {
    return 0;
  }

  switch (e.type) {
    case SDL_EVENT_QUIT:
      lua_pushstring(L, "quit");
      return 1;

    case SDL_EVENT_WINDOW_RESIZED:
      {
        RenWindow* window_renderer = ren_find_window_from_id(e.window.windowID);
        ren_resize_window(window_renderer);
        lua_pushstring(L, "resized");
        /* The size below will be in points. */
        lua_pushinteger(L, e.window.data1);
        lua_pushinteger(L, e.window.data2);
        return 3;
      }

    case SDL_EVENT_WINDOW_EXPOSED:
      rencache_invalidate();
      lua_pushstring(L, "exposed");
      return 1;

    case SDL_EVENT_WINDOW_MINIMIZED:
      lua_pushstring(L, "minimized");
      return 1;

    case SDL_EVENT_WINDOW_MAXIMIZED:
      lua_pushstring(L, "maximized");
      return 1;

    case SDL_EVENT_WINDOW_RESTORED:
      lua_pushstring(L, "restored");
      return 1;

    case SDL_EVENT_WINDOW_MOUSE_LEAVE:
      lua_pushstring(L, "mouseleft");
      return 1;

    case SDL_EVENT_WINDOW_FOCUS_LOST:
      lua_pushstring(L, "focuslost");
      return 1;

    case SDL_EVENT_WINDOW_FOCUS_GAINED:
      /* on some systems, when alt-tabbing to the window SDL will queue up
      ** several KEYDOWN events for the `tab` key; we flush all keydown
      ** events on focus so these are discarded */
      SDL_FlushEvent(SDL_EVENT_KEY_DOWN);
      goto top;


    case SDL_EVENT_DROP_FILE:
      {
        RenWindow* window_renderer = ren_find_window_from_id(e.drop.windowID);
        SDL_GetMouseState(&mx, &my);
        lua_pushstring(L, "filedropped");
        lua_pushstring(L, e.drop.data);
        // a DND into dock event fired before a window is created
        lua_pushinteger(L, mx * (window_renderer ? window_renderer->scale_x : 0));
        lua_pushinteger(L, my * (window_renderer ? window_renderer->scale_y : 0));
        return 4;
      }

    case SDL_EVENT_KEY_DOWN:
#ifdef __APPLE__
      /* on macos 11.2.3 with sdl 2.0.14 the keyup handler for cmd+w below
      ** was not enough. Maybe the quit event started to be triggered from the
      ** keydown handler? In any case, flushing the quit event here too helped. */
      if ((e.key.key == SDLK_W) && (e.key.mod & SDL_KMOD_GUI)) {
        SDL_FlushEvent(SDL_EVENT_QUIT);
      }
#endif
      lua_pushstring(L, "keypressed");
      lua_pushstring(L, get_key_name(&e, buf));
      return 2;

    case SDL_EVENT_KEY_UP:
#ifdef __APPLE__
      /* on macos command+w will close the current window
      ** we want to flush this event and let the keymapper
      ** handle this key combination.
      ** Thanks to mathewmariani, taken from his lite-macos github repository. */
      if ((e.key.key == SDLK_W) && (e.key.mod & SDL_KMOD_GUI)) {
        SDL_FlushEvent(SDL_EVENT_QUIT);
      }
#endif
      lua_pushstring(L, "keyreleased");
      lua_pushstring(L, get_key_name(&e, buf));
      return 2;

    case SDL_EVENT_TEXT_INPUT:
      lua_pushstring(L, "textinput");
      lua_pushstring(L, e.text.text);
      return 2;

    case SDL_EVENT_TEXT_EDITING:
      lua_pushstring(L, "textediting");
      lua_pushstring(L, e.edit.text);
      lua_pushinteger(L, e.edit.start);
      lua_pushinteger(L, e.edit.length);
      return 4;

    case SDL_EVENT_MOUSE_BUTTON_DOWN:
      {
        if (e.button.button == 1) { SDL_CaptureMouse(1); }
        RenWindow* window_renderer = ren_find_window_from_id(e.button.windowID);
        lua_pushstring(L, "mousepressed");
        lua_pushstring(L, button_name(e.button.button));
        lua_pushinteger(L, e.button.x * window_renderer->scale_x);
        lua_pushinteger(L, e.button.y * window_renderer->scale_y);
        lua_pushinteger(L, e.button.clicks);
        return 5;
      }

    case SDL_EVENT_MOUSE_BUTTON_UP:
      {
        if (e.button.button == 1) { SDL_CaptureMouse(0); }
        RenWindow* window_renderer = ren_find_window_from_id(e.button.windowID);
        lua_pushstring(L, "mousereleased");
        lua_pushstring(L, button_name(e.button.button));
        lua_pushinteger(L, e.button.x * window_renderer->scale_x);
        lua_pushinteger(L, e.button.y * window_renderer->scale_y);
        return 4;
      }

    case SDL_EVENT_MOUSE_MOTION:
      {
        SDL_PumpEvents();
        while (SDL_PeepEvents(&event_plus, 1, SDL_GETEVENT, SDL_EVENT_MOUSE_MOTION, SDL_EVENT_MOUSE_MOTION) > 0) {
          e.motion.x = event_plus.motion.x;
          e.motion.y = event_plus.motion.y;
          e.motion.xrel += event_plus.motion.xrel;
          e.motion.yrel += event_plus.motion.yrel;
        }
        RenWindow* window_renderer = ren_find_window_from_id(e.motion.windowID);
        lua_pushstring(L, "mousemoved");
        lua_pushinteger(L, e.motion.x * window_renderer->scale_x);
        lua_pushinteger(L, e.motion.y * window_renderer->scale_y);
        lua_pushinteger(L, e.motion.xrel * window_renderer->scale_x);
        lua_pushinteger(L, e.motion.yrel * window_renderer->scale_y);
        return 5;
      }

    case SDL_EVENT_MOUSE_WHEEL:
      lua_pushstring(L, "mousewheel");
      lua_pushnumber(L, e.wheel.y);
      // Use -x to keep consistency with vertical scrolling values (e.g. shift+scroll)
      lua_pushnumber(L, -e.wheel.x);
      return 3;

    case SDL_EVENT_FINGER_DOWN:
      {
        RenWindow* window_renderer = ren_find_window_from_id(e.tfinger.windowID);
        SDL_GetWindowSize(window_renderer->window, &w, &h);

        lua_pushstring(L, "touchpressed");
        lua_pushinteger(L, (lua_Integer)(e.tfinger.x * w));
        lua_pushinteger(L, (lua_Integer)(e.tfinger.y * h));
        lua_pushinteger(L, e.tfinger.fingerID);
        return 4;
      }

    case SDL_EVENT_FINGER_UP:
      {
        RenWindow* window_renderer = ren_find_window_from_id(e.tfinger.windowID);
        SDL_GetWindowSize(window_renderer->window, &w, &h);

        lua_pushstring(L, "touchreleased");
        lua_pushinteger(L, (lua_Integer)(e.tfinger.x * w));
        lua_pushinteger(L, (lua_Integer)(e.tfinger.y * h));
        lua_pushinteger(L, e.tfinger.fingerID);
        return 4;
      }

    case SDL_EVENT_FINGER_MOTION:
      {
        SDL_PumpEvents();
        while (SDL_PeepEvents(&event_plus, 1, SDL_GETEVENT, SDL_EVENT_FINGER_MOTION, SDL_EVENT_FINGER_MOTION) > 0) {
          e.tfinger.x = event_plus.tfinger.x;
          e.tfinger.y = event_plus.tfinger.y;
          e.tfinger.dx += event_plus.tfinger.dx;
          e.tfinger.dy += event_plus.tfinger.dy;
        }
        RenWindow* window_renderer = ren_find_window_from_id(e.tfinger.windowID);
        SDL_GetWindowSize(window_renderer->window, &w, &h);

        lua_pushstring(L, "touchmoved");
        lua_pushinteger(L, (lua_Integer)(e.tfinger.x * w));
        lua_pushinteger(L, (lua_Integer)(e.tfinger.y * h));
        lua_pushinteger(L, (lua_Integer)(e.tfinger.dx * w));
        lua_pushinteger(L, (lua_Integer)(e.tfinger.dy * h));
        lua_pushinteger(L, e.tfinger.fingerID);
        return 6;
      }

    case SDL_EVENT_WILL_ENTER_FOREGROUND:
    case SDL_EVENT_DID_ENTER_FOREGROUND:
      {
        #ifdef LITE_USE_SDL_RENDERER
          rencache_invalidate();
        #else
          RenWindow** window_list;
          size_t window_count = ren_get_window_list(&window_list);
          while (window_count) {
            SDL_UpdateWindowSurface(window_list[--window_count]->window);
          }
        #endif
        lua_pushstring(L, e.type == SDL_EVENT_WILL_ENTER_FOREGROUND ? "enteringforeground" : "enteredforeground");
        return 1;
      }

    case SDL_EVENT_WILL_ENTER_BACKGROUND:
      lua_pushstring(L, "enteringbackground");
      return 1;

    case SDL_EVENT_DID_ENTER_BACKGROUND:
      lua_pushstring(L, "enteredbackground");
      return 1;

    case SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED:
    case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
      {
        RenWindow* window_renderer = ren_find_window_from_id(e.window.windowID);
        ren_resize_window(window_renderer);
      }

    default:
      // Custom event types are higher than SDL_EVENT_USER
      if (e.type >= SDL_EVENT_USER) {
        CustomEventCallback cec = get_custom_event_callback_by_type(e.type);
        if (cec != NULL) {
          int result = cec(L, &e);
          // If the callback didn't return anything, skip to the next event
          if (result != 0) {
            return result;
          }
        }
      }
      goto top;
  }

  return 0;
}


static int f_wait_event(lua_State *L) {
  int nargs = lua_gettop(L);
  if (nargs >= 1) {
    double n = luaL_checknumber(L, 1);
    if (n < 0) n = 0;
    lua_pushboolean(L, SDL_WaitEventTimeout(NULL, n * 1000));
  } else {
    lua_pushboolean(L, SDL_WaitEvent(NULL));
  }
  return 1;
}


static SDL_Cursor* cursor_cache[SDL_SYSTEM_CURSOR_POINTER + 1];

static const char *cursor_opts[] = {
  "arrow",
  "ibeam",
  "sizeh",
  "sizev",
  "hand",
  NULL
};

static const int cursor_enums[] = {
  SDL_SYSTEM_CURSOR_DEFAULT,
  SDL_SYSTEM_CURSOR_TEXT,
  SDL_SYSTEM_CURSOR_EW_RESIZE,
  SDL_SYSTEM_CURSOR_NS_RESIZE,
  SDL_SYSTEM_CURSOR_POINTER
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
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  const char *title = luaL_checkstring(L, 2);
  SDL_SetWindowTitle(window_renderer->window, title);
  return 0;
}


static const char *window_opts[] = { "normal", "minimized", "maximized", "fullscreen", 0 };
enum { WIN_NORMAL, WIN_MINIMIZED, WIN_MAXIMIZED, WIN_FULLSCREEN };

static int f_set_window_mode(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  int n = luaL_checkoption(L, 2, "normal", window_opts);
  SDL_SetWindowFullscreen(window_renderer->window, n == WIN_FULLSCREEN);
  if (n == WIN_NORMAL) { SDL_RestoreWindow(window_renderer->window); }
  if (n == WIN_MAXIMIZED) { SDL_MaximizeWindow(window_renderer->window); }
  if (n == WIN_MINIMIZED) { SDL_MinimizeWindow(window_renderer->window); }
  return 0;
}


static int f_set_window_bordered(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**) luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  SDL_SetWindowBordered(window_renderer->window, lua_toboolean(L, 2));
  return 0;
}


static int f_set_window_hit_test(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**) luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  if (lua_gettop(L) == 1) {
    SDL_SetWindowHitTest(window_renderer->window, NULL, NULL);
    return 0;
  }
  window_hit_info->title_height = luaL_checknumber(L, 2);
  window_hit_info->controls_width = luaL_checknumber(L, 3);
  window_hit_info->resize_border = luaL_checknumber(L, 4);
  SDL_SetWindowHitTest(window_renderer->window, &hit_test, window_hit_info);
  return 0;
}


static int f_get_window_size(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  int x, y, w, h;
  SDL_GetWindowSize(window_renderer->window, &w, &h);
  SDL_GetWindowPosition(window_renderer->window, &x, &y);
  lua_pushinteger(L, w);
  lua_pushinteger(L, h);
  lua_pushinteger(L, x);
  lua_pushinteger(L, y);
  return 4;
}


static int f_set_window_size(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  double w = luaL_checknumber(L, 2);
  double h = luaL_checknumber(L, 3);
  double x = luaL_checknumber(L, 4);
  double y = luaL_checknumber(L, 5);
  SDL_SetWindowSize(window_renderer->window, w, h);
  SDL_SetWindowPosition(window_renderer->window, x, y);
  ren_resize_window(window_renderer);
  return 0;
}


static int f_window_has_focus(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  unsigned flags = SDL_GetWindowFlags(window_renderer->window);
  lua_pushboolean(L, flags & SDL_WINDOW_INPUT_FOCUS);
  return 1;
}


static int f_get_window_mode(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  unsigned flags = SDL_GetWindowFlags(window_renderer->window);
  if (flags & SDL_WINDOW_FULLSCREEN) {
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

static int f_set_text_input_rect(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  SDL_Rect rect;
  rect.x = luaL_checknumber(L, 2);
  rect.y = luaL_checknumber(L, 3);
  rect.w = luaL_checknumber(L, 4);
  rect.h = luaL_checknumber(L, 5);
  SDL_SetTextInputArea(window_renderer->window, &rect, 0);
  return 0;
}

static int f_clear_ime(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  SDL_ClearComposition(window_renderer->window);
  return 0;
}


static int f_raise_window(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  SDL_RaiseWindow(window_renderer->window);
  return 0;
}


static int f_show_fatal_error(lua_State *L) {
  const char *title = luaL_checkstring(L, 1);
  const char *msg = luaL_checkstring(L, 2);

#ifdef _WIN32
  MessageBox(0, msg, title, MB_OK | MB_ICONERROR);
#else
  SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, title, msg, NULL);
#endif
  return 0;
}


// removes an empty directory
static int f_rmdir(lua_State *L) {
  lua_pushboolean(L, SDL_RemovePath(luaL_checkstring(L, 1)));
  if (!lua_toboolean(L, -1)) {
    lua_pushstring(L, SDL_GetError());
    return 2;
  }
  return 1;
}


static int f_chdir(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
#ifdef _WIN32
  LPWSTR wpath = utfconv_utf8towc(path);
  if (wpath == NULL) { return luaL_error(L, UTFCONV_ERROR_INVALID_CONVERSION ); }
  int err = _wchdir(wpath);
  SDL_free(wpath);
#else
  int err = chdir(path);
#endif
  if (err) { luaL_error(L, "chdir() failed: %s", strerror(errno)); }
  return 0;
}

static SDL_EnumerationResult list_dir_enumeration_callback(void *userdata, const char *dirname, const char *fname) {
  (void) dirname;
  lua_State *L = userdata;
  int len = lua_rawlen(L, -1);
  lua_pushstring(L, fname);
  lua_rawseti(L, -2, len + 1);
  return SDL_ENUM_CONTINUE;
}

static int f_list_dir(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
  lua_newtable(L);
  bool res = SDL_EnumerateDirectory(path, list_dir_enumeration_callback, L);
  if (!res) {
    lua_pushnil(L);
    lua_pushstring(L, SDL_GetError());
    return 2;
  }
  return 1;
}


#ifdef _WIN32
  #define realpath(x, y) _wfullpath(y, x, MAX_PATH)
#endif

static int f_absolute_path(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);
#ifdef _WIN32
  LPWSTR wpath = utfconv_utf8towc(path);
  if (!wpath) { return 0; }

  LPWSTR wfullpath = realpath(wpath, NULL);
  SDL_free(wpath);
  if (!wfullpath) { return 0; }

  char *res = utfconv_wctoutf8(wfullpath);
  SDL_free(wfullpath);
#else
  char *res = realpath(path, NULL);
#endif
  if (!res) { return 0; }
  lua_pushstring(L, res);
  SDL_free(res);
  return 1;
}


static int f_get_file_info(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);

  lua_newtable(L);
#ifdef _WIN32
  LPWSTR wpath = utfconv_utf8towc(path);
  if (wpath == NULL) {
    lua_pushnil(L); lua_pushstring(L, UTFCONV_ERROR_INVALID_CONVERSION);
    return 2;
  }
  WIN32_FILE_ATTRIBUTE_DATA data;
  if (!GetFileAttributesExW(wpath, GetFileExInfoStandard, &data)) {
    SDL_free(wpath);
    lua_pushnil(L); push_win32_error(L, GetLastError());
    return 2;
  }
  SDL_free(wpath);
  ULARGE_INTEGER large_int = {0};
  #define TICKS_PER_MILISECOND 10000
  #define EPOCH_DIFFERENCE 11644473600000LL
  // https://stackoverflow.com/questions/6161776/convert-windows-filetime-to-second-in-unix-linux
  large_int.HighPart = data.ftLastWriteTime.dwHighDateTime; large_int.LowPart = data.ftLastWriteTime.dwLowDateTime;
  lua_pushnumber(L, (double)((large_int.QuadPart / TICKS_PER_MILISECOND - EPOCH_DIFFERENCE)/1000.0));
  lua_setfield(L, -2, "modified");

  large_int.HighPart = data.nFileSizeHigh; large_int.LowPart = data.nFileSizeLow;
  lua_pushinteger(L, large_int.QuadPart);
  lua_setfield(L, -2, "size");

  lua_pushstring(L, data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY ? "dir" : "file");
  lua_setfield(L, -2, "type");

  lua_pushboolean(L, data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY && data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT);
  lua_setfield(L, -2, "symlink");
#else
  struct stat s;
  int err = stat(path, &s);
  if (err < 0) {
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
  }

  lua_pushinteger(L, s.st_size);
  lua_setfield(L, -2, "size");

  if (S_ISREG(s.st_mode)) {
    lua_pushstring(L, "file");
  } else if (S_ISDIR(s.st_mode)) {
    lua_pushstring(L, "dir");
  } else {
    lua_pushnil(L);
  }
  lua_setfield(L, -2, "type");

  double mtime;
  #if _BSD_SOURCE || _SVID_SOURCE || _XOPEN_SOURCE > 700 || _POSIX_C_SOURCE >= 200809L
    mtime = (double)s.st_mtim.tv_sec + (s.st_mtim.tv_nsec / 1000000000.0);
  #elif __APPLE__
    #if !defined(_POSIX_C_SOURCE) || defined(_DARWIN_C_SOURCE)
      mtime = (double)s.st_mtimespec.tv_sec + (s.st_mtimespec.tv_nsec / 1000000000.0);
    #else
      mtime = (double)s.st_mtime + (s.st_atimensec / 1000000000.0);
    #endif
  #else
    mtime = s.st_mtime;
  #endif
  lua_pushnumber(L, mtime);
  lua_setfield(L, -2, "modified");

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

#endif

static int f_get_fs_type(lua_State *L) {
  #if __linux__
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
  #endif
  lua_pushstring(L, "unknown");
  return 1;
}


static int f_ftruncate(lua_State *L) {
#if LUA_VERSION_NUM < 503
  // note: it is possible to support pre 5.3 and JIT
  //       since file handles are just FILE*  wrapped in a userdata;
  //       but it is not standardized. YMMV.
  #error luaL_Stream is not supported in this version of Lua.
#endif
  luaL_Stream *stream = luaL_checkudata(L, 1, LUA_FILEHANDLE);
  lua_Integer len = luaL_optinteger(L, 2, 0);
  if (ftruncate(fileno(stream->f), len) != 0) {
    lua_pushboolean(L, 0);
    lua_pushfstring(L, "ftruncate(): %s", strerror(errno));
    return 2;
  }

  lua_pushboolean(L, 1);
  return 1;
}


static int f_mkdir(lua_State *L) {
  const char *path = luaL_checkstring(L, 1);

#ifdef _WIN32
  LPWSTR wpath = utfconv_utf8towc(path);
  if (wpath == NULL) {
    lua_pushboolean(L, 0);
    lua_pushstring(L, UTFCONV_ERROR_INVALID_CONVERSION);
    return 2;
  }

  int err = _wmkdir(wpath);
  SDL_free(wpath);
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
#ifdef _WIN32
  // on windows, text-based clipboard formats must terminate with \r\n
  // we need to convert it to \n for Lite XL to read them properly
  // https://learn.microsoft.com/en-us/windows/win32/dataxchg/standard-clipboard-formats
  luaL_gsub(L, text, "\r\n", "\n");
#else
  lua_pushstring(L, text);
#endif
  SDL_free(text);
  return 1;
}


static int f_set_clipboard(lua_State *L) {
  const char *text = luaL_checkstring(L, 1);
  SDL_SetClipboardText(text);
  return 0;
}


static int f_get_primary_selection(lua_State *L) {
  char *text = SDL_GetPrimarySelectionText();
  if (!text) { return 0; }
  lua_pushstring(L, text);
  SDL_free(text);
  return 1;
}


static int f_set_primary_selection(lua_State *L) {
  const char *text = luaL_checkstring(L, 1);
  SDL_SetPrimarySelectionText(text);
  return 0;
}


static int f_get_process_id(lua_State *L) {
#ifdef _WIN32
  lua_pushinteger(L, GetCurrentProcessId());
#else
  lua_pushinteger(L, getpid());
#endif
  return 1;
}


static int f_get_time(lua_State *L) {
  double n = SDL_GetPerformanceCounter() / (double) SDL_GetPerformanceFrequency();
  lua_pushnumber(L, n);
  return 1;
}


static int f_sleep(lua_State *L) {
  double n = luaL_checknumber(L, 1);
  if (n < 0) n = 0;
  SDL_Delay(n * 1000);
  return 0;
}


static int f_exec(lua_State *L) {
  size_t len;
  const char *cmd = luaL_checklstring(L, 1, &len);
  char *buf = SDL_malloc(len + 32);
  if (!buf) { luaL_error(L, "buffer allocation failed"); }
#if _WIN32
  sprintf(buf, "cmd /c \"%s\"", cmd);
  WinExec(buf, SW_HIDE);
#else
  sprintf(buf, "%s &", cmd);
  int res = system(buf);
  (void) res;
#endif
  SDL_free(buf);
  return 0;
}

static int f_fuzzy_match(lua_State *L) {
  size_t strLen, ptnLen;
  const char *str = luaL_checklstring(L, 1, &strLen);
  const char *ptn = luaL_checklstring(L, 2, &ptnLen);
  // If true match things *backwards*. This allows for better matching on filenames than the above
  // function. For example, in the lite project, opening "renderer" has lib/font_render/build.sh
  // as the first result, rather than src/renderer.c. Clearly that's wrong.
  bool files = lua_gettop(L) > 2 && lua_isboolean(L,3) && lua_toboolean(L, 3);
  int score = 0, run = 0, increment = files ? -1 : 1;
  const char* strTarget = files ? str + strLen - 1 : str;
  const char* ptnTarget = files ? ptn + ptnLen - 1 : ptn;
  while (strTarget >= str && ptnTarget >= ptn && *strTarget && *ptnTarget) {
    while (strTarget >= str && *strTarget == ' ') { strTarget += increment; }
    while (ptnTarget >= ptn && *ptnTarget == ' ') { ptnTarget += increment; }
    if (tolower(*strTarget) == tolower(*ptnTarget)) {
      score += run * 10 - (*strTarget != *ptnTarget);
      run++;
      ptnTarget += increment;
    } else {
      score -= 10;
      run = 0;
    }
    strTarget += increment;
  }
  if (ptnTarget >= ptn && *ptnTarget) { return 0; }
  lua_pushinteger(L, score - (int)strLen * 10);
  return 1;
}

static int f_set_window_opacity(lua_State *L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  double n = luaL_checknumber(L, 2);
  int r = SDL_SetWindowOpacity(window_renderer->window, n);
  lua_pushboolean(L, r > -1);
  return 1;
}

typedef void (*fptr)(void);

typedef struct lua_function_node {
  const char *symbol;
  fptr address;
} lua_function_node;

#define P(FUNC) { "lua_" #FUNC, (fptr)(lua_##FUNC) }
#define U(FUNC) { "luaL_" #FUNC, (fptr)(luaL_##FUNC) }
#define S(FUNC) { #FUNC, (fptr)(FUNC) }
static void* api_require(const char* symbol) {
  static const lua_function_node nodes[] = {
    #if LUA_VERSION_NUM == 501 || LUA_VERSION_NUM == 502 || LUA_VERSION_NUM == 503 || LUA_VERSION_NUM == 504
    U(addlstring), U(addstring), U(addvalue), U(argerror), U(buffinit),
    U(callmeta), U(checkany), U(checkinteger), U(checklstring),
    U(checknumber), U(checkoption), U(checkstack), U(checktype),
    U(checkudata), U(error), U(getmetafield), U(gsub), U(loadstring),
    U(newmetatable), U(newstate), U(openlibs), U(optinteger), U(optlstring),
    U(optnumber), U(pushresult), U(ref), U(unref), U(where), P(atpanic),
    P(checkstack), P(close), P(concat), P(createtable), P(dump), P(error),
    P(gc), P(getallocf), P(getfield), P(gethook), P(gethookcount),
    P(gethookmask), P(getinfo), P(getlocal), P(getmetatable), P(getstack),
    P(gettable), P(gettop), P(getupvalue), P(iscfunction), P(isnumber),
    P(isstring), P(isuserdata), P(load), P(newstate), P(newthread), P(next),
    P(pushboolean), P(pushcclosure), P(pushfstring), P(pushinteger),
    P(pushlightuserdata), P(pushlstring), P(pushnil), P(pushnumber),
    P(pushstring), P(pushthread), P(pushvalue), P(pushvfstring), P(rawequal),
    P(rawget), P(rawgeti), P(rawset), P(rawseti), P(resume), P(setallocf),
    P(setfield), P(sethook), P(setlocal), P(setmetatable), P(settable),
    P(settop), P(setupvalue), P(status), P(toboolean), P(tocfunction),
    P(tolstring), P(topointer), P(tothread), P(touserdata), P(type),
    P(typename), P(xmove), S(luaopen_base), S(luaopen_debug), S(luaopen_io),
    S(luaopen_math), S(luaopen_os), S(luaopen_package), S(luaopen_string),
    S(luaopen_table), S(api_load_libs),
    #endif
    #if LUA_VERSION_NUM == 502 || LUA_VERSION_NUM == 503 || LUA_VERSION_NUM == 504
    U(buffinitsize), U(checkversion_), U(execresult), U(fileresult),
    U(getsubtable), U(len), U(loadbufferx), U(loadfilex), U(prepbuffsize),
    U(pushresultsize), U(requiref), U(setfuncs), U(setmetatable),
    U(testudata), U(tolstring), U(traceback), P(absindex), P(arith),
    P(callk), P(compare), P(copy), P(getglobal), P(len), P(pcallk),
    P(rawgetp), P(rawlen), P(rawsetp), P(setglobal), P(tointegerx),
    P(tonumberx), P(upvalueid), P(upvaluejoin), P(version), P(yieldk),
    S(luaopen_coroutine),
    #endif
    #if LUA_VERSION_NUM == 501 || LUA_VERSION_NUM == 502 || LUA_VERSION_NUM == 503
    P(newuserdata),
    #endif
    #if LUA_VERSION_NUM == 503 || LUA_VERSION_NUM == 504
    P(geti), P(isinteger), P(isyieldable), P(rotate), P(seti),
    P(stringtonumber), S(luaopen_utf8),
    #endif
    #if LUA_VERSION_NUM == 502 || LUA_VERSION_NUM == 503
    P(getuservalue), P(setuservalue), S(luaopen_bit32),
    #endif
    #if LUA_VERSION_NUM == 501 || LUA_VERSION_NUM == 502
    P(insert), P(remove), P(replace),
    #endif
    #if LUA_VERSION_NUM == 504
    U(addgsub), U(typeerror), P(closeslot), P(getiuservalue),
    P(newuserdatauv), P(resetthread), P(setcstacklimit), P(setiuservalue),
    P(setwarnf), P(toclose), P(warning),
    #endif
    #if LUA_VERSION_NUM == 502
    U(checkunsigned), U(optunsigned), P(getctx), P(pushunsigned),
    P(tounsignedx),
    #endif
    #if LUA_VERSION_NUM == 501
    U(findtable), U(loadbuffer), U(loadfile), U(openlib), U(prepbuffer),
    U(register), U(typerror), P(call), P(cpcall), P(equal), P(getfenv),
    P(lessthan), P(objlen), P(pcall), P(setfenv), P(setlevel), P(tointeger),
    P(tonumber), P(yield),
    #endif
  };
  for (size_t i = 0; i < sizeof(nodes) / sizeof(lua_function_node); ++i) {
    if (strcmp(nodes[i].symbol, symbol) == 0)
      return *(void**)(&nodes[i].address);
  }
  return NULL;
}

static int f_library_gc(lua_State *L) {
  lua_getfield(L, 1, "handle");
  void* handle = lua_touserdata(L, -1);
  SDL_UnloadObject(handle);

  return 0;
}

static int f_load_native_plugin(lua_State *L) {
  char entrypoint_name[512]; entrypoint_name[sizeof(entrypoint_name) - 1] = '\0';
  int result;

  const char *name = luaL_checkstring(L, 1);
  const char *path = luaL_checkstring(L, 2);
  void *library = SDL_LoadObject(path);
  if (!library)
    return (lua_pushstring(L, SDL_GetError()), lua_error(L));

  lua_getglobal(L, "package");
  lua_getfield(L, -1, "native_plugins");
  lua_newtable(L);
  lua_pushlightuserdata(L, library);
  lua_setfield(L, -2, "handle");
  luaL_setmetatable(L, API_TYPE_NATIVE_PLUGIN);
  lua_setfield(L, -2, name);
  lua_pop(L, 2);

  const char *basename = strrchr(name, '.');
  basename = !basename ? name : basename + 1;
  snprintf(entrypoint_name, sizeof(entrypoint_name), "luaopen_lite_xl_%s", basename);
  int (*ext_entrypoint) (lua_State *L, void* (*)(const char*));
  *(void**)(&ext_entrypoint) = SDL_LoadFunction(library, entrypoint_name);
  if (!ext_entrypoint) {
    snprintf(entrypoint_name, sizeof(entrypoint_name), "luaopen_%s", basename);
    int (*entrypoint)(lua_State *L);
    *(void**)(&entrypoint) = SDL_LoadFunction(library, entrypoint_name);
    if (!entrypoint)
      return luaL_error(L, "Unable to load %s: Can't find %s(lua_State *L, void *XL)", name, entrypoint_name);
    result = entrypoint(L);
  } else {
    result = ext_entrypoint(L, api_require);
  }

  if (!result)
    return luaL_error(L, "Unable to load %s: entrypoint must return a value", name);

  return result;
}

#ifdef _WIN32
#define PATHSEP '\\'
#else
#define PATHSEP '/'
#endif

/* Special purpose filepath compare function. Corresponds to the
   order used in the TreeView view of the project's files. Returns true if
   path1 < path2 in the TreeView order. */
static int f_path_compare(lua_State *L) {
  size_t len1, len2;
  const char *path1 = luaL_checklstring(L, 1, &len1);
  const char *type1_s = luaL_checkstring(L, 2);
  const char *path2 = luaL_checklstring(L, 3, &len2);
  const char *type2_s = luaL_checkstring(L, 4);
  int type1 = strcmp(type1_s, "dir") != 0;
  int type2 = strcmp(type2_s, "dir") != 0;
  /* Find the index of the common part of the path. */
  size_t offset = 0, i, j;
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
  int cfr = -1;
  bool same_len = len1 == len2;
  for (i = offset, j = offset; i <= len1 && j <= len2; i++, j++) {
    if (path1[i] == 0 || path2[j] == 0) {
      if (cfr < 0) cfr = 0; // The strings are equal
      if (!same_len) {
        cfr = (path1[i] == 0);
      }
    } else if (isdigit(path1[i]) && isdigit(path2[j])) {
      size_t ii = 0, ij = 0;
      while (isdigit(path1[i+ii])) { ii++; }
      while (isdigit(path2[j+ij])) { ij++; }

      size_t di = 0, dj = 0;
      for (size_t ai = 0; ai < ii; ++ai) {
        di = di * 10 + (path1[i+ai] - '0');
      }
      for (size_t aj = 0; aj < ij; ++aj) {
        dj = dj * 10 + (path2[j+aj] - '0');
      }

      if (di == dj) {
        continue;
      }
      cfr = (di < dj);
    } else if (path1[i] == path2[j]) {
      continue;
    } else if (path1[i] == PATHSEP || path2[j] == PATHSEP) {
      /* For comparison we treat PATHSEP as if it was the string terminator. */
      cfr = (path1[i] == PATHSEP);
    } else {
      char a = path1[i], b = path2[j];
      if (a >= 'A' && a <= 'Z') a += 32;
      if (b >= 'A' && b <= 'Z') b += 32;
      if (a == b) {
        /* If the strings have the same length, we need
           to keep the first case sensitive difference. */
        if (same_len && cfr < 0) {
          /* Give priority to lower-case characters */
          cfr = (path1[i] > path2[j]);
        }
        continue;
      }
      cfr = (a < b);
    }
    break;
  }
  lua_pushboolean(L, cfr);
  return 1;
}


static int f_text_input(lua_State* L) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  if (!window_renderer) return 0;
  if (lua_toboolean(L, 2)) {
    SDL_StartTextInput(window_renderer->window);
  } else {
    SDL_StopTextInput(window_renderer->window);
  }
  return 0;
}

static int f_setenv(lua_State* L) {
  const char *key = luaL_checkstring(L, 1);
  const char *val = luaL_checkstring(L, 2);
  // right now we overwrite unconditionally
  lua_pushboolean(L, SDL_setenv_unsafe(key, val, 1) == 0);
  return 1;
}

typedef struct {
  uintptr_t id;
  SDL_DialogFileFilter *filters;
  size_t n_filters;
} DialogData;

static void free_dialog_filters(SDL_DialogFileFilter *filters, size_t n_filters) {
  for (size_t i = 0; i < n_filters; i++) {
    SDL_free((char *)filters[i].name);
    SDL_free((char *)filters[i].pattern);
  }
}

static void dialog_callback(void *userdata, const char * const *filelist, int filter) {
  // TODO: support getting the selected filter?
  //       as of SDL 3.2.10 only the windows backend supports that,
  //       the others just return -1
  CustomEvent event;
  SDL_zero(event);
  DialogData *dd = userdata;

  event.data1 = (void *)dd->id;

  // Filters had to be available until this callback was called,
  // so we can free them now
  free_dialog_filters(dd->filters, dd->n_filters);
  SDL_free(dd->filters);
  SDL_free(dd);

  if (filelist == NULL) {
    event.code = DIALOG_ERROR;
    event.data2 = SDL_strdup(SDL_GetError());
  } else if (*filelist == NULL) {
    event.code = DIALOG_CANCEL;
  } else {
    event.code = DIALOG_OK;

    // Calculate total size needed for every entry
    size_t bytes = 0;
    for (size_t i = 0; filelist[i] != NULL; i++) {
      bytes += SDL_strlen(filelist[i]) + 1;
    }
    
    char *dataptr = event.data2 = SDL_malloc(bytes + 1); // +1 for NULL last entry
    if (event.data2 == NULL) {
      event.code = DIALOG_ERROR;
    } else {
      for (size_t i = 0; filelist[i] != NULL; i++) {
        size_t len = SDL_strlen(filelist[i]) + 1;
        SDL_memcpy(dataptr, filelist[i], len);
        dataptr += len;
      }
      *dataptr = '\0'; // NULL last entry
    }
  }
  if (!push_custom_event(dialogfinished_event_name, &event)) {
    // TODO: panic?
    SDL_free(event.data2);
  }
}

static SDL_DialogFileFilter *get_dialog_filters(lua_State* L, int index, lxl_arena *A, size_t *n_filters) {
  if (index < 0) {
    index += lua_gettop(L) + 1;
  }

  *n_filters = 0;
  if (lua_isnoneornil(L, index)) {
    return NULL;
  }

  size_t n = luaL_len(L, index);
  if (n == 0) {
    return NULL;
  }

  SDL_DialogFileFilter *filters = lxl_arena_malloc(A, n * sizeof(SDL_DialogFileFilter));

  for (size_t i = 0; i < n; i++) {
    size_t str_size = 0;
    const char *tmp;

    lua_geti(L, index, i + 1);

    lua_getfield(L, -1, "name");
    tmp = luaL_checklstring(L, -1, &str_size);
    filters[i].name = lxl_arena_copy(A, tmp, str_size + 1);

    lua_getfield(L, -2, "pattern");
    tmp = luaL_checklstring(L, -1, &str_size);
    filters[i].pattern = lxl_arena_copy(A, tmp, str_size + 1);

    lua_pop(L, 3);
  }

  *n_filters = n;
  return filters;
}

typedef struct {
  bool allow_many;
  char *default_location;
  char *title;
  char *accept_label;
  char *cancel_label;
} DialogOptions;

static void get_dialog_options(lua_State* L, int index, SDL_FileDialogType type, lxl_arena *A, DialogOptions *options, SDL_DialogFileFilter **filters, size_t *n_filters) {
  if (index < 0) {
    index += lua_gettop(L) + 1;
  }
  options->allow_many = false;
  options->default_location = NULL;
  options->title = NULL;
  options->accept_label = NULL;
  options->cancel_label = NULL;
  *filters = NULL;
  *n_filters = 0;

  if (lua_isnoneornil(L, index)) {
    // No options specified
    return;
  }
  luaL_checktype(L, index, LUA_TTABLE);

  size_t str_size = 0;
  const char* tmp;

  lua_getfield(L, index, "default_location");
  tmp = luaL_optlstring(L, -1, NULL, &str_size);
  options->default_location = lxl_arena_copy(A, tmp, str_size + 1);

  lua_getfield(L, index, "title");
  tmp = luaL_optlstring(L, -1, NULL, &str_size);
  options->title = lxl_arena_copy(A, tmp, str_size + 1);

  lua_getfield(L, index, "accept_label");
  tmp = luaL_optlstring(L, -1, NULL, &str_size);
  options->accept_label = lxl_arena_copy(A, tmp, str_size + 1);

  lua_getfield(L, index, "cancel_label");
  tmp = luaL_optlstring(L, -1, NULL, &str_size);
  options->cancel_label = lxl_arena_copy(A, tmp, str_size + 1);

  lua_pop(L, 4);

  if (type == SDL_FILEDIALOG_OPENFILE || type == SDL_FILEDIALOG_OPENFOLDER) {
    lua_getfield(L, index, "allow_many");
    options->allow_many = luaL_opt(L, lua_toboolean, -1, false);
    lua_pop(L, 1);
  }

  if (type == SDL_FILEDIALOG_OPENFILE || type == SDL_FILEDIALOG_SAVEFILE) {
    lua_getfield(L, index, "filters");
    *filters = get_dialog_filters(L, -1, A, n_filters);
    lua_pop(L, 1);
  }
}

static int open_dialog(lua_State* L, SDL_FileDialogType type) {
  RenWindow *window_renderer = *(RenWindow**)luaL_checkudata(L, 1, API_TYPE_RENWINDOW);
  uintptr_t id = luaL_checkinteger(L, 2);
  DialogOptions options;
  SDL_zero(options);
  SDL_DialogFileFilter *arena_filters = NULL;
  size_t n_filters = 0;

  if (!lua_isnoneornil(L, 3)) {
    get_dialog_options(
      L, 3, type,
      lxl_arena_init(L),
      &options, &arena_filters, &n_filters
    );
  }

  SDL_PropertiesID props = SDL_CreateProperties();
  if (props == 0) {
    return luaL_error(L, "Error while creating SDL Property: %s", SDL_GetError());
  }

  DialogData *dd = SDL_calloc(1, sizeof(DialogData));
  if (dd == NULL) {
    return luaL_error(L, "Unable to allocate DialogData memory");
  }
  dd->id = id;
  dd->n_filters = n_filters;
  dd->filters = SDL_malloc(n_filters * sizeof(SDL_DialogFileFilter));

  if (dd->filters == NULL) {
    SDL_free(dd);
    return luaL_error(L, "Unable to allocate SDL_DialogFileFilter memory");
  }

  // SDL needs the filters to be available at least until the callback is called.
  // arena_filters memory is handled by Lua so we can't use it as-is
  for (size_t i = 0; i < n_filters; i++) {
    dd->filters[i].name = SDL_strdup(arena_filters[i].name);
    dd->filters[i].pattern = SDL_strdup(arena_filters[i].pattern);
    if (dd->filters[i].name == NULL || dd->filters[i].pattern == NULL) {
      free_dialog_filters(dd->filters, i);
      SDL_free(dd->filters);
      SDL_free(dd);
      return luaL_error(L, "Unable to allocate memory for SDL_DialogFileFilter values");
    }
  }

  SDL_SetPointerProperty(props, SDL_PROP_FILE_DIALOG_FILTERS_POINTER, dd->filters);
  SDL_SetNumberProperty(props, SDL_PROP_FILE_DIALOG_NFILTERS_NUMBER, n_filters);
  SDL_SetPointerProperty(props, SDL_PROP_FILE_DIALOG_WINDOW_POINTER, window_renderer->window);
  SDL_SetStringProperty(props, SDL_PROP_FILE_DIALOG_LOCATION_STRING, options.default_location);
  SDL_SetBooleanProperty(props, SDL_PROP_FILE_DIALOG_MANY_BOOLEAN, options.allow_many);
  SDL_SetStringProperty(props, SDL_PROP_FILE_DIALOG_TITLE_STRING, options.title);
  SDL_SetStringProperty(props, SDL_PROP_FILE_DIALOG_ACCEPT_STRING, options.accept_label);
  SDL_SetStringProperty(props, SDL_PROP_FILE_DIALOG_CANCEL_STRING, options.cancel_label);

  SDL_ShowFileDialogWithProperties(type, dialog_callback, dd, props);

  SDL_DestroyProperties(props);
  return 0;
}

static int dialogfinished_callback(lua_State *L, SDL_Event *e) {
  lua_pushstring(L, "dialogfinished");
  lua_pushinteger(L, (uintptr_t)e->user.data1); // ID

  switch ((DialogState)e->user.code) {
    case DIALOG_OK:
      lua_pushstring(L, "accept");
      char *dataptr = e->user.data2;
      lua_newtable(L);
      for (size_t i = 1; *dataptr != '\0'; i++) {
        lua_pushstring(L, dataptr);
        size_t len = lua_rawlen(L, -1) + 1;
        lua_rawseti(L, -2, i);
        dataptr += len;
      }
      SDL_free(e->user.data2);
      return 4;
    case DIALOG_CANCEL:
      lua_pushstring(L, "cancel");
      return 3;
    case DIALOG_ERROR:
      lua_pushstring(L, "error");
      lua_pushstring(L, e->user.data2);
      SDL_free(e->user.data2);
      return 4;
    default:
      lua_pushstring(L, "unknown");
      return 3;
  }
}

static int f_open_file_dialog(lua_State* L) {
  return open_dialog(L, SDL_FILEDIALOG_OPENFILE);
}

static int f_save_file_dialog(lua_State* L) {
  return open_dialog(L, SDL_FILEDIALOG_SAVEFILE);
}

static int f_open_directory_dialog(lua_State* L) {
  return open_dialog(L, SDL_FILEDIALOG_OPENFOLDER);
}

static int f_get_sandbox(lua_State* L) {
  char *sandbox_name = "unknown";
  switch (SDL_GetSandbox()) {
    case SDL_SANDBOX_NONE:
      sandbox_name = "none";
      break;
    case SDL_SANDBOX_UNKNOWN_CONTAINER:
      sandbox_name = "unknown";
      break;
    case SDL_SANDBOX_FLATPAK:
      sandbox_name = "flatpak";
      break;
    case SDL_SANDBOX_SNAP:
      sandbox_name = "snap";
      break;
    case SDL_SANDBOX_MACOS:
      sandbox_name = "macos";
      break;
  }
  lua_pushstring(L, sandbox_name);
  return 1;
}

static const luaL_Reg lib[] = {
  { "poll_event",            f_poll_event            },
  { "wait_event",            f_wait_event            },
  { "set_cursor",            f_set_cursor            },
  { "set_window_title",      f_set_window_title      },
  { "set_window_mode",       f_set_window_mode       },
  { "get_window_mode",       f_get_window_mode       },
  { "set_window_bordered",   f_set_window_bordered   },
  { "set_window_hit_test",   f_set_window_hit_test   },
  { "get_window_size",       f_get_window_size       },
  { "set_window_size",       f_set_window_size       },
  { "set_text_input_rect",   f_set_text_input_rect   },
  { "clear_ime",             f_clear_ime             },
  { "window_has_focus",      f_window_has_focus      },
  { "raise_window",          f_raise_window          },
  { "show_fatal_error",      f_show_fatal_error      },
  { "rmdir",                 f_rmdir                 },
  { "chdir",                 f_chdir                 },
  { "mkdir",                 f_mkdir                 },
  { "list_dir",              f_list_dir              },
  { "absolute_path",         f_absolute_path         },
  { "get_file_info",         f_get_file_info         },
  { "get_clipboard",         f_get_clipboard         },
  { "set_clipboard",         f_set_clipboard         },
  { "get_primary_selection", f_get_primary_selection },
  { "set_primary_selection", f_set_primary_selection },
  { "get_process_id",        f_get_process_id        },
  { "get_time",              f_get_time              },
  { "sleep",                 f_sleep                 },
  { "exec",                  f_exec                  },
  { "fuzzy_match",           f_fuzzy_match           },
  { "set_window_opacity",    f_set_window_opacity    },
  { "load_native_plugin",    f_load_native_plugin    },
  { "path_compare",          f_path_compare          },
  { "get_fs_type",           f_get_fs_type           },
  { "text_input",            f_text_input            },
  { "setenv",                f_setenv                },
  { "ftruncate",             f_ftruncate             },
  { "open_file_dialog",      f_open_file_dialog      },
  { "save_file_dialog",      f_save_file_dialog      },
  { "open_directory_dialog", f_open_directory_dialog },
  { "get_sandbox",           f_get_sandbox           },
  { NULL, NULL }
};


int luaopen_system(lua_State *L) {
  if (!register_custom_event(dialogfinished_event_name, dialogfinished_callback)) {
    return luaL_error(L, "Unable to register custom dialogfinished event: %s", SDL_GetError());
  }
  luaL_newmetatable(L, API_TYPE_NATIVE_PLUGIN);
  lua_pushcfunction(L, f_library_gc);
  lua_setfield(L, -2, "__gc");
  luaL_newlib(L, lib);
  return 1;
}
