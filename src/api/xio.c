#include "api.h"
#include "win32_util.h"

#define XIO_PREFIX "__XIO__"
#define XIO_INPUT (XIO_PREFIX "input")
#define XIO_OUTPUT (XIO_PREFIX "output")


static int io_fclose(lua_State *L) {
  luaL_Stream *p = luaL_checkudata(L, 1, LUA_FILEHANDLE);
  int res = fclose(p->f);
  return luaL_fileresult(L, (res == 0), NULL);
}


static int f_open(lua_State *L) {
  const char *filename = luaL_checkstring(L, 1);
  const char *mode = luaL_optstring(L, 2, "r");

  LPWSTR wfilename = utftowcs(filename);
  LPWSTR wmode = utftowcs(mode);
  if (!wfilename || !wmode)
    return l_win32error(L, GetLastError());

  luaL_Stream *p = (luaL_Stream *) lua_newuserdata(L, sizeof(luaL_Stream));
  luaL_setmetatable(L, LUA_FILEHANDLE);
  p->f = _wfopen(wfilename, wmode);
  p->closef = &io_fclose;

  return (p->f == NULL) ? luaL_fileresult(L, 0, filename) : 1;
}


static int f_replace_handle(lua_State *L) {
  luaL_checkudata(L, 1, LUA_FILEHANDLE);
  luaL_checkudata(L, 2, LUA_FILEHANDLE);
  const char *key  = lua_toboolean(L, 3) ? XIO_INPUT : XIO_OUTPUT;

  lua_getfield(L, LUA_REGISTRYINDEX, key);
  if (lua_isnil(L, -1)) {
    // find the handle
    while (lua_next(L, LUA_REGISTRYINDEX) != 0) {
      int c = lua_compare(L, -1, 1, LUA_OPEQ);
      lua_pop(L, 1);
      if (c) {
        lua_setfield(L, LUA_REGISTRYINDEX, key);
        break;
      }
    }
    lua_getfield(L, LUA_REGISTRYINDEX, key);
    if (lua_isnil(L, 1))
      return luaL_error(L, "cannot %s handle name", lua_toboolean(L, 3) ? "stdin" : "stdout");
  }

  lua_pushvalue(L, -1); // duplicate the key
  lua_pushvalue(L, 2);
  lua_settable(L, LUA_REGISTRYINDEX);
  lua_gettable(L, LUA_REGISTRYINDEX);

  return 1;
}


static int f_remove(lua_State *L) {
  const char *filename = luaL_checkstring(L, 1);
  LPWSTR wfilename = utftowcs(filename);
  if (!wfilename)
    return errno = EINVAL, luaL_fileresult(L, 0, filename);

  int r = _wremove(wfilename);
  free(wfilename);

  return luaL_fileresult(L, r == 0, filename);
}


static int f_rename(lua_State *L) {
  const char *old = luaL_checkstring(L, 1);
  const char *new = luaL_checkstring(L, 2);
  LPWSTR wold = utftowcs(old);
  LPWSTR wnew = utftowcs(new);
  if (!wold || !wnew)
    return errno = EINVAL, luaL_fileresult(L, 0, NULL);

  int r = _wrename(wold, wnew);
  free(wold); free(wnew);

  return luaL_fileresult(L, r == 0, NULL);
}


const luaL_Reg lib[] = {
  { "open", f_open },
  { "replace_handle", f_replace_handle },
  { "remove", f_remove },
  { "rename", f_rename },
  { NULL, NULL }
};

int luaopen_xio(lua_State *L) {
  luaL_newlib(L, lib);
  return 1;
}
