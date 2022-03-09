/*
 * Port of https://github.com/Tangent128/luasdl2 channel.c to lite-xl
 *
 * Copyright (c) 2013, 2014 David Demelier <markand@malikania.fr>
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

#include <errno.h>
#include <string.h>

typedef struct channel_value_pair {
  struct channel_value* key;
  struct channel_value* value;
  struct {
    struct channel_value_pair* first;
    struct channel_value_pair** last;
  } queue;
  struct channel_value_pair* next;
} ChannelValuePair;

typedef struct channel_value {
  int type;

  union {
    char boolean;
    lua_Number number;
    ChannelValuePair table;
    struct {
      char* data;
      int length;
    } string;
  } data;

  struct channel_value* next;
} ChannelValue;

typedef struct channel {
  char* name;

  struct {
    ChannelValue* first;
    ChannelValue** last;
  } queue;

  SDL_atomic_t ref;
  SDL_mutex* mutex;
  SDL_cond* cond;
  unsigned int sent;
  unsigned int received;

  struct channel* next;
} Channel;

typedef struct channel_container {
  Channel* channel;
} ChannelContainer;

typedef struct channel_list {
  Channel* first;
  Channel** last;
} ChannelList;

/* Global list of registered channels */
static ChannelList g_channels = { NULL, &(g_channels).first };

/* Mutex initialized when plugin is loaded */
SDL_mutex* ChannelsListMutex = NULL;

/* --------------------------------------------------------
 * Channel private functions
 * -------------------------------------------------------- */

static void channelValueFree(ChannelValue *v)
{
  ChannelValuePair *t, *tmp;

  if (v == NULL)
    return;

  switch (v->type) {
    case LUA_TSTRING:
      free(v->data.string.data);
      break;
    case LUA_TTABLE:
      for (
        t = v->data.table.queue.first;
        t && (tmp = t->next, 1);
        t = tmp
      ){
        channelValueFree(t->key);
        channelValueFree(t->value);
        free(t);
      }
      break;
  }

  free(v);
}

static ChannelValue* channelValueGet(lua_State *L, int index)
{
  ChannelValue *v;
  int type;

  if ((type = lua_type(L, index)) == LUA_TNIL)
    return NULL;

  if ((v = calloc(1, sizeof (ChannelValue))) == NULL)
    return NULL;

  v->type = type;
  switch (v->type) {
    case LUA_TNUMBER:
      v->data.number = lua_tonumber(L, index);
      break;
    case LUA_TSTRING:
    {
      const char *str;
      size_t length;

      str = lua_tolstring(L, index, &length);
      if ((v->data.string.data = malloc(length)) == NULL) {
        free(v);
        return NULL;
      }

      /* Copy the string which may have embedded '\0' */
      v->data.string.length = length;
      memcpy(v->data.string.data, str, length);
    }
      break;
    case LUA_TBOOLEAN:
      v->data.boolean = lua_toboolean(L, index);
      break;
    case LUA_TTABLE:
    {
      v->data.table.queue.first = NULL;
      v->data.table.queue.last = &v->data.table.queue.first;

      if (index < 0)
        -- index;

      lua_pushnil(L);
      while (lua_next(L, index)) {
        ChannelValuePair* pair = malloc(sizeof (ChannelValuePair));

        if (pair == NULL) {
          lua_pop(L, 1);
          channelValueFree(v);
          return NULL;
        }

        pair->key = channelValueGet(L, -2);
        pair->value = channelValueGet(L, -1);

        if (pair->key == NULL || pair->value == NULL) {
          lua_pop(L, 1);
          channelValueFree(pair->key);
          channelValueFree(pair->value);
          channelValueFree(v);
          free(pair);
          break;
        }

        lua_pop(L, 1);

        pair->next = NULL;
        /* set first or next in list to current pair */
        *v->data.table.queue.last = pair;
        /* set the last in list to the next pair */
        v->data.table.queue.last = &pair->next;
      }
    }
      break;
  }

  return v;
}

static void channelValuePush(lua_State* L, const ChannelValue* v)
{
  if (v == NULL)
    return;

  switch (v->type) {
    case LUA_TNUMBER:
      lua_pushnumber(L, v->data.number);
      break;
    case LUA_TSTRING:
      lua_pushlstring(L, v->data.string.data, v->data.string.length);
      break;
    case LUA_TBOOLEAN:
        lua_pushboolean(L, v->data.boolean);
        break;
    case LUA_TTABLE:
    {
      ChannelValuePair* pair;

      lua_createtable(L, 0, 0);
      for(
        pair = v->data.table.queue.first;
        pair;
        pair = pair->next
      ) {
        channelValuePush(L, pair->key);
        channelValuePush(L, pair->value);
        lua_settable(L, -3);
      }
    }
      break;
  }
}

/*
 * Highly based on LÖVE system.
 */
static int channelGiven(unsigned int target, unsigned int current)
{
  union cv {
    unsigned long u;
    long i;
  } t, c;

  if (target > current)
    return 0;
  if (target == current)
    return 1;

  t.u = target;
  c.u = current;

  return !(t.i < 0 && c.i > 0);
}

