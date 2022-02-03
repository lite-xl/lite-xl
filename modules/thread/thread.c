/*
 * Port of https://github.com/Tangent128/luasdl2 thread.c to lite-xl
 *
 * Copyright (c) 2013, 2014 David Demelier <markand@malikania.fr>
 * Copyright (c) 2014 Joseph Wallace <tangent128@gmail.com>
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

#include "channel.h"

#include <SDL.h>
#include <errno.h>
#include <string.h>
#include <stdbool.h>

#define API_TYPE_THREAD "Thread"

typedef struct thread {
  lua_State *L;
  SDL_Thread *ptr;
  SDL_atomic_t ref;
  int joined;
} LuaThread;

typedef struct loadstate {
  struct {
    char* data;
    size_t size;
    size_t last_written;
  } buffer;
  int given;
} LoadState;

void* (*lite_xl_api_require)(char *) = NULL;
void (*lite_xl_api_load_libs)(lua_State*) = NULL;

int luaopen_thread(lua_State *L);

/* --------------------------------------------------------
 * Thread private functions
 * -------------------------------------------------------- */

static int writer(lua_State *L, const char *data, size_t sz, LoadState *state)
{
  size_t i;

  for (i = 0; i < sz; ++i) {
    if (state->buffer.last_written + 1 >= state->buffer.size) {
      if (!(state->buffer.data = realloc(state->buffer.data, state->buffer.size + 32))) {
        lua_pushstring(L, strerror(errno));
        return -1;
      } else {
        state->buffer.size += 32;
      }
    }
    state->buffer.last_written++;
    state->buffer.data[state->buffer.last_written] = data[i];
  }

  return 0;
}

static const char* reader(lua_State *L, LoadState *state, size_t *size)
{
  (void)L;

  if (state->given) {
    *size = 0;
    state->given = 1;
    return NULL;
  }

  *size = state->buffer.last_written + 1;

  return state->buffer.data;
}

static void destroy(LuaThread *t)
{
  (void)SDL_AtomicDecRef(&t->ref);

  if (SDL_AtomicGet(&t->ref) == 0) {
    lua_close(t->L);
  }
}

static int callback(LuaThread *t)
{
  int ret = -1;

  SDL_AtomicIncRef(&t->ref);

  if (lua_pcall(t->L, lua_gettop(t->L) - 1, 1, 0) != LUA_OK)
    SDL_LogCritical(SDL_LOG_CATEGORY_SYSTEM, "%s", lua_tostring(t->L, -1));
  else
    ret = lua_tointeger(t->L, -1);

  destroy(t);

  return ret;
}

static int loadfunction(lua_State *owner, lua_State *thread, int index)
{
  LoadState state;
  int ret = 0;

  memset(&state, 0, sizeof (LoadState));

  if (!(state.buffer.data = malloc(32))) {
    lua_pushnil(owner);
    lua_pushstring(owner, strerror(errno));
    ret = 2;
    goto cleanup;
  } else {
    state.buffer.last_written = -1;
    state.buffer.size = 32;
  }

  /* Copy the function at the top of the stack */
  lua_pushvalue(owner, index);

  if (lua_dump(owner, (lua_Writer)writer, &state, 0) != LUA_OK) {
    lua_pushnil(owner);
    lua_pushstring(owner, "failed to dump function");
    ret = 2;
    goto cleanup;
  }

  /*
   * If it fails, it pushes the error into the new state, move it to our
   * state.
   */
  if (lua_load(thread, (lua_Reader)reader, &state, "thread", NULL) != LUA_OK) {
    lua_pushnil(owner);
    lua_pushstring(owner, lua_tostring(thread, -1));
    ret = 2;
    goto cleanup;
  }

cleanup:
  if (state.buffer.data) {
    free(state.buffer.data);
  }

  return ret;
}

static int loadfile(lua_State *owner, lua_State *thread, const char *path)
{
  if (luaL_loadfile(thread, path) != LUA_OK){
    lua_pushnil(owner);
    lua_pushstring(owner, lua_tostring(thread, -1));
    return 2;
  }

  return 0;
}

static int threadDump(lua_State *L, lua_State *th, int index)
{
  int ret;

  if (lua_type(L, index) == LUA_TSTRING)
    ret = loadfile(L, th, lua_tostring(L, index));
  else if (lua_type(L, index) == LUA_TFUNCTION)
    ret = loadfunction(L, th, index);
  else
    return luaL_error(L, "expected a file path or a function");

  return ret;
}

static void push_from_state(lua_State* from, lua_State* to, int index)
{
  switch (lua_type(from, index)) {
    case LUA_TNUMBER:
    {
      lua_pushnumber(to, lua_tonumber(from, index));
      break;
    }
    case LUA_TSTRING:
    {
      const char *str;
      size_t length;
      str = lua_tolstring(from, index, &length);
      lua_pushlstring(to, str, length);
      break;
    }
    case LUA_TBOOLEAN:
    {
      lua_pushboolean(to, lua_toboolean(from, index));
      break;
    }
    case LUA_TTABLE:
    {
      if (index < 0)
        -- index;

      lua_pushnil(from);

      bool table_created = false;

      while (lua_next(from, index)) {
        int key_type = lua_type(from, -2);

        if (key_type == LUA_TNIL) {
          lua_pop(from, 1);
          break;
        } else if (!table_created) {
          lua_createtable(to, 0, 0);
          table_created = true;
        }

        push_from_state(from, to, -2);
        push_from_state(from, to, -1);

        lua_settable(to, -3);

        lua_pop(from, 1);
      }
      break;
    }
  }
}

/* --------------------------------------------------------
 * Thread functions
 * -------------------------------------------------------- */

