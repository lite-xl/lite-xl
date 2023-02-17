#include "api.h"

#ifdef _WIN32

#if (LUA_VERSION_NUM < 503)
#error "This extension will not work with Lua below version 5.3 or LuaJIT."
#endif

#include "../utfconv.h"

#include <io.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>

#define IO_PREFIX "__patch_io__"

static int close_file(lua_State *L) {
  luaL_Stream *f = luaL_checkudata(L, 1, LUA_FILEHANDLE);
  return luaL_fileresult(L, fclose(f->f) == 0, NULL);
}

static int close_popen(lua_State *L) {
  luaL_Stream *f = luaL_checkudata(L, 1, LUA_FILEHANDLE);
  return luaL_fileresult(L, _pclose(f->f) == 0, NULL);
}

/**
 * This code is adapted from Lua 5.4.
 * FIXME:cannot get L_MODEEXIT on runtime.
 *
 * Change this macro to accept other modes for 'fopen' besides
 * the standard ones.
 */
#if !defined(l_checkmode)

/* accepted extensions to 'mode' in 'fopen' */
#if !defined(L_MODEEXT)
#define L_MODEEXT       "b"
#endif

/* Check whether 'mode' matches '[rwa]%+?[L_MODEEXT]*' */
static int l_checkmode (const char *mode) {
  return (*mode != '\0' && strchr("rwa", *(mode++)) != NULL &&
         (*mode != '+' || (++mode, 1)) &&  /* skip if char is '+' */
         (strspn(mode, L_MODEEXT) == strlen(mode)));  /* check extensions */
}

#endif

static int utf8_io_open(lua_State *L) {
  int retval = 0;
  FILE *f = NULL;
  luaL_Stream *stream = NULL;
  wchar_t *filename_w = NULL, *mode_w = NULL;
  const char *filename = luaL_checkstring(L, 1);
  const char *mode = luaL_optstring(L, 2, "r");
  luaL_argcheck(L, l_checkmode(mode), 2, "invalid mode");

  if (!(filename_w = utfconv_utf8towc(filename)) || !(mode_w = utfconv_utf8towc(mode))) {
    retval = -1;
    errno = EINVAL;
    goto cleanup;
  }

  /**
   * Nasty Windows hack: if mode is w then we need to use CreateFile, OPEN_ALWAYS,
   * FILE_ATTRIBUTE_NORMAL | FILE_ATTRIBUTE_HIDDEN, and manually truncate.
   * FILE_ATTRIBUTE_NORMAL | FILE_ATTRIBUTE_HIDDEN is documented to be invalid, but when
   * combined with OPEN_ALWAYS will always open ANY file or create one if it doesn't exist.
   * IT DOES NOT MAKE AN EXISTING FILE HIDDEN. If CreateFile created a new file, we will
   * immediately unhide it.
   *
   * FIXME: potential race condition between GetAttribute and SetAttribute
   */
  if (mode[0] == 'w') {
    HANDLE f_handle = CreateFileW(filename_w,
                                  GENERIC_WRITE,
                                  FILE_SHARE_READ | FILE_SHARE_WRITE,
                                  NULL,
                                  OPEN_ALWAYS, // functionally equivalent to r+
                                  FILE_ATTRIBUTE_NORMAL | FILE_ATTRIBUTE_HIDDEN,
                                  NULL);

    if (f_handle == INVALID_HANDLE_VALUE) {
      retval = -1;
      errno = EINVAL; // TODO: better error messages?
      goto cleanup;
    }

    // file is newly created, unset hidden flag
    if (GetLastError() == 0) {
      // last chance to look at me hector (attributes)
      FILE_BASIC_INFO basic_info = { 0 };
      if (!GetFileInformationByHandleEx(f_handle, FileBasicInfo, (void *) &basic_info, sizeof(FILE_BASIC_INFO))) {
        retval = -1;
        errno = EINVAL; // TODO: better error messages
        goto cleanup;
      }
      // unset hidden
      basic_info.FileAttributes &= ~(FILE_ATTRIBUTE_HIDDEN);
      if (!SetFileInformationByHandle(f_handle, FileBasicInfo, (void *) &basic_info, sizeof(FILE_BASIC_INFO))) {
        retval = -1;
        errno = EINVAL; // TODO: better error messages
        goto cleanup;
      }
    }
    // truncate the file
    FILE_END_OF_FILE_INFO eof_info = { 0 };
    if (!SetFileInformationByHandle(f_handle, FileEndOfFileInfo, (void *) &eof_info, sizeof(FILE_END_OF_FILE_INFO))) {
      retval = -1;
      errno = EINVAL; // TODO: better error messages
      goto cleanup;
    }
    // now we need to create a fileno and an associated FILE*
    int fd = _open_osfhandle((intptr_t) f_handle, strchr(mode + 1, 'b') != NULL ? _O_TEXT : 0);
    if (fd == -1) {
      retval = -1;
      goto cleanup;
    }
    // convert fd to actual FILE*
    f = _wfdopen(fd, mode_w);
  } else {
    // use _wfopen
    f = _wfopen(filename_w, mode_w);
  }

  if (!f) {
    retval = -1;
    goto cleanup;
  }

  stream = lua_newuserdata(L, sizeof(luaL_Stream));
  stream->f = f;
  stream->closef = &close_file;

  luaL_setmetatable(L, LUA_FILEHANDLE);
  retval = 1;

cleanup:
  free(filename_w);
  free(mode_w);
  if (retval == -1) {
    if (f) fclose(f);
    return luaL_fileresult(L, 0, filename);
  }
  return retval;
}

