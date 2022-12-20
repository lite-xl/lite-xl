#include "api.h"

#include <SDL_net.h>
#include <stdbool.h>

#define IPV4_LEN 16

typedef enum ConnectionType {
  TCP,
  UDP
} ConnectionType;

typedef struct Connection {
  void* socket;
  ConnectionType type;
  bool closed;
} Connection;

static bool ip_to_number(const char* string, unsigned int* number) {
  unsigned int byte0, byte1, byte2, byte3;
  if (sscanf(string, "%u.%u.%u.%u", &byte3, &byte2, &byte1, &byte0) == 4) {
    if (byte0 < 256 && byte1 < 256 && byte2 < 256 && byte3 < 256) {
      *number = (byte0 << 24) + (byte1 << 16) + (byte2 << 8) + byte3;
      return true;
    }
  }
  return false;
}

static void ip_to_string(unsigned int number, char* string) {
  sprintf(
    string,
    "%d.%d.%d.%d",
    number & 0xFF,
    (number >> 8) & 0xFF,
    (number >> 16) & 0xFF,
    (number >> 24) & 0xFF
  );
}

static bool host_port_to_address(
  const char* host, unsigned short port, IPaddress* address
) {
  unsigned int ip_number;

  if (ip_to_number(host, &ip_number)) {
    address->host = ip_number;
    address->port = port;
    return true;
  } else if(SDLNet_ResolveHost(address, host, port) != -1) {
    return true;
  }

  return false;
}

static SDLNet_SocketSet pull_set(lua_State* L, int arg) {
  if (!lua_istable(L, arg))
    luaL_typeerror(L, arg, "set");

  lua_getmetatable(L, arg);
  lua_getfield(L, -1, "__name");
  const char* name = lua_tostring(L, -1);
  lua_pop(L, 2);

  if (!strstr(API_TYPE_NET_SET, name))
    luaL_typeerror(L, arg, "set");

  lua_rawgeti(L, arg, 1);
  SDLNet_SocketSet set = lua_touserdata(L, -1);
  lua_pop(L, 1);
  return set;
}

static bool pull_address(lua_State* L, int arg, IPaddress* address) {
  luaL_checktype(L, arg, LUA_TTABLE);

  lua_getfield(L, arg, "host");
  const char* host = lua_tostring(L, -1);
  lua_pop(L, 1);

	lua_getfield(L, arg, "port");
	unsigned short port = lua_tointeger(L, -1);
	lua_pop(L, 1);

  if (host_port_to_address(host, port, address)) {
    return true;
  }

  return false;
}

static void push_address(lua_State* L, IPaddress* address) {
  char ip_string[IPV4_LEN];
  ip_to_string(address->host, ip_string);

  lua_createtable(L, 0, 2);

  lua_pushstring(L, ip_string);
  lua_setfield(L, -2, "host");

  lua_pushinteger(L, address->port);
  lua_setfield(L, -2, "port");
}

static void close_connection(Connection* conn) {
  if (!conn->closed) {
    if (conn->type == TCP)
      SDLNet_TCP_Close(conn->socket);
    else if (conn->type == UDP)
      SDLNet_UDP_Close(conn->socket);

    conn->closed = true;
  }
}

/******************************************************************************/
/* Library Functions                                                          */
/******************************************************************************/

static int f_init(lua_State* L) {
  if (SDLNet_Init() == 0) {
    lua_pushboolean(L, 1);
    return 1;
  }

  lua_pushboolean(L, 0);
  lua_pushstring(L, SDLNet_GetError());
  return 2;
}

static int f_quit(lua_State* L) {
  SDLNet_Quit();
  return 0;
}

static int f_resolve_host(lua_State* L) {
  const char* hostname = luaL_checkstring(L, 1);

  IPaddress address;
  if (SDLNet_ResolveHost(&address, hostname, 0) == 0) {
    char ip[IPV4_LEN];
    ip_to_string(address.host, ip);
    lua_pushstring(L, ip);
    return 1;
  }

  lua_pushnil(L);
  lua_pushstring(L, SDLNet_GetError());
  return 2;
}