static const ChannelValue* channelFirst(const Channel* c)
{
  ChannelValue* v;

  SDL_LockMutex(c->mutex);
  if (c->queue.first == NULL){
    SDL_UnlockMutex(c->mutex);
    return NULL;
  }

  v = c->queue.first;
  SDL_UnlockMutex(c->mutex);

  return v;
}

static const ChannelValue* channelLast(const Channel *c)
{
  ChannelValue *v;

  SDL_LockMutex(c->mutex);
  if (c->queue.first == NULL){
    SDL_UnlockMutex(c->mutex);
    return NULL;
  }

  v = c->queue.first == NULL ? NULL : *(c->queue.last);

  SDL_UnlockMutex(c->mutex);

  return v;
}

static int channelPush(Channel* c, ChannelValue* v)
{
  SDL_LockMutex(c->mutex);

  v->next = NULL;
  /* set pointer of previous next to given value */
  *c->queue.last = v;
  /* set the last element to new next */
  c->queue.last = &v->next;

  SDL_UnlockMutex(c->mutex);
  SDL_CondBroadcast(c->cond);

  return ++c->sent;
}

static const ChannelValue* channelWait(Channel *c)
{
  SDL_LockMutex(c->mutex);
  while (c->queue.first == NULL)
    SDL_CondWait(c->cond, c->mutex);

  ++ c->received;

  SDL_UnlockMutex(c->mutex);
  SDL_CondBroadcast(c->cond);

  return c->queue.first;
}

static void channelSupply(Channel* c, ChannelValue* v)
{
  unsigned id;

  SDL_LockMutex(c->mutex);

  id = channelPush(c, v);
  while (!channelGiven(id, c->received))
    SDL_CondWait(c->cond, c->mutex);
}

static void channelClear(Channel* c)
{
  ChannelValue* v;
  ChannelValue* tmp;

  SDL_LockMutex(c->mutex);

  for (v = c->queue.first; v && (tmp = v->next, 1); v = tmp)
  {
    channelValueFree(v);
  }

  c->queue.first = NULL;
  c->queue.last = &c->queue.first;

  SDL_UnlockMutex(c->mutex);
  SDL_CondBroadcast(c->cond);
}

static void channelPop(Channel* c)
{
  SDL_LockMutex(c->mutex);

  if (c->queue.first == NULL) {
    SDL_UnlockMutex(c->mutex);
    SDL_CondBroadcast(c->cond);
    return;
  }

  ChannelValue* previous_first = c->queue.first;

  c->queue.first = previous_first->next;

  if (!c->queue.first)
    c->queue.last = &c->queue.first;
  else if(!c->queue.first->next)
    c->queue.last = &c->queue.first->next;

  channelValueFree(previous_first);

  SDL_UnlockMutex(c->mutex);
  SDL_CondBroadcast(c->cond);
}

static void removeChannelFromList(Channel* c)
{
  Channel* first = g_channels.first;

  SDL_LockMutex(ChannelsListMutex);

  if (c == first && first->next == NULL) {
    g_channels.first = NULL;
    g_channels.last = &g_channels.first;
  }
  else if (c == first) {
    g_channels.first = c->next;
  } else {
    Channel* prev = first;
    for (Channel* ch = first->next; ch; ch = ch->next) {
      if (strcmp(ch->name, c->name) == 0) {
        break;
      }
      prev = ch;
    }
    if (c->next == NULL) {
      prev->next = NULL;
      g_channels.last = &prev->next;
    } else {
      prev->next = c->next;
    }
  }

  SDL_UnlockMutex(ChannelsListMutex);
}

static void channelFree(Channel* c)
{
  removeChannelFromList(c);

  channelClear(c);

  SDL_DestroyMutex(c->mutex);
  SDL_DestroyCond(c->cond);

  free(c->name);
  free(c);
}

/* --------------------------------------------------------
 * Channel functions
 * -------------------------------------------------------- */

/*
 * channel.get(name)
 *
 * Arguments:
 *  name the channel name
 *
 * Returns:
 *  The channel object or nil on failure
 *  The error message
 */
