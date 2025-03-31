#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <ctype.h>

#define SDL_MAIN_USE_CALLBACKS

#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#include "api/api.h"
#include "rencache.h"
#include "renwindow.h"
#include "renderer.h"

#ifdef _WIN32
  #include <windows.h>
#elif defined(__linux__) || defined(__serenity__)
  #include <unistd.h>
#elif defined(SDL_PLATFORM_APPLE)
  #include <mach-o/dyld.h>
#elif defined(__FreeBSD__)
  #include <sys/sysctl.h>
#endif

static void get_exe_filename(char *buf, int sz) {
#if _WIN32
  int len;
  wchar_t *buf_w = malloc(sizeof(wchar_t) * sz);
  if (buf_w) {
    len = GetModuleFileNameW(NULL, buf_w, sz - 1);
    buf_w[len] = L'\0';
    // if the conversion failed we'll empty the string
    if (!WideCharToMultiByte(CP_UTF8, 0, buf_w, -1, buf, sz, NULL, NULL))
      buf[0] = '\0';
    free(buf_w);
  } else {
    buf[0] = '\0';
  }
#elif __linux__ || __serenity__
  char path[] = "/proc/self/exe";
  ssize_t len = readlink(path, buf, sz - 1);
  if (len > 0)
    buf[len] = '\0';
#elif SDL_PLATFORM_APPLE
  /* use realpath to resolve a symlink if the process was launched from one.
  ** This happens when Homebrew installs a cack and creates a symlink in
  ** /usr/loca/bin for launching the executable from the command line. */
  unsigned size = sz;
  char exepath[size];
  _NSGetExecutablePath(exepath, &size);
  realpath(exepath, buf);
#elif __FreeBSD__
  size_t len = sz;
  const int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, -1 };
  sysctl(mib, 4, buf, &len, NULL, 0);
#else
  *buf = 0;
#endif
}

#ifdef _WIN32
#define LITE_OS_HOME "USERPROFILE"
#define LITE_PATHSEP_PATTERN "\\\\"
#define LITE_NONPATHSEP_PATTERN "[^\\\\]+"
#else
#define LITE_OS_HOME "HOME"
#define LITE_PATHSEP_PATTERN "/"
#define LITE_NONPATHSEP_PATTERN "[^/]+"
#endif

#ifdef SDL_PLATFORM_APPLE
void enable_momentum_scroll();
#ifdef MACOS_USE_BUNDLE
void set_macos_bundle_resources(lua_State *L);
#endif
#endif

#ifndef LITE_ARCH_TUPLE
  // https://learn.microsoft.com/en-us/cpp/preprocessor/predefined-macros?view=msvc-140
  #if defined(__x86_64__) || defined(_M_AMD64) || defined(__MINGW64__)
    #define ARCH_PROCESSOR "x86_64"
  #elif defined(__i386__) || defined(_M_IX86) || defined(__MINGW32__)
    #define ARCH_PROCESSOR "x86"
  #elif defined(__aarch64__) || defined(_M_ARM64) || defined (_M_ARM64EC)
    #define ARCH_PROCESSOR "aarch64"
  #elif defined(__arm__) || defined(_M_ARM)
    #define ARCH_PROCESSOR "arm"
  #endif

  #if _WIN32
    #define ARCH_PLATFORM "windows"
  #elif __linux__
    #define ARCH_PLATFORM "linux"
  #elif __FreeBSD__
    #define ARCH_PLATFORM "freebsd"
  #elif SDL_PLATFORM_APPLE
    #define ARCH_PLATFORM "darwin"
  #elif __serenity__
    #define ARCH_PLATFORM "serenity"
  #else
  #endif

  #if !defined(ARCH_PROCESSOR) || !defined(ARCH_PLATFORM)
    #error "Please define -DLITE_ARCH_TUPLE."
  #endif

  #define LITE_ARCH_TUPLE ARCH_PROCESSOR "-" ARCH_PLATFORM
#endif