static int f_resolve_ip(lua_State* L) {
  const char* ip_string = luaL_checkstring(L, 1);
  unsigned int ip_number;

  if (ip_to_number(ip_string, &ip_number) == 0) {
    lua_pushnil(L);
    lua_pushstring(L, "invalid ip address given");
    return 2;
  }

  IPaddress address;
  address.host = ip_number;
  address.port = 0;

  const char* hostname = SDLNet_ResolveIP(&address);
  if (hostname == NULL) {
    lua_pushnil(L);
    lua_pushstring(L, "could not resolve ip to hostname");
    return 2;
  }

  lua_pushstring(L, hostname);
  return 1;
}

static int f_get_local_addresses(lua_State* L) {
  const int max_amount = luaL_optinteger(L, 1, 10);

  IPaddress* addresses = malloc(sizeof(IPaddress) * max_amount);

  int count = SDLNet_GetLocalAddresses(addresses, max_amount);

  if (count > 0) {
    char ip_string[IPV4_LEN];
    lua_createtable(L, count, 0);
    for(int i=0; i<count; i++) {
      ip_to_string(addresses[i].host, ip_string);
      lua_pushstring(L, ip_string);
      lua_rawseti(L, -2, i+1);
    }
  } else {
    lua_pushnil(L);
  }

  free(addresses);

  return count > 0 ? 1 : 0;
}

static int f_set(lua_State* L) {
  int size = luaL_checkinteger(L, 1);
  SDLNet_SocketSet self = SDLNet_AllocSocketSet(size);

  if (self == NULL) {
    lua_pushnil(L);
    lua_pushstring(L, SDLNet_GetError());
    return 2;
  }

  lua_newtable(L);

  /* store self on first field */
  lua_pushlightuserdata(L, self);
  lua_rawseti(L, -2, 1);

  /* table to hold a reference of added sockets on second field */
  lua_newtable(L);
  lua_rawseti(L, -2, 2);

  luaL_setmetatable(L, API_TYPE_NET_SET);

  return 1;
}

static int f_open_tcp(lua_State* L) {
  const char* host = luaL_checkstring(L, 1);
  unsigned short port = luaL_checkinteger(L, 2);

  unsigned int ip_number;
  IPaddress address;

  if (ip_to_number(host, &ip_number)) {
    address.host = ip_number;
    address.port = port;
  } else {
    if (SDLNet_ResolveHost(&address, host, port) != 0) {
      lua_pushnil(L);
      lua_pushstring(L, SDLNet_GetError());
      return 2;
    }
  }

  void* socket = SDLNet_TCP_Open(&address);

  if (socket == NULL) {
    lua_pushnil(L);
    lua_pushstring(L, SDLNet_GetError());
    return 2;
  }

  Connection* self = lua_newuserdata(L, sizeof(Connection));
  self->type = TCP;
  self->socket = socket;
  self->closed = false;

  luaL_setmetatable(L, API_TYPE_NET_TCP);

  return 1;
}

static int f_open_udp(lua_State* L) {
  unsigned short port = luaL_optinteger(L, 1, 0);

  void* socket = SDLNet_UDP_Open(port);

  if (socket == NULL) {
    lua_pushnil(L);
    lua_pushstring(L, SDLNet_GetError());
    return 2;
  }

  Connection* self = lua_newuserdata(L, sizeof(Connection));
  self->type = UDP;
  self->socket = socket;
  self->closed = false;

  luaL_setmetatable(L, API_TYPE_NET_UDP);

  return 1;
}

/******************************************************************************/
/* Set Methods                                                                */
/******************************************************************************/