int f_channel_get(lua_State *L)
{
  size_t name_len = 0;
  const char *name = luaL_checklstring(L, 1, &name_len);
  Channel *c;
  int found = 0;

  SDL_LockMutex(ChannelsListMutex);

  for (c = g_channels.first; c; c = c->next) {
    if (strcmp(c->name, name) == 0) {
      found = 1;
      break;
    }
  }

  const char* error_message = NULL;

  if (!found) {
    if ((c = calloc(1, sizeof (Channel))) == NULL) {
      error_message = strerror(errno);
      goto fail;
    }
    if ((c->name = malloc(name_len+1)) == NULL) {
      error_message = strerror(errno);
      goto fail;
    }
    if ((c->mutex = SDL_CreateMutex()) == NULL) {
      error_message = SDL_GetError();
      goto fail;
    }
    if ((c->cond = SDL_CreateCond()) == NULL) {
      error_message = SDL_GetError();
      goto fail;
    }

    strcpy(c->name, name);

    c->queue.first = NULL;
    c->queue.last = &c->queue.first;

    c->next = NULL;
    *g_channels.last = c;
    g_channels.last = &c->next;
  }

  SDL_AtomicIncRef(&c->ref);

  ChannelContainer* self = lua_newuserdata(L, sizeof(ChannelContainer));
  luaL_setmetatable(L, API_TYPE_CHANNEL);
  self->channel = c;

  SDL_UnlockMutex(ChannelsListMutex);

  return 1;

fail:
  if (c->mutex)
    SDL_DestroyMutex(c->mutex);
  if (c->cond)
    SDL_DestroyCond(c->cond);

  free(c->name);
  free(c);

  SDL_UnlockMutex(ChannelsListMutex);

  luaL_error(L, error_message);

  return 2;
}

/* --------------------------------------------------------
 * Channel object methods
 * -------------------------------------------------------- */

/*
 * Channel:first()
 *
 * Returns:
 *  The first value or nil
 */
int m_channel_first(lua_State *L)
{
  Channel* self = ((ChannelContainer*)luaL_checkudata(
    L, 1, API_TYPE_CHANNEL
  ))->channel;
  const ChannelValue* v;

  if ((v = channelFirst(self)) == NULL)
    lua_pushnil(L);
  else
    channelValuePush(L, v);

  return 1;
}

/*
 * Channel:last()
 *
 * Returns:
 *  The last value or nil
 */
int m_channel_last(lua_State *L)
{
  Channel* self = ((ChannelContainer*)luaL_checkudata(
    L, 1, API_TYPE_CHANNEL
  ))->channel;
  const ChannelValue* v;

  if ((v = channelLast(self)) == NULL)
    lua_pushnil(L);
  else
    channelValuePush(L, v);

  return 1;
}

/*
 * Channel:push(value)
 *
 * Arguments:
 *  value the value to push (!userdata, !function)
 *
 * Returns:
 *  True on success or false
 *  The error message
 */
int m_channel_push(lua_State *L)
{
  Channel* self = ((ChannelContainer*)luaL_checkudata(
    L, 1, API_TYPE_CHANNEL
  ))->channel;
  ChannelValue* v = channelValueGet(L, 2);

  if (v == NULL){
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
  }

  channelPush(self, v);

  lua_pushboolean(L, 1);
  return 1;
}

/*
 * Channel:supply(value)
 *
 * Arguments:
 *  value the value to push (!userdata, !function)
 *
 * Returns:
 *  True on success or false
 *  The error message
 */
int m_channel_supply(lua_State *L)
{
  Channel* self = ((ChannelContainer*)luaL_checkudata(
    L, 1, API_TYPE_CHANNEL
  ))->channel;
  ChannelValue* v = channelValueGet(L, 2);

  if (v == NULL) {
    lua_pushnil(L);
    lua_pushstring(L, strerror(errno));
    return 2;
  }

  channelSupply(self, v);

  lua_pushboolean(L, 1);
  return 1;
}

/*
 * Channel:clear()
 */
int m_channel_clear(lua_State *L)
{
  Channel* self = ((ChannelContainer*)luaL_checkudata(
    L, 1, API_TYPE_CHANNEL
  ))->channel;

  channelClear(self);

  return 0;
}

/*
 * Channel:pop()
 */
int m_channel_pop(lua_State *L)
{
  Channel* self = ((ChannelContainer*)luaL_checkudata(
    L, 1, API_TYPE_CHANNEL
  ))->channel;
  channelPop(self);

  return 0;
}

/*
 * Channel:wait()
 *
 * Returns:
 *  The last value or nil
 */
int m_channel_wait(lua_State *L)
{
  Channel* self = ((ChannelContainer*)luaL_checkudata(
    L, 1, API_TYPE_CHANNEL
  ))->channel;
  const ChannelValue* v;

  if ((v = channelWait(self)) == NULL)
    lua_pushnil(L);
  else
    channelValuePush(L, v);

  SDL_CondBroadcast(self->cond);

  return 1;
}

/* --------------------------------------------------------
 * Channel object metamethods
 * -------------------------------------------------------- */

/*
 * Channel:__gc()
 */
int mm_channel_gc(lua_State *L)
{
  Channel* self = ((ChannelContainer*)luaL_checkudata(
    L, 1, API_TYPE_CHANNEL
  ))->channel;

  (void)SDL_AtomicDecRef(&self->ref);
  if (SDL_AtomicGet(&self->ref) == 0)
    channelFree(self);

  return 0;
}

/*
 * Channel:__tostring()
 */
int mm_channel_tostring(lua_State *L)
{
  Channel* self = ((ChannelContainer*)luaL_checkudata(
    L, 1, API_TYPE_CHANNEL
  ))->channel;

  lua_pushfstring(L, "channel %s", self->name);

  return 1;
}
