#define SDL_MAIN_USE_CALLBACKS

#include <stdio.h>
#include <stdlib.h>
#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include "api/api.h"
#include "rencache.h"
#include "renderer.h"
#include "state.h"

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

static bool init_lua(struct app_state* state)
{
  lua_State *L = luaL_newstate();
  state->L = L;

  luaL_openlibs(L);
  api_load_libs(L);


  lua_newtable(L);
  for (int i = 0; i < state->argc; i++) {
    lua_pushstring(L, state->argv[i]);
    lua_rawseti(L, -2, i + 1);
  }
  lua_setglobal(L, "ARGS");

  lua_pushstring(L, SDL_GetPlatform());
  lua_setglobal(L, "PLATFORM");

  lua_pushstring(L, LITE_ARCH_TUPLE);
  lua_setglobal(L, "ARCH");
  
  lua_pushboolean(L, state->has_restarted);
  lua_setglobal(L, "RESTARTED");

  char exename[2048];
  get_exe_filename(exename, sizeof(exename));
  if (*exename) {
    lua_pushstring(L, exename);
  } else {
    // get_exe_filename failed
    lua_pushstring(L, state->argv[0]);
  }
  lua_setglobal(L, "EXEFILE");

  const char *init_lite_code = \
    "core = {}\n"
    "local os_exit = os.exit\n"
    "os.exit = function(code, close)\n"
    "  os_exit(code, close == nil and true or close)\n"
    "end\n"
    "local match = require('utf8extra').match\n"
    "HOME = os.getenv('" LITE_OS_HOME "')\n"
    "local exedir = match(EXEFILE, '^(.*)" LITE_PATHSEP_PATTERN LITE_NONPATHSEP_PATTERN "$')\n"
    "local prefix = os.getenv('LITE_PREFIX') or match(exedir, '^(.*)" LITE_PATHSEP_PATTERN "bin$')\n"
    "dofile((MACOS_RESOURCES or (prefix and prefix .. '/share/lite-xl' or exedir .. '/data')) .. '/core/start.lua')\n"
    "core = require(os.getenv('LITE_XL_RUNTIME') or 'core')\n"
    "core.init()\n";

  if (luaL_loadstring(state->L, init_lite_code)) {
    fprintf(stderr, "internal error when initailizing the application\n");
    return false;
  }

  if (lua_pcall(state->L, 0, 1, 0) != 0)
  {
    char err_prelude[] = "An internal error occured while initializing the application\n\n";
    char* err_string = lua_tostring(state->L, -1);

    char *buf = SDL_calloc(sizeof(err_prelude) + strlen(err_string) + 1, sizeof(char));

    sprintf(buf, "An internal error occured while initializing the application\n\n%s", err_string);
    SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "Lite XL", buf, NULL);

    SDL_free(buf);
    return false;
  }

  return true;
}

SDL_AppResult SDL_AppInit(void **appstate, int argc, char **argv)
{

#ifndef _WIN32
  signal(SIGPIPE, SIG_IGN);
#endif

  if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
    fprintf(stderr, "Error initializing SDL: %s", SDL_GetError());
    exit(1);
  }
  SDL_EnableScreenSaver();
  SDL_SetEventEnabled(SDL_EVENT_DROP_FILE, true);
  atexit(SDL_Quit);

  SDL_SetHint(SDL_HINT_VIDEO_X11_NET_WM_BYPASS_COMPOSITOR, "0");
  SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");
  SDL_SetHint(SDL_HINT_IME_IMPLEMENTED_UI, "1");
  SDL_SetHint(SDL_HINT_RENDER_DRIVER, "software");
  // this acts as a sane default and will be overwitten by config.fps
  SDL_SetHint(SDL_HINT_MAIN_CALLBACK_RATE, "60");

  /* This hint tells SDL to respect borderless window as a normal window.
  ** For example, the window will sit right on top of the taskbar instead
  ** of obscuring it. */
  SDL_SetHint("SDL_BORDERLESS_WINDOWED_STYLE", "1");
  /* This hint tells SDL to allow the user to resize a borderless windoow.
  ** It also enables aero-snap on Windows apparently. */
  SDL_SetHint("SDL_BORDERLESS_RESIZABLE_STYLE", "1");
  SDL_SetHint(SDL_HINT_MOUSE_DOUBLE_CLICK_RADIUS, "4");

  if (ren_init() != 0) {
    fprintf(stderr, "Error initializing renderer: %s\n", SDL_GetError());
  }

  struct app_state *state = (struct app_state *)SDL_calloc(1, sizeof(struct app_state));
  if (!state)
    return SDL_APP_FAILURE;


  *appstate = state;
  state->has_restarted = 0;
  state->argc = argc;
  state->argv = argv;
  if (!init_lua(state))
    return SDL_APP_FAILURE;

#ifdef SDL_PLATFORM_APPLE
  enable_momentum_scroll();
  #ifdef MACOS_USE_BUNDLE
    set_macos_bundle_resources(state->L);
  #endif
#endif
  SDL_SetEventEnabled(SDL_EVENT_TEXT_INPUT, true);
  SDL_SetEventEnabled(SDL_EVENT_TEXT_EDITING, true);

  return SDL_APP_CONTINUE;
}

SDL_AppResult SDL_AppIterate(void *appstate)
{
  struct app_state *state = (struct app_state*)appstate;

  lua_getglobal(state->L, "core");
  lua_getfield(state->L, -1, "step");

  lua_pcall(state->L, 0, 1, 0);
  bool should_continue = lua_toboolean(state->L, -1);
  lua_pop(state->L, 1);
  if (should_continue)
    return SDL_APP_CONTINUE;

  // check if we are suppose to restart
  lua_getglobal(state->L, "core");
  lua_getfield(state->L, -1, "restart_request");
  lua_remove(state->L, -2);

  bool restart_request = lua_toboolean(state->L, -1);
  lua_pop(state->L, 1);

  if (restart_request)
  {
    lua_close(state->L);
    rencache_invalidate();
    state->has_restarted = 1;
    if (!init_lua(state))
      return SDL_APP_FAILURE;

    return SDL_APP_CONTINUE;
  }

  return SDL_APP_SUCCESS;
}

void SDL_AppQuit(void *appstate, SDL_AppResult result)
{
  struct app_state *state = (struct app_state*)appstate;

  lua_close(state->L);
  ren_free();

}