static int m_set_add(lua_State* L) {
  SDLNet_SocketSet self = pull_set(L, 1);

  if (
    !luaL_testudata(L, 2, API_TYPE_NET_TCP)
    &&
    !luaL_testudata(L, 2, API_TYPE_NET_UDP)
  ) {
    return luaL_argerror(L, 2, "expected tcp or udp socket");
  }

  Connection* conn = NULL;
  if (luaL_testudata(L, 2, API_TYPE_NET_TCP))
    conn = luaL_checkudata(L, 2, API_TYPE_NET_TCP);
  else if(luaL_testudata(L, 2, API_TYPE_NET_UDP))
    conn = luaL_checkudata(L, 2, API_TYPE_NET_UDP);

  int len = SDLNet_AddSocket(self, conn->socket);
  if (len < 0){
    lua_pushnil(L);
    lua_pushstring(L, SDLNet_GetError());
    return 2;
  }

  /* add reference of socket to set to prevent garbage collection */
  lua_rawgeti(L, 1, 2);
  lua_pushvalue(L, 2);
  lua_rawsetp(L, -2, conn);
  lua_pop(L, 1);

  lua_pushinteger(L, len);

  return 1;
}

static int m_set_delete(lua_State* L) {
  SDLNet_SocketSet self = pull_set(L, 1);
  if (!self) return luaL_typeerror(L, 1, "set");

  if (
    !luaL_testudata(L, 2, API_TYPE_NET_TCP)
    &&
    !luaL_testudata(L, 2, API_TYPE_NET_UDP)
  ) {
    return luaL_argerror(L, 2, "expected tcp or udp socket");
  }

  Connection* conn = NULL;
  if (luaL_testudata(L, 2, API_TYPE_NET_TCP))
    conn = luaL_checkudata(L, 2, API_TYPE_NET_TCP);
  else if(luaL_testudata(L, 2, API_TYPE_NET_UDP))
    conn = luaL_checkudata(L, 2, API_TYPE_NET_UDP);

  int len = SDLNet_DelSocket(self, conn->socket);
  if (len < 0) {
    lua_pushnil(L);
    lua_pushstring(L, SDLNet_GetError());
    return 2;
  }

  /* remove reference of socket from set to allow garbage collection */
  lua_rawgeti(L, 1, 2);
  lua_pushnil(L);
  lua_rawsetp(L, -2, conn);
  lua_pop(L, 1);

  lua_pushinteger(L, len);

  return 1;
}

static int m_set_check_sockets(lua_State* L) {
  SDLNet_SocketSet self = pull_set(L, 1);
  if (!self) return luaL_typeerror(L, 1, "set");

  unsigned int timeout = luaL_optinteger(L, 2, 0);

  int ready = SDLNet_CheckSockets(self, timeout);
  if (ready == -1) {
    lua_pushnil(L);
    lua_pushstring(L, SDLNet_GetError());
    return 2;
  }

  lua_pushinteger(L, ready);

  return 1;
}

static int mm_set_gc(lua_State* L) {
  SDLNet_SocketSet self = pull_set(L, 1);

  /* remove references to all sockets to allow garbage collection */
  lua_pushnil(L);
  lua_rawseti(L, 1, 2);

  SDLNet_FreeSocketSet(self);

  return 0;
}

/******************************************************************************/
/* TCP Methods                                                                */
/******************************************************************************/

static int m_tcp_accept(lua_State* L) {
  Connection* self = (Connection*) luaL_checkudata(L, 1, API_TYPE_NET_TCP);

  TCPsocket client_socket = SDLNet_TCP_Accept(self->socket);

  if (client_socket == NULL) {
    lua_pushnil(L);
    lua_pushstring(L, SDLNet_GetError());
    return 2;
  }

  Connection* client = lua_newuserdata(L, sizeof(Connection));
  client->type = TCP;
  client->socket = client_socket;
  client->closed = false;

  luaL_setmetatable(L, API_TYPE_NET_TCP);

  return 1;
}

static int m_tcp_get_peer_address(lua_State* L) {
  Connection* self = (Connection*) luaL_checkudata(L, 1, API_TYPE_NET_TCP);

  IPaddress* address = SDLNet_TCP_GetPeerAddress(self->socket);

  if (address == NULL) {
    lua_pushnil(L);
    return 1;
  }

  push_address(L, address);

  return 1;
}