/**
 * The code below is from Lua 5.4.
 * FIXME: no way to get l_checkmodep on runtime
 */
#if !defined(l_checkmodep)
/* Windows accepts "[rw][bt]?" as valid modes */
#define l_checkmodep(m) ((m[0] == 'r' || m[0] == 'w') && \
  (m[1] == '\0' || ((m[1] == 'b' || m[1] == 't') && m[2] == '\0')))
#endif

static int utf8_io_popen(lua_State *L) {
  const char *filename = luaL_checkstring(L, 1);
  const char *mode = luaL_optstring(L, 2, "r");
  luaL_argcheck(L, l_checkmodep(mode), 2, "invalid mode");

  wchar_t *filename_w = utfconv_utf8towc(filename);
  wchar_t *mode_w = utfconv_utf8towc(mode);
  if (!filename_w || !mode_w) {
    free(filename_w);
    free(mode_w);
    errno = EINVAL;
    return luaL_fileresult(L, 0, filename);
  }
  luaL_Stream *stream = lua_newuserdata(L, sizeof(luaL_Stream));
  luaL_setmetatable(L, LUA_FILEHANDLE);
  stream->f = _wpopen(filename_w, mode_w);
  stream->closef = &close_popen;
  free(filename_w);
  free(mode_w);

  return stream->f == NULL ? luaL_fileresult(L, 0, filename) : 1;
}

/** Calls a function and returns the number of values returned. */
static int call_function(lua_State *L, int nargs, int nresults) {
  int top = lua_gettop(L);
  lua_call(L, nargs, nresults);
  return lua_gettop(L) - (top - nargs - 1);
}

/** Calls a method previously saved into the registry with IO_PREFIX. */
static int stub_method(lua_State *L, const char *method) {
  int arg_len = lua_gettop(L);
  lua_pushfstring(L, "%s%s", IO_PREFIX, method);
  lua_gettable(L, LUA_REGISTRYINDEX); lua_insert(L, 1);
  return call_function(L, arg_len, LUA_MULTRET);
}

/**
 * A thunk for calling the iterator function returned by io.lines().
 * The thunk checks if the return value is nil (indicating end of iterator)
 * and closes the file immediately.
 * This emulate Lua's behavior for io.lines with a filename.
 * Upvalue 1 is the file and upvalue 2 is the function.
 */
static int utf8_io_lines_thunk(lua_State *L) {
  int arg_len, ret_len;
  arg_len = lua_gettop(L);
  lua_pushvalue(L, lua_upvalueindex(2)); lua_insert(L, 1); // insert function as first element

  if (!(ret_len = call_function(L, arg_len, LUA_MULTRET)) || lua_isnil(L, 1)) {
    // close the file if the function returns nothing (or nil!)
    lua_getfield(L, lua_upvalueindex(1), "close");
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_call(L, 1, 0);
  }
  return ret_len;
}