/*
 * thread.create(name, source, ...)
 *
 * Create a separate thread of execution. It creates a new Lua state that
 * does not share any data frmo the parent process.
 *
 * Arguments:
 *  name, the thread name
 *  source, a path to a Lua file or a function to call
 *  ..., optional arguments passed to the thread function
 *
 * Returns:
 *  The thread object or nil
 *  The error message
 */
static int f_thread_create(lua_State *L)
{
  const char *name = luaL_checkstring(L, 1);
  int ret, iv;

  LuaThread* self = lua_newuserdata(L, sizeof(LuaThread));
  memset(self, 0, sizeof(LuaThread));
  luaL_setmetatable(L, API_TYPE_THREAD);

  self->L = luaL_newstate();
  luaL_openlibs(self->L);

  ret = threadDump(L, self->L, 2);

  /* If return number is 2, it is nil and the error */
  if (ret == 2)
    goto failure;

  /* Iterate over the optional arguments to pass to the callback */
  int optargc = lua_gettop(L);
  for (iv = 3; iv <= optargc; ++iv) {
    push_from_state(L, self->L, iv);
  }

  // loading lite-xl api before threadDump and arguments causes issues
  if (lite_xl_api_load_libs != NULL)
    lite_xl_api_load_libs(self->L);

  luaL_requiref(self->L, "thread", luaopen_thread, 1);

  self->ptr = SDL_CreateThread((SDL_ThreadFunction)callback, name, self);
  if (self->ptr == NULL) {
    luaL_error(L, SDL_GetError());
    goto failure;
  }

  SDL_AtomicIncRef(&self->ref);

  return 1;

failure:
  lua_close(self->L);

  return 2;
}

/* --------------------------------------------------------
 * Thread object methods
 * -------------------------------------------------------- */

/*
 * Thread:getId()
 *
 * Returns:
 *  The thread id
 */
static int m_thread_getId(lua_State *L)
{
  LuaThread* self = (LuaThread*)luaL_checkudata(L, 1, API_TYPE_THREAD);

  lua_pushinteger(L, SDL_GetThreadID(self->ptr));

  return 1;
}

/*
 * Thread:getName()
 *
 * Returns:
 *  The thread name
 */
static int m_thread_getName(lua_State *L)
{
  LuaThread* self = (LuaThread*)luaL_checkudata(L, 1, API_TYPE_THREAD);

  lua_pushstring(L, SDL_GetThreadName(self->ptr));

  return 1;
}

/*
 * Thread:wait()
 *
 * Returns:
 *  The return code from the thread
 */
static int m_thread_wait(lua_State *L)
{
  LuaThread* self = (LuaThread*)luaL_checkudata(L, 1, API_TYPE_THREAD);
  int status;

  SDL_WaitThread(self->ptr, &status);
  self->joined = 1;

  lua_pushinteger(L, status);

  return 1;
}

/* --------------------------------------------------------
 * Thread object metamethods
 * -------------------------------------------------------- */

/*
 * Thread:__eq()
 */
static int mm_thread_eq(lua_State *L)
{
  LuaThread* t1 = (LuaThread*)luaL_checkudata(L, 1, API_TYPE_THREAD);
  LuaThread* t2 = (LuaThread*)luaL_checkudata(L, 2, API_TYPE_THREAD);

  lua_pushboolean(L, t1 == t2);

  return 1;
}

/*
 * Thread:__gc()
 */
static int mm_thread_gc(lua_State *L)
{
  LuaThread* self = (LuaThread*)luaL_checkudata(L, 1, API_TYPE_THREAD);

#if SDL_VERSION_ATLEAST(2, 0, 2)
  if (!self->joined)
    SDL_DetachThread(self->ptr);
#endif

  destroy(self);

  return 0;
}

/*
 * Thread:__tostring()
 */
static int mm_thread_tostring(lua_State *L)
{
  LuaThread* self = (LuaThread*)luaL_checkudata(L, 1, API_TYPE_THREAD);

  lua_pushfstring(L, "thread %d", SDL_GetThreadID(self->ptr));

  return 1;
}

/* --------------------------------------------------------
 * Thread object definition
 * -------------------------------------------------------- */

static const struct luaL_Reg thread_lib[] = {
  {"create", f_thread_create},
  {"getChannel", f_channel_get},
  {NULL, NULL}
};

static const struct luaL_Reg thread_object[] = {
  {"getId", m_thread_getId},
  {"getName", m_thread_getName},
  {"wait", m_thread_wait},
  {"__eq", mm_thread_eq},
  {"__gc", mm_thread_gc},
  {"__tostring", mm_thread_tostring},
  {NULL, NULL}
};

/* --------------------------------------------------------
 * Channel object definition
 * -------------------------------------------------------- */

static const struct luaL_Reg channel_object[] = {
  {"first", m_channel_first},
  {"last", m_channel_last},
  {"push", m_channel_push},
  {"clear", m_channel_clear},
  {"pop", m_channel_pop},
  {"supply", m_channel_supply},
  {"wait", m_channel_wait},
  {"__gc", mm_channel_gc},
  {"__tostring", mm_channel_tostring},
  {NULL, NULL}
};

/* Called internally to expose the thread lib to created threads */
int luaopen_thread(lua_State *L) {
  luaL_newmetatable(L, API_TYPE_THREAD);
  luaL_setfuncs(L, thread_object, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");

  luaL_newmetatable(L, API_TYPE_CHANNEL);
  luaL_setfuncs(L, channel_object, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");

  luaL_newlib(L, thread_lib);

  return 1;
}

/* Called by lite-xl f_load_native_plugin on `require "thread"` */
int luaopen_lite_xl_thread(lua_State *L, void* (*api_require)(char *)) {
  lite_xl_api_require = api_require;
  lite_xl_api_load_libs = api_require("api_load_libs");

  return luaopen_thread(L);
}