static int m_tcp_send(lua_State* L) {
  Connection* self = (Connection*) luaL_checkudata(L, 1, API_TYPE_NET_TCP);

  size_t data_len = 0;
  const char* data = luaL_checklstring(L, 2, &data_len);

  size_t sent = SDLNet_TCP_Send(self->socket, data, data_len);

  if (sent < data_len) {
    lua_pushboolean(L, 0);
    lua_pushstring(L, SDLNet_GetError());
    return 2;
  }

  lua_pushboolean(L, 1);

  return 1;
}

static int m_tcp_receive(lua_State* L) {
  Connection* self = (Connection*) luaL_checkudata(L, 1, API_TYPE_NET_TCP);
  const size_t max_len = luaL_checkinteger(L, 2);

  char* data = malloc(max_len);
  size_t received = SDLNet_TCP_Recv(self->socket, data, max_len);

  int return_count = 1;

  if (received > 0) {
    lua_pushlstring(L, data, received);
  } else {
    lua_pushnil(L);
    lua_pushstring(L, SDLNet_GetError());
    return_count = 2;
  }

  free(data);

  return return_count;
}

static int m_tcp_ready(lua_State* L) {
  Connection* self = (Connection*) luaL_checkudata(L, 1, API_TYPE_NET_TCP);

  if (SDLNet_SocketReady(self->socket) != 0) {
    lua_pushboolean(L, 1);
  }

  lua_pushboolean(L, 0);

  return 1;
}

static int m_tcp_close(lua_State* L) {
  Connection* self = (Connection*) luaL_checkudata(L, 1, API_TYPE_NET_TCP);
  close_connection(self);
  return 0;
}

static int mm_tcp_gc(lua_State* L) {
  return m_tcp_close(L);
}

/******************************************************************************/
/* UDP Methods                                                                */
/******************************************************************************/

static int m_udp_bind(lua_State* L) {
  Connection* self = (Connection*) luaL_checkudata(L, 1, API_TYPE_NET_UDP);
  int channel = luaL_checkinteger(L, 2);

  IPaddress address;
  if (!pull_address(L, 3, &address)) {
    return luaL_argerror(L, 3, "invalid address provided");
  }

  channel = SDLNet_UDP_Bind(self->socket, channel, &address);
  if (channel == -1) {
    lua_pushnil(L);
    lua_pushstring(L, SDLNet_GetError());
    return 2;
  }

  lua_pushinteger(L, channel);

  return 1;
}

static int m_udp_unbind(lua_State* L) {
  Connection* self = (Connection*) luaL_checkudata(L, 1, API_TYPE_NET_UDP);
  int channel = luaL_checkinteger(L, 2);

  SDLNet_UDP_Unbind(self->socket, channel);

  return 0;
}

static int m_udp_get_peer_address(lua_State* L) {
  Connection* self = (Connection*) luaL_checkudata(L, 1, API_TYPE_NET_UDP);
  int channel = luaL_checkinteger(L, 2);

  IPaddress* address = SDLNet_UDP_GetPeerAddress(self->socket, channel);

  if (address == NULL) {
    lua_pushnil(L);
    return 1;
  }

  push_address(L, address);

  return 1;
}

static int m_udp_send(lua_State* L) {
  Connection* self = (Connection*) luaL_checkudata(L, 1, API_TYPE_NET_UDP);

  size_t data_len = 0;
  const char* data = luaL_checklstring(L, 2, &data_len);

  UDPpacket packet;
  packet.data = (unsigned char*) data;
  packet.len = data_len;

  if (lua_type(L, 3) == LUA_TTABLE) {
    IPaddress address;
    if (pull_address(L, 3, &address)) {
      packet.address = address;
      packet.channel = -1;
    } else {
      return luaL_argerror(L, 3, "invalid address provided");
    }
  } else if (lua_type(L, 3) == LUA_TNUMBER) {
    packet.channel = luaL_checkinteger(L, 3);
  } else {
    return luaL_argerror(L, 3, "no channel or address provided");
  }

  int sent = SDLNet_UDP_Send(self->socket, packet.channel, &packet);

  if (sent == 0) {
    lua_pushboolean(L, 0);
    lua_pushstring(L, SDLNet_GetError());
    return 2;
  }

  lua_pushboolean(L, 1);

  return 1;
}