static int utf8_io_lines(lua_State *L) {
  int arg_len, ret_len;
  arg_len = lua_gettop(L);

  // fall back to original function if possible
  if (lua_isnoneornil(L, 1))
    return stub_method(L, "lines");

  // call _io_open to open a file
  lua_pushcfunction(L, utf8_io_open);
  lua_pushvalue(L, 1);
  lua_pushstring(L, "r");
  if (call_function(L, 2, LUA_MULTRET) != 1)
    return luaL_argerror(L, 1, lua_tostring(L, -2)); // -1 is errno, -2 is the message

  // copy the file (to replace filename)
  lua_copy(L, -1, 1);
  lua_insert(L, 1); // insert file as the first element (now we have two files)

  // get the lines metamethod and insert it as second element
  if (lua_getfield(L, 1, "lines") != LUA_TFUNCTION)
    return luaL_error(L, "cannot get metamethod lines");
  lua_insert(L, 2);

  // run the metamethod
  ret_len = call_function(L, arg_len, LUA_MULTRET);
  // all values are popped (except the first) and replaced with results
  if (lua_isfunction(L, 2)) {
    lua_pushvalue(L, 1); // push the first upvalue (file)
    lua_pushvalue(L, 2); // push the second upvalue (iterator)
    lua_pushcclosure(L, utf8_io_lines_thunk, 2); // 2 upvalues
    lua_replace(L, 2); // replace iterator function with our thunk
  }
  return ret_len;
}

/** General function to implement io.input, io.output, etc */
static int utf8_g_iofile(lua_State *L, const char *f, const char *mode) {
  if (lua_isstring(L, 1)) {
    // call io_open and replace the first argument with our file
    lua_pushcfunction(L, utf8_io_open);
    lua_pushvalue(L, 1);
    lua_pushstring(L, mode);
    if (call_function(L, 2, LUA_MULTRET) != 1)
      return luaL_error(L, "cannot open file '%s' (%s)", lua_tostring(L, 1), mode);
    lua_replace(L, 1);
  }
  // call the original method
  return stub_method(L, f);
}

static int utf8_io_input(lua_State *L) {
  return utf8_g_iofile(L, "input", "r");
}

static int utf8_io_output(lua_State *L) {
  return utf8_g_iofile(L, "output", "w");
}

static const luaL_Reg utf8_iolib[] = {
  { "open", utf8_io_open },
  { "lines", utf8_io_lines },
  { "popen", utf8_io_popen },
  { "input", utf8_io_input },
  { "output", utf8_io_output },
  { NULL, NULL }
};

#endif

static int utf8_io_enable(lua_State *L) {
#ifdef _WIN32
  // here we (attempt to) dynamically detect the version of lua.
  if (lua_version(L) < 503)
    return luaL_error(L, "unsupported runtime Lua version");

  // check if we've patched the io library
  if (lua_getfield(L, LUA_REGISTRYINDEX, IO_PREFIX "patched") != LUA_TNIL) {
    lua_pushboolean(L, 0);
    return 1;
  }

  // set patched
  lua_pushboolean(L, 1);
  lua_setfield(L, LUA_REGISTRYINDEX, IO_PREFIX "patched");

  // patch the functions
  lua_getglobal(L, "io");
  for (int i = 0; utf8_iolib[i].name; i++) {
    lua_getfield(L, -1, utf8_iolib[i].name);

    // save the old IO functions
    lua_pushfstring(L, "%s%s", IO_PREFIX, utf8_iolib[i].name);
    lua_pushvalue(L, -2);
    lua_settable(L, LUA_REGISTRYINDEX);
    lua_pop(L, 1);

    // save the new value
    lua_pushstring(L, utf8_iolib[i].name);
    lua_pushcfunction(L, utf8_iolib[i].func);
    lua_settable(L, -3);
  }
#endif

  lua_pushboolean(L, 1);
  return 1;
}

static int utf8_io_disable(lua_State *L) {
#ifdef _WIN32
  // check if we've patched the io library
  if (lua_getfield(L, LUA_REGISTRYINDEX, IO_PREFIX "patched") == LUA_TNIL) {
    lua_pushboolean(L, 0);
    return 1;
  }

  // unpatch all the functions
  lua_getglobal(L, "io");
  for (int i = 0; utf8_iolib[i].name; i++) {
    // restore the functions to the io table
    lua_pushstring(L, utf8_iolib[i].name);

    lua_pushfstring(L, "%s%s", IO_PREFIX, utf8_iolib[i].name);
    lua_gettable(L, LUA_REGISTRYINDEX);

    lua_settable(L, -3);
  }

  // unset patch
  lua_pushnil(L);
  lua_setfield(L, LUA_REGISTRYINDEX, IO_PREFIX "patched");
#endif

  lua_pushboolean(L, 1);
  return 1;
}

static const luaL_Reg utf8_io_control_lib[] = {
  { "enable", utf8_io_enable },
  { "disable", utf8_io_disable },
  { NULL, NULL },
};

int luaopen_utf8_io(lua_State *L) {
  luaL_newlib(L, utf8_io_control_lib);
  return 1;
}
