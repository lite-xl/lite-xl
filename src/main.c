#include <stdio.h>
#include <stdlib.h>
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include "api/api.h"
#include "rencache.h"
#include "renderer.h"
#include "custom_events.h"

#include <signal.h>

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
  wchar_t *buf_w = SDL_malloc(sizeof(wchar_t) * sz);
  if (buf_w) {
    len = GetModuleFileNameW(NULL, buf_w, sz - 1);
    buf_w[len] = L'\0';
    // if the conversion failed we'll empty the string
    if (!WideCharToMultiByte(CP_UTF8, 0, buf_w, -1, buf, sz, NULL, NULL))
      buf[0] = '\0';
    SDL_free(buf_w);
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

int main(int argc, char **argv) {
#ifndef _WIN32
  signal(SIGPIPE, SIG_IGN);
#endif

  SDL_SetAppMetadata("Lite XL", LITE_PROJECT_VERSION_STR, "com.lite_xl.LiteXL");
  if (!SDL_Init(SDL_INIT_EVENTS)) {
    fprintf(stderr, "Error initializing sdl: %s", SDL_GetError());
    exit(1);
  }
  SDL_SetEventEnabled(SDL_EVENT_DROP_FILE, true);
  atexit(SDL_Quit);
  
  if (ren_init() != 0) {
    fprintf(stderr, "Error initializing renderer: %s\n", SDL_GetError());
  }

  if (!init_custom_events()) {
    fprintf(stderr, "Error initializing custom events: %s\n", SDL_GetError());
    exit(1);
  }

  int has_restarted = 0;
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
  
  lua_pushboolean(L, has_restarted);
  lua_setglobal(L, "RESTARTED");

  char exename[2048];
  get_exe_filename(exename, sizeof(exename));
  if (*exename) {
    lua_pushstring(L, exename);
  } else {
    // get_exe_filename failed
    lua_pushstring(L, argv[0]);
  }
  lua_setglobal(L, "EXEFILE");

#ifdef SDL_PLATFORM_APPLE
  enable_momentum_scroll();
  #ifdef MACOS_USE_BUNDLE
    set_macos_bundle_resources(L);
  #endif
#endif
  SDL_SetEventEnabled(SDL_EVENT_TEXT_INPUT, true);
  SDL_SetEventEnabled(SDL_EVENT_TEXT_EDITING, true);

  const char *init_lite_code = \
    "local core\n"
    "local os_exit = os.exit\n"
    "os.exit = function(code, close)\n"
    "  os_exit(code, close == nil and true or close)\n"
    "end\n"
    "xpcall(function()\n"
    "  local match = require('utf8extra').match\n"
    "  HOME = os.getenv('" LITE_OS_HOME "')\n"
    "  local exedir = match(EXEFILE, '^(.*)" LITE_PATHSEP_PATTERN LITE_NONPATHSEP_PATTERN "$')\n"
    "  local prefix = os.getenv('LITE_PREFIX') or match(exedir, '^(.*)" LITE_PATHSEP_PATTERN "bin$')\n"
    "  dofile((MACOS_RESOURCES or (prefix and prefix .. '/share/lite-xl' or exedir .. '/data')) .. '/core/start.lua')\n"
    "  core = require(os.getenv('LITE_XL_RUNTIME') or 'core')\n"
    "  core.init()\n"
    "  core.run()\n"
    "end, function(err)\n"
    "  local error_path = 'error.txt'\n"
    "  io.stdout:write('Error: '..tostring(err)..'\\n')\n"
    "  io.stdout:write(debug.traceback(nil, 2)..'\\n')\n"
    "  if core and core.on_error then\n"
    "    error_path = USERDIR .. PATHSEP .. error_path\n"
    "    pcall(core.on_error, err)\n"
    "  else\n"
    "    local fp = io.open(error_path, 'wb')\n"
    "    fp:write('Error: ' .. tostring(err) .. '\\n')\n"
    "    fp:write(debug.traceback(nil, 2)..'\\n')\n"
    "    fp:close()\n"
    "    error_path = system.absolute_path(error_path)\n"
    "  end\n"
    "  system.show_fatal_error('Lite XL internal error',\n"
    "    'An internal error occurred in a critical part of the application.\\n\\n'..\n"
    "    'Error: '..tostring(err)..'\\n\\n'..\n"
    "    'Details can be found in \\\"'..error_path..'\\\"')\n"
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
    has_restarted = 1;
    goto init_lua;
  }

  lua_close(L);

  // At this point we're not going to call the event loop anymore,
  // so we can free the custom events.
  free_custom_events();

  ren_free();

  return EXIT_SUCCESS;
}