static int m_udp_receive(lua_State* L) {
  Connection* self = (Connection*) luaL_checkudata(L, 1, API_TYPE_NET_UDP);
  size_t max_len = luaL_checkinteger(L, 2);

  UDPpacket* packet = SDLNet_AllocPacket(max_len);

  if (packet == NULL) {
    lua_pushnil(L);
    lua_pushstring(L, SDLNet_GetError());
    return 2;
  }

  size_t received = SDLNet_UDP_Recv(self->socket, packet);

  if (received > 0) {
    lua_pushlstring(L, (const char*) packet->data, packet->len);
    lua_pushboolean(L, 1);
  } else if (received == 0) {
    lua_pushstring(L, "");
    lua_pushboolean(L, 0);
  } else {
    lua_pushnil(L);
    lua_pushstring(L, SDLNet_GetError());
  }

  SDLNet_FreePacket(packet);

  return 1;
}

static int m_udp_ready(lua_State* L) {
  Connection* self = (Connection*) luaL_checkudata(L, 1, API_TYPE_NET_UDP);

  if (SDLNet_SocketReady(self->socket) != 0) {
    lua_pushboolean(L, 1);
  }

  lua_pushboolean(L, 0);

  return 1;
}

static int m_udp_close(lua_State* L) {
  Connection* self = (Connection*) luaL_checkudata(L, 1, API_TYPE_NET_UDP);
  close_connection(self);
  return 0;
}

static int mm_udp_gc(lua_State* L) {
  return m_udp_close(L);
}

static const struct luaL_Reg net_lib[] = {
  { "init",                f_init                },
  { "quit",                f_quit                },
  { "resolve_host",        f_resolve_host        },
  { "resolve_ip",          f_resolve_ip          },
  { "get_local_addresses", f_get_local_addresses },
  { "set",                 f_set                 },
  { "open_tcp",            f_open_tcp            },
  { "open_udp",            f_open_udp            },
  { NULL, NULL}
};

static const struct luaL_Reg net_set_object[] = {
  { "add",              m_set_add           },
  { "delete",           m_set_delete        },
  { "check_sockets",    m_set_check_sockets },
  { "__gc",             mm_set_gc           },
  { NULL, NULL}
};

static const struct luaL_Reg net_tcp_object[] = {
  { "accept",           m_tcp_accept           },
  { "get_peer_address", m_tcp_get_peer_address },
  { "send",             m_tcp_send             },
  { "receive",          m_tcp_receive          },
  { "ready",            m_tcp_ready            },
  { "close",            m_tcp_close            },
  { "__gc",             mm_tcp_gc              },
  { NULL, NULL}
};

static const struct luaL_Reg net_udp_object[] = {
  { "bind",             m_udp_bind             },
  { "unbind",           m_udp_unbind           },
  { "get_peer_address", m_udp_get_peer_address },
  { "send",             m_udp_send             },
  { "receive",          m_udp_receive          },
  { "ready",            m_udp_ready            },
  { "close",            m_udp_close            },
  { "__gc",             mm_udp_gc              },
  { NULL, NULL}
};


int luaopen_net(lua_State *L) {
  luaL_newmetatable(L, API_TYPE_NET_SET);
  luaL_setfuncs(L, net_set_object, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");

  luaL_newmetatable(L, API_TYPE_NET_TCP);
  luaL_setfuncs(L, net_tcp_object, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");

  luaL_newmetatable(L, API_TYPE_NET_UDP);
  luaL_setfuncs(L, net_udp_object, 0);
  lua_pushvalue(L, -1);
  lua_setfield(L, -2, "__index");

  luaL_newlib(L, net_lib);

  return 1;
}
