#include <stdio.h>
#include <stdlib.h>
#include <SDL.h>
#include "api/api.h"
#include "rencache.h"
#include "renderer.h"

#include <signal.h>

#ifdef _WIN32
  #include <windows.h>
#elif defined(__linux__)
  #include <unistd.h>
#elif defined(__APPLE__)
  #include <mach-o/dyld.h>
#elif defined(__FreeBSD__)
  #include <sys/sysctl.h>
#endif


static SDL_Window *window;

static double get_scale(void) {
#ifndef __APPLE__
  float dpi;
  if (SDL_GetDisplayDPI(0, NULL, &dpi, NULL) == 0)
    return dpi / 96.0;
#endif
  return 1.0;
}


static void get_exe_filename(char *buf, int sz) {
#if _WIN32
  int len = GetModuleFileName(NULL, buf, sz - 1);
  buf[len] = '\0';
#elif __linux__
  char path[] = "/proc/self/exe";
  ssize_t len = readlink(path, buf, sz - 1);
  if (len > 0)
    buf[len] = '\0';
#elif __APPLE__
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


static void init_window_icon(void) {
#if !defined(_WIN32) && !defined(__APPLE__)
  #include "../resources/icons/icon.inl"
  (void) icon_rgba_len; /* unused */
  SDL_Surface *surf = SDL_CreateRGBSurfaceFrom(
    icon_rgba, 64, 64,
    32, 64 * 4,
    0x000000ff,
    0x0000ff00,
    0x00ff0000,
    0xff000000);
  SDL_SetWindowIcon(window, surf);
  SDL_FreeSurface(surf);
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

#ifdef __APPLE__
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
  #elif __APPLE__
    #define ARCH_PLATFORM "darwin"
  #endif

  #if !defined(ARCH_PROCESSOR) || !defined(ARCH_PLATFORM)
    #error "Please define -DLITE_ARCH_TUPLE."
  #endif

  #define LITE_ARCH_TUPLE ARCH_PROCESSOR "-" ARCH_PLATFORM
#endif

int main(int argc, char **argv) {
#ifndef _WIN32
  signal(SIGPIPE, SIG_IGN);
#endif

  if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
    fprintf(stderr, "Error initializing sdl: %s", SDL_GetError());
    exit(1);
  }
  SDL_EnableScreenSaver();
  SDL_EventState(SDL_DROPFILE, SDL_ENABLE);
  atexit(SDL_Quit);

#ifdef SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR /* Available since 2.0.8 */
  SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
#endif
#if SDL_VERSION_ATLEAST(2, 0, 5)
  SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");
#endif
#if SDL_VERSION_ATLEAST(2, 0, 18)
  SDL_SetHint(SDL_HINT_IME_SHOW_UI, "1");
#endif
#if SDL_VERSION_ATLEAST(2, 0, 22)
  SDL_SetHint(SDL_HINT_IME_SUPPORT_EXTENDED_TEXT, "1");
#endif

#if SDL_VERSION_ATLEAST(2, 0, 8)
  /* This hint tells SDL to respect borderless window as a normal window.
  ** For example, the window will sit right on top of the taskbar instead
  ** of obscuring it. */
  SDL_SetHint("SDL_BORDERLESS_WINDOWED_STYLE", "1");
#endif
#if SDL_VERSION_ATLEAST(2, 0, 12)
  /* This hint tells SDL to allow the user to resize a borderless windoow.
  ** It also enables aero-snap on Windows apparently. */
  SDL_SetHint("SDL_BORDERLESS_RESIZABLE_STYLE", "1");
#endif
#if SDL_VERSION_ATLEAST(2, 0, 9)
  SDL_SetHint("SDL_MOUSE_DOUBLE_CLICK_RADIUS", "4");
#endif

  SDL_DisplayMode dm;
  SDL_GetCurrentDisplayMode(0, &dm);

  window = SDL_CreateWindow(
    "", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, dm.w * 0.8, dm.h * 0.8,
    SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_HIDDEN);
  init_window_icon();
  if (!window) {
    fprintf(stderr, "Error creating lite-xl window: %s", SDL_GetError());
    exit(1);
  }
  ren_init(window);

  lua_State *L;
init_lua:
  L = luaL_newstate();
  luaL_openlibs(L);
  api_load_libs(L);


  lua_newtable(L);
  for (int i = 0; i < argc; i++) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i + 1);
  }
  lua_setglobal(L, "ARGS");

  lua_pushstring(L, SDL_GetPlatform());
  lua_setglobal(L, "PLATFORM");

  lua_pushstring(L, LITE_ARCH_TUPLE);
  lua_setglobal(L, "ARCH");

  lua_pushnumber(L, get_scale());
  lua_setglobal(L, "SCALE");

  char exename[2048];
  get_exe_filename(exename, sizeof(exename));
  if (*exename) {
    lua_pushstring(L, exename);
  } else {
    // get_exe_filename failed
    lua_pushstring(L, argv[0]);
  }
  lua_setglobal(L, "EXEFILE");

#ifdef __APPLE__
  enable_momentum_scroll();
  #ifdef MACOS_USE_BUNDLE
    set_macos_bundle_resources(L);
  #endif
#endif

  const char *init_lite_code = \
    "local core\n"
    "xpcall(function()\n"
    "  HOME = os.getenv('" LITE_OS_HOME "')\n"
    "  local exedir = EXEFILE:match('^(.*)" LITE_PATHSEP_PATTERN LITE_NONPATHSEP_PATTERN "$')\n"
    "  local prefix = os.getenv('LITE_PREFIX') or exedir:match('^(.*)" LITE_PATHSEP_PATTERN "bin$')\n"
    "  dofile((MACOS_RESOURCES or (prefix and prefix .. '/share/lite-xl' or exedir .. '/data')) .. '/core/start.lua')\n"
    "  core = require(os.getenv('LITE_XL_RUNTIME') or 'core')\n"
    "  core.init()\n"
    "  core.run()\n"
    "end, function(err)\n"
    "  local error_dir\n"
    "  io.stdout:write('Error: '..tostring(err)..'\\n')\n"
    "  io.stdout:write(debug.traceback(nil, 4)..'\\n')\n"
    "  if core and core.on_error then\n"
    "    error_dir=USERDIR\n"
    "    pcall(core.on_error, err)\n"
    "  else\n"
    "    error_dir=system.absolute_path('.')\n"
    "    local fp = io.open('error.txt', 'wb')\n"
    "    fp:write('Error: ' .. tostring(err) .. '\\n')\n"
    "    fp:write(debug.traceback(nil, 4)..'\\n')\n"
    "    fp:close()\n"
    "  end\n"
    "  system.show_fatal_error('Lite XL internal error',\n"
    "    'An internal error occurred in a critical part of the application.\\n\\n'..\n"
    "    'Please verify the file \\\"error.txt\\\" in the directory '..error_dir)\n"
    "  os.exit(1)\n"
    "end)\n"
    "return core and core.restart_request\n";

  if (luaL_loadstring(L, init_lite_code)) {
    fprintf(stderr, "internal error when starting the application\n");
    exit(1);
  }
  lua_pcall(L, 0, 1, 0);
  if (lua_toboolean(L, -1)) {
    lua_close(L);
    rencache_invalidate();
    goto init_lua;
  }

  lua_close(L);
  ren_free_window_resources(&window_renderer);

  return EXIT_SUCCESS;
}
