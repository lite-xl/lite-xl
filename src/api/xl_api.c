#include "api.h"
#include <lualib.h>
#include <SDL.h>

#define CLIB "_LITE_XL_CLIB_"

typedef void (*lua_function)(void);

typedef struct lua_function_node {
  const char *symbol;
  lua_function address;
} lua_function_node;

#define P(FUNC) { "lua_" #FUNC, (lua_function)(lua_##FUNC) }
#define U(FUNC) { "luaL_" #FUNC, (lua_function)(luaL_##FUNC) }

static void* api_require(const char* symbol) {
  static const lua_function_node nodes[] = {
    P(atpanic), P(checkstack),
    P(close), P(concat), P(copy), P(createtable), P(dump),
    P(error),  P(gc), P(getallocf),  P(getfield),
    P(gethook), P(gethookcount), P(gethookmask), P(getinfo), P(getlocal),
    P(getmetatable), P(getstack), P(gettable), P(gettop), P(getupvalue),
    P(isnumber), P(isstring), P(isuserdata),
    P(load), P(newstate), P(newthread), P(next),
    P(pushboolean), P(pushcclosure), P(pushfstring), P(pushinteger),
    P(pushlightuserdata), P(pushlstring), P(pushnil), P(pushnumber),
    P(pushstring), P(pushthread),  P(pushvalue),
    P(pushvfstring), P(rawequal), P(rawget), P(rawgeti),
    P(rawset), P(rawseti), P(resume),
    P(setallocf), P(setfield), P(sethook), P(setlocal),
    P(setmetatable), P(settable), P(settop), P(setupvalue),
    P(status), P(tocfunction), P(tointegerx), P(tolstring), P(toboolean),
    P(tonumberx), P(topointer), P(tothread),  P(touserdata),
    P(type), P(typename), P(upvalueid), P(upvaluejoin), P(version), P(xmove),
    U(getmetafield), U(callmeta), U(argerror), U(checknumber), U(optnumber),
    U(checkinteger), U(checkstack), U(checktype), U(checkany),
    U(newmetatable), U(setmetatable), U(testudata), U(checkudata), U(where),
    U(error), U(fileresult), U(execresult), U(ref), U(unref), U(loadstring),
    U(newstate), U(setfuncs), U(buffinit), U(addlstring), U(addstring),
    U(addvalue), U(pushresult), U(openlibs), {"api_load_libs", (void*)(api_load_libs)},
#if LUA_VERSION_NUM >= 502
    P(absindex), P(arith), P(callk), P(compare), P(getglobal),
    P(len), P(pcallk), P(rawgetp), P(rawlen), P(rawsetp), P(setglobal),
    P(iscfunction), P(yieldk),
    U(checkversion_), U(tolstring), U(len), U(getsubtable), U(prepbuffsize),
    U(pushresultsize), U(buffinitsize), U(checklstring), U(checkoption), U(gsub), U(loadbufferx),
    U(loadfilex), U(optinteger), U(optlstring), U(requiref), U(traceback),
#else
    P(objlen),
#endif
#if LUA_VERSION_NUM >= 504
    P(newuserdatauv), P(setiuservalue), P(getiuservalue)
#else
    P(newuserdata), P(setuservalue), P(getuservalue)
#endif
  };
  for (size_t i = 0; i < sizeof(nodes) / sizeof(lua_function_node); ++i) {
    if (strcmp(nodes[i].symbol, symbol) == 0)
      return *(void**)(&nodes[i].address);
  }
  return NULL;
}

static int f_library_gc(lua_State *L) {
  void **handle = luaL_checkudata(L, 1, API_TYPE_C_LIBRARY);
  SDL_UnloadObject(*handle);

  return 0;
}

static int f_library_tostring(lua_State *L) {
  lua_pushliteral(L, API_TYPE_C_LIBRARY);
  return 1;
}

static void *open_library(lua_State *L, const char *path) {
  void *lib;
  luaL_getsubtable(L, LUA_REGISTRYINDEX, CLIB);
  if (lua_getfield(L, -1, path) != LUA_TNIL) {
    lib = *((void **) lua_touserdata(L, -1));
    lua_pop(L, 2);
  } else {
    lua_pop(L, 1); // pop the library userdata (nil in this case)
    lib = SDL_LoadObject(path);
    if (!lib) {
      lua_pop(L, 1); // pop the clib table
      lua_pushnil(L);
      lua_pushstring(L, SDL_GetError());
      lua_pushliteral(L, "open");
      return NULL;
    }
    *((void **) lua_newuserdata(L, sizeof(void **))) = lib;
    luaL_setmetatable(L, API_TYPE_C_LIBRARY);
    lua_setfield(L, -2, path);
    lua_pop(L, 1); // pop clib
  }
  return lib;
}

static int extended_function_thunk(lua_State *L) {
  int (*fn) (lua_State *L, void* (*)(const char*));
  *(void**)(&fn) = lua_touserdata(L, lua_upvalueindex(1));
  return fn(L, api_require);
}

static int f_loadlib(lua_State *L) {
  void *lib, *fn;
  const char *path = luaL_checkstring(L, 1);
  const char *funcname = luaL_checkstring(L, 2);
  int extended = lua_toboolean(L, 3);

  if (!(lib = open_library(L, path)))
    return 3;
  if (!(fn = SDL_LoadFunction(lib, funcname))) {
    lua_pushnil(L);
    lua_pushstring(L, SDL_GetError());
    lua_pushliteral(L, "init");
    return 3;
  }

  if (extended) {
    lua_pushlightuserdata(L, fn);
    lua_pushcclosure(L, extended_function_thunk, 1);
  } else {
    lua_CFunction f;
    *(void**)(&f) = fn;
    lua_pushcfunction(L, f);
  }
  return 1;
}

static const luaL_Reg lib[] = {
  { "loadlib", f_loadlib },
  { NULL, NULL }
};

static const luaL_Reg lib_metatable[] = {
  { "__gc", f_library_gc },
  { "__tostring", f_library_tostring },
  { NULL, NULL }
};

int luaopen_xl_api(lua_State *L) {
  luaL_newmetatable(L, API_TYPE_C_LIBRARY);
  luaL_setfuncs(L, lib_metatable, 0);

  luaL_newlib(L, lib);
  return 1;
}
