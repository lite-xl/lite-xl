#include <SDL.h>

#include "api/api.h"

#define API_TYPE_CHANNEL "Channel"

extern SDL_mutex* ChannelsListMutex;

// channel table functions
int f_channel_get(lua_State*);

// Channel object methods
int m_channel_first(lua_State*);
int m_channel_last(lua_State*);
int m_channel_push(lua_State*);
int m_channel_clear(lua_State*);
int m_channel_pop(lua_State*);
int m_channel_supply(lua_State*);
int m_channel_wait(lua_State*);

// Channel object metamethods
int mm_channel_gc(lua_State*);
int mm_channel_tostring(lua_State*);