static int app_argc = 0;
static char **app_argv = NULL;
static lua_State *app_L = NULL;
static int app_has_restarted = 0;
static SDL_ThreadID app_main_thread_id = 0;


static int initialize_lua(int argc, char **argv) {
  if (app_L) {
    lua_close(app_L);
    rencache_invalidate();
  }
  app_L = luaL_newstate();
  if (!app_L) return -1;

  luaL_openlibs(app_L);
  api_load_libs(app_L);

  lua_newtable(app_L);
  for (int i = 0; i < argc; i++) {
    lua_pushstring(app_L, argv[i]);
    lua_rawseti(app_L, -2, i + 1);
  }
  lua_setglobal(app_L, "ARGS");

  lua_pushstring(app_L, SDL_GetPlatform());
  lua_setglobal(app_L, "PLATFORM");

  lua_pushstring(app_L, LITE_ARCH_TUPLE);
  lua_setglobal(app_L, "ARCH");
  
  lua_pushboolean(app_L, app_has_restarted);
  lua_setglobal(app_L, "RESTARTED");

  char exename[2048];
  get_exe_filename(exename, sizeof(exename));
  if (*exename) {
    lua_pushstring(app_L, exename);
  } else {
    // get_exe_filename failed
    lua_pushstring(app_L, argv[0]);
  }
  lua_setglobal(app_L, "EXEFILE");

#ifdef MACOS_USE_BUNDLE
  set_macos_bundle_resources(app_L);
#endif

  // a function to catch error and send them to files
  const char *app_catch_error_code = \
  "function app_catch_error(cb, ...)\n"
  "  local res = { xpcall(cb, function(err)\n"
  "    local error_path = 'error.txt'\n"
  "    io.stdout:write(debug.traceback(coroutine.running(), 'Error: '..tostring(err), 1)..'\\n')\n"
  "    io.stdout:flush()\n"
  "    if core and core.on_error then\n"
  "      error_path = USERDIR .. PATHSEP .. error_path\n"
  "      pcall(core.on_error, err)\n"
  "    else\n"
  "      local fp = io.open(error_path, 'wb')\n"
  "      fp:write(debug.traceback(coroutine.running(), 'Error: '..tostring(err), 1)..'\\n')\n"
  "      fp:close()\n"
  "      error_path = system.absolute_path(error_path)\n"
  "    end\n"
  "    system.show_fatal_error('Lite XL internal error',\n"
  "      'An internal error occurred in a critical part of the application.\\n\\n'..\n"
  "      'Error: '..tostring(err)..'\\n\\n'..\n"
  "      'Details can be found in \\\"'..error_path..'\\\"')\n"
  "    os.exit(1)\n"
  "  end, ...) }\n"
  "  return table.unpack(res, 2)\n"
  "end\n";

  if (luaL_loadstring(app_L, app_catch_error_code) != LUA_OK || lua_pcall(app_L, 0, 0, 0) != LUA_OK) {
    fprintf(stderr, "internal error when starting the application\n");
    return -1;
  }

  const char *init_lite_code = \
  "core = {}\n"
  "local os_exit = os.exit\n"
  "os.exit = function(code, close)\n"
  "  os_exit(code, close == nil and true or close)\n"
  "end\n"
  "app_catch_error(function()\n"
  "  local match = require('utf8extra').match\n"
  "  HOME = os.getenv('" LITE_OS_HOME "')\n"
  "  local exedir = match(EXEFILE, '^(.*)" LITE_PATHSEP_PATTERN LITE_NONPATHSEP_PATTERN "$')\n"
  "  local prefix = os.getenv('LITE_PREFIX') or match(exedir, '^(.*)" LITE_PATHSEP_PATTERN "bin$')\n"
  "  dofile((MACOS_RESOURCES or (prefix and prefix .. '/share/lite-xl' or exedir .. '/data')) .. '/core/start.lua')\n"
  "  core = require(os.getenv('LITE_XL_RUNTIME') or 'core')\n"
  "  core.init()\n"
  "end)\n";
   
  if (luaL_loadstring(app_L, init_lite_code) || lua_pcall(app_L, 0, 0, 0) != LUA_OK) {
    fprintf(stderr, "internal error when starting the application\n");
    return -1;
  }

  return 0;
}


static int safe_call(lua_State *L, const char *glb, const char *name, int nargs, int nresult) {
  lua_getglobal(L, "app_catch_error");
  lua_getglobal(L, glb);
  lua_getfield(L, -1, name);
  lua_remove(L, lua_gettop(L) - 1); // remove glb
  lua_rotate(L, lua_gettop(L) - nargs - 1, 2);
  int ret = lua_pcall(L, nargs + 1, nresult, 0);
  if (ret != LUA_OK) lua_pop(L, 1);
  return ret;
}


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


// soft-required by f_poll_event until that is removed...
int main_push_event(lua_State *L, SDL_Event *e) {
  char buf[16];
  float mx, my;
  int w, h;
  SDL_Event event_plus;

  switch (e->type) {
    case SDL_EVENT_QUIT:
      lua_pushstring(L, "quit");
      return 1;

    case SDL_EVENT_WINDOW_RESIZED:
      {
        RenWindow* window_renderer = ren_find_window_from_id(e->window.windowID);
        ren_resize_window(window_renderer);
        lua_pushstring(L, "resized");
        /* The size below will be in points. */
        lua_pushinteger(L, e->window.data1);
        lua_pushinteger(L, e->window.data2);
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
      SDL_FlushEvent(SDL_EVENT_KEY_DOWN);
      return 0;


    case SDL_EVENT_DROP_FILE:
      {
        RenWindow* window_renderer = ren_find_window_from_id(e->drop.windowID);
        SDL_GetMouseState(&mx, &my);
        lua_pushstring(L, "filedropped");
        lua_pushstring(L, e->drop.data);
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
      if ((e->key.key == SDLK_W) && (e->key.mod & SDL_KMOD_GUI)) {
        SDL_FlushEvent(SDL_EVENT_QUIT);
      }
#endif
      lua_pushstring(L, "keypressed");
      lua_pushstring(L, get_key_name(e, buf));
      return 2;

    case SDL_EVENT_KEY_UP:
#ifdef __APPLE__
      /* on macos command+w will close the current window
      ** we want to flush this event and let the keymapper
      ** handle this key combination.
      ** Thanks to mathewmariani, taken from his lite-macos github repository. */
      if ((e->key.key == SDLK_W) && (e->key.mod & SDL_KMOD_GUI)) {
        SDL_FlushEvent(SDL_EVENT_QUIT);
      }
#endif
      lua_pushstring(L, "keyreleased");
      lua_pushstring(L, get_key_name(e, buf));
      return 2;

    case SDL_EVENT_TEXT_INPUT:
      lua_pushstring(L, "textinput");
      lua_pushstring(L, e->text.text);
      return 2;

    case SDL_EVENT_TEXT_EDITING:
      lua_pushstring(L, "textediting");
      lua_pushstring(L, e->edit.text);
      lua_pushinteger(L, e->edit.start);
      lua_pushinteger(L, e->edit.length);
      return 4;

    case SDL_EVENT_MOUSE_BUTTON_DOWN:
      {
        if (e->button.button == 1) { SDL_CaptureMouse(1); }
        RenWindow* window_renderer = ren_find_window_from_id(e->button.windowID);
        lua_pushstring(L, "mousepressed");
        lua_pushstring(L, button_name(e->button.button));
        lua_pushinteger(L, e->button.x * window_renderer->scale_x);
        lua_pushinteger(L, e->button.y * window_renderer->scale_y);
        lua_pushinteger(L, e->button.clicks);
        return 5;
      }

    case SDL_EVENT_MOUSE_BUTTON_UP:
      {
        if (e->button.button == 1) { SDL_CaptureMouse(0); }
        RenWindow* window_renderer = ren_find_window_from_id(e->button.windowID);
        lua_pushstring(L, "mousereleased");
        lua_pushstring(L, button_name(e->button.button));
        lua_pushinteger(L, e->button.x * window_renderer->scale_x);
        lua_pushinteger(L, e->button.y * window_renderer->scale_y);
        return 4;
      }

    case SDL_EVENT_MOUSE_MOTION:
      {
        SDL_PumpEvents();
        while (SDL_PeepEvents(&event_plus, 1, SDL_GETEVENT, SDL_EVENT_MOUSE_MOTION, SDL_EVENT_MOUSE_MOTION) > 0) {
          e->motion.x = event_plus.motion.x;
          e->motion.y = event_plus.motion.y;
          e->motion.xrel += event_plus.motion.xrel;
          e->motion.yrel += event_plus.motion.yrel;
        }
        RenWindow* window_renderer = ren_find_window_from_id(e->motion.windowID);
        lua_pushstring(L, "mousemoved");
        lua_pushinteger(L, e->motion.x * window_renderer->scale_x);
        lua_pushinteger(L, e->motion.y * window_renderer->scale_y);
        lua_pushinteger(L, e->motion.xrel * window_renderer->scale_x);
        lua_pushinteger(L, e->motion.yrel * window_renderer->scale_y);
        return 5;
      }

    case SDL_EVENT_MOUSE_WHEEL:
      lua_pushstring(L, "mousewheel");
      lua_pushinteger(L, e->wheel.y);
      lua_pushinteger(L, -e->wheel.x);
      return 3;

    case SDL_EVENT_FINGER_DOWN:
      {
        RenWindow* window_renderer = ren_find_window_from_id(e->tfinger.windowID);
        SDL_GetWindowSize(window_renderer->window, &w, &h);

        lua_pushstring(L, "touchpressed");
        lua_pushinteger(L, (lua_Integer)(e->tfinger.x * w));
        lua_pushinteger(L, (lua_Integer)(e->tfinger.y * h));
        lua_pushinteger(L, e->tfinger.fingerID);
        return 4;
      }

    case SDL_EVENT_FINGER_UP:
      {
        RenWindow* window_renderer = ren_find_window_from_id(e->tfinger.windowID);
        SDL_GetWindowSize(window_renderer->window, &w, &h);

        lua_pushstring(L, "touchreleased");
        lua_pushinteger(L, (lua_Integer)(e->tfinger.x * w));
        lua_pushinteger(L, (lua_Integer)(e->tfinger.y * h));
        lua_pushinteger(L, e->tfinger.fingerID);
        return 4;
      }

    case SDL_EVENT_FINGER_MOTION:
      {
        // TODO: will this work?
        SDL_PumpEvents();
        while (SDL_PeepEvents(&event_plus, 1, SDL_GETEVENT, SDL_EVENT_FINGER_MOTION, SDL_EVENT_FINGER_MOTION) > 0) {
          e->tfinger.x = event_plus.tfinger.x;
          e->tfinger.y = event_plus.tfinger.y;
          e->tfinger.dx += event_plus.tfinger.dx;
          e->tfinger.dy += event_plus.tfinger.dy;
        }
        RenWindow* window_renderer = ren_find_window_from_id(e->tfinger.windowID);
        SDL_GetWindowSize(window_renderer->window, &w, &h);

        lua_pushstring(L, "touchmoved");
        lua_pushinteger(L, (lua_Integer)(e->tfinger.x * w));
        lua_pushinteger(L, (lua_Integer)(e->tfinger.y * h));
        lua_pushinteger(L, (lua_Integer)(e->tfinger.dx * w));
        lua_pushinteger(L, (lua_Integer)(e->tfinger.dy * h));
        lua_pushinteger(L, e->tfinger.fingerID);
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
        lua_pushstring(L, e->type == SDL_EVENT_WILL_ENTER_FOREGROUND ? "enteringforeground" : "enteredforeground");
        return 1;
      }
    case SDL_EVENT_WILL_ENTER_BACKGROUND:
      lua_pushstring(L, "enteringbackground");
      return 1;
    case SDL_EVENT_DID_ENTER_BACKGROUND:
      lua_pushstring(L, "enteredbackground");
      return 1;
    
    return 0;
  }
  return 0;
}


SDL_AppResult SDL_AppInit(void **appstate, int argc, char **argv) {
  #ifndef _WIN32
    signal(SIGPIPE, SIG_IGN);
  #endif
  
  /* This hint tells SDL to respect borderless window as a normal window.
    * For example, the window will sit right on top of the taskbar instead
    * of obscuring it. */
  SDL_SetHint("SDL_BORDERLESS_WINDOWED_STYLE", "1");
  /* This hint tells SDL to allow the user to resize a borderless windoow.
  ** It also enables aero-snap on Windows apparently. */
  SDL_SetHint("SDL_BORDERLESS_RESIZABLE_STYLE", "1");
  SDL_SetHint(SDL_HINT_MOUSE_DOUBLE_CLICK_RADIUS, "4");
  SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
  SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");
  SDL_SetHint(SDL_HINT_IME_IMPLEMENTED_UI, "1");
  SDL_SetHint(SDL_HINT_RENDER_DRIVER, "software");

  if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
    fprintf(stderr, "Error initializing SDL: %s", SDL_GetError());
    return SDL_APP_FAILURE;
  }
  SDL_EnableScreenSaver();
  SDL_SetEventEnabled(SDL_EVENT_DROP_FILE, true);
  SDL_SetEventEnabled(SDL_EVENT_TEXT_INPUT, true);
  SDL_SetEventEnabled(SDL_EVENT_TEXT_EDITING, true);
  
#ifdef SDL_PLATFORM_APPLE
  enable_momentum_scroll();
#endif
  
  app_main_thread_id = SDL_GetCurrentThreadID();
  // usually these addresses don't change...
  app_argc = argc;
  app_argv = argv;
  
  if (ren_init() != 0) {
    fprintf(stderr, "Error initializing renderer: %s\n", SDL_GetError());
    return SDL_APP_FAILURE;
  }

  return initialize_lua(argc, argv) == 0 ? SDL_APP_CONTINUE : SDL_APP_FAILURE;
}
  

SDL_AppResult SDL_AppIterate(void *appstate) {
  SDL_AppResult result = SDL_APP_CONTINUE;

  if (safe_call(app_L, "core", "run", 0, 2) != LUA_OK) {
    fprintf(stderr, "critical application error\n");
    result = SDL_APP_FAILURE;
  } else {
    if (lua_toboolean(app_L, -2)) result = SDL_APP_CONTINUE; // should not exit
    else if (!lua_toboolean(app_L, -1)) result = SDL_APP_SUCCESS; // should exit w/o restart
    else { // restart
      initialize_lua(app_argc, app_argv);
      app_has_restarted = 1;
      result = SDL_APP_CONTINUE;
    }
  }

  return result;
}


SDL_AppResult SDL_AppEvent(void *appstate, SDL_Event *event) {
  if (SDL_GetCurrentThreadID() != app_main_thread_id) {
    // currently SDL specifies this can be called from any thread, which will be somewhat dangerous,
    // because we don't want to run window operation on non-UI thread. Some systems hate this.
    fprintf(stderr, "WARNING: event from non-main thread (0x%llx) detected, ignoring this event\n", SDL_GetCurrentThreadID());
    return SDL_APP_CONTINUE;
  }

  SDL_AppResult result = SDL_APP_CONTINUE;
  int args = main_push_event(app_L, event);
  if (args && safe_call(app_L, "core", "on_event", args, 0) != LUA_OK) {
    fprintf(stderr, "critical application error\n");
    result = SDL_APP_FAILURE;
  }

  return result;
}


void SDL_AppQuit(void *appstate, SDL_AppResult result) {
  if (app_L) lua_close(app_L);
  ren_free();
}