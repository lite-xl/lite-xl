/**
 * Basic binding of reproc into Lua.
 * @copyright Jefferson Gonzalez
 * @license MIT
 */

#include <string.h>
#include <stdbool.h>
#include <stdlib.h>
#include <reproc/reproc.h>
#include "api.h"

#define READ_BUF_SIZE 4096

typedef struct {
    reproc_t * process;
    lua_State* L;

} process_t;

static int process_new(lua_State* L)
{
    process_t* self = (process_t*) lua_newuserdata(
        L, sizeof(process_t)
    );

    memset(self, 0, sizeof(process_t));

    self->process = NULL;
    self->L = L;

    luaL_getmetatable(L, API_TYPE_PROCESS);
    lua_setmetatable(L, -2);

    return 1;
}

static int process_strerror(lua_State* L)
{
    int error_code = luaL_checknumber(L, 1);

    if(error_code){
        lua_pushstring(
            L,
            reproc_strerror(error_code)
        );
    } else {
        lua_pushnil(L);
    }

    return 1;
}

static int process_gc(lua_State* L)
{
    process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);

    if(self->process){
        reproc_kill(self->process);
        reproc_destroy(self->process);
        self->process = NULL;
    }

    return 0;
}

static int process_start(lua_State* L)
{
    process_t* self = (process_t*) lua_touserdata(L, 1);

    luaL_checktype(L, 2, LUA_TTABLE);

    char* path = NULL;
    size_t path_len = 0;

    if(lua_type(L, 3) == LUA_TSTRING){
        path = (char*) lua_tolstring(L, 3, &path_len);
    }

    size_t deadline = 0;

    if(lua_type(L, 4) == LUA_TNUMBER){
        deadline = lua_tonumber(L, 4);
    }

    size_t table_len = luaL_len(L, 2);
    char* command[table_len+1];
    command[table_len] = NULL;

    int i;
    for(i=1; i<=table_len; i++){
        lua_pushnumber(L, i);
        lua_gettable(L, 2);

        command[i-1] = (char*) lua_tostring(L, -1);

        lua_remove(L, -1);
    }

    if(self->process){
        reproc_kill(self->process);
        reproc_destroy(self->process);
    }

    self->process = reproc_new();

    int out = reproc_start(
        self->process,
        (const char* const*) command,
        (reproc_options){
            .working_directory = path,
            .deadline = deadline,
            .nonblocking=true,
            .redirect.err.type=REPROC_REDIRECT_PIPE
        }
    );

    if(out > 0) {
        lua_pushboolean(L, 1);
    }
    else {
        reproc_destroy(self->process);
        self->process = NULL;
        lua_pushnumber(L, out);
    }

    return 1;
}

static int process_pid(lua_State* L)
{
    process_t* self = (process_t*) lua_touserdata(L, 1);

    if(self->process){
        int id = reproc_pid(self->process);
        
        if(id > 0){
            lua_pushnumber(L, id);
        } else {
            lua_pushnumber(L, 0);
        }
    } else {
        lua_pushnumber(L, 0);
    }

    return 1;
}

static int g_read(lua_State* L, int stream)
{
    process_t* self = (process_t*) lua_touserdata(L, 1);

    if(self->process){
        int read_size = READ_BUF_SIZE;
        if (lua_type(L, 2) == LUA_TNUMBER){
            read_size = (int) lua_tonumber(L, 2);
        }

        int tries = 1;
        if (lua_type(L, 3) == LUA_TNUMBER){
            tries = (int) lua_tonumber(L, 3);
        }

        int out = 0;
        uint8_t buffer[read_size];

        int runs;
        for (runs=0; runs<tries; runs++){
            out = reproc_read(
                self->process,
                REPROC_STREAM_OUT,
                buffer,
                read_size
            );

            if (out >= 0)
                break;
        }

        if(out == REPROC_EPIPE){
            reproc_kill(self->process);
            reproc_destroy(self->process);
            self->process = NULL;

            lua_pushnil(L);
        } else if(out > 0) {
            lua_pushlstring(L, (const char*) buffer, out);
        } else {
            lua_pushnil(L);
        }
    } else {
        lua_pushnil(L);
    }

    return 1;
}

static int process_read(lua_State* L)
{
    return g_read(L, REPROC_STREAM_OUT);
}

static int process_read_errors(lua_State* L)
{
    return g_read(L, REPROC_STREAM_ERR);
}

static int process_write(lua_State* L)
{
    process_t* self = (process_t*) lua_touserdata(L, 1);

    if(self->process){
        size_t data_size = 0;
        const char* data = luaL_checklstring(L, 2, &data_size);

        int out = 0;

        out = reproc_write(
            self->process,
            (uint8_t*) data,
            data_size
        );

        if(out == REPROC_EPIPE){
            reproc_kill(self->process);
            reproc_destroy(self->process);
            self->process = NULL;
        }

        lua_pushnumber(L, out);
    } else {
        lua_pushnumber(L, REPROC_EPIPE);
    }

    return 1;
}

static int process_close_stream(lua_State* L)
{
    process_t* self = (process_t*) lua_touserdata(L, 1);

    if(self->process){
        size_t stream = luaL_checknumber(L, 2);

        int out = reproc_close(self->process, stream);

        lua_pushnumber(L, out);
    } else {
        lua_pushnumber(L, REPROC_EINVAL);
    }

    return 1;
}

static int process_wait(lua_State* L)
{
    process_t* self = (process_t*) lua_touserdata(L, 1);

    if(self->process){
        size_t timeout = luaL_checknumber(L, 2);

        int out = reproc_wait(self->process, timeout);

        if(out >= 0){
            reproc_destroy(self->process);
            self->process = NULL;
        }

        lua_pushnumber(L, out);
    } else {
        lua_pushnumber(L, REPROC_EINVAL);
    }

    return 1;
}

static int process_terminate(lua_State* L)
{
    process_t* self = (process_t*) lua_touserdata(L, 1);

    if(self->process){
        int out = reproc_terminate(self->process);

        if(out < 0){
            lua_pushnumber(L, out);
        } else {
            reproc_destroy(self->process);
            self->process = NULL;
            lua_pushboolean(L, 1);
        }
    } else {
        lua_pushnumber(L, REPROC_EINVAL);
    }

    return 1;
}

static int process_kill(lua_State* L)
{
    process_t* self = (process_t*) lua_touserdata(L, 1);

    if(self->process){
        int out = reproc_kill(self->process);

        if(out < 0){
            lua_pushnumber(L, out);
        } else {
            reproc_destroy(self->process);
            self->process = NULL;
            lua_pushboolean(L, 1);
        }
    } else {
        lua_pushnumber(L, REPROC_EINVAL);
    }

    return 1;
}

static int process_running(lua_State* L)
{
    process_t* self = (process_t*) lua_touserdata(L, 1);

    if(self->process){
        lua_pushboolean(L, 1);
    } else {
        lua_pushboolean(L, 0);
    }

    return 1;
}

static const struct luaL_Reg process_methods[] = {
    { "__gc", process_gc},
    {"start", process_start},
    {"pid", process_pid},
    {"read", process_read},
    {"read_errors", process_read_errors},
    {"write", process_write},
    {"close_stream", process_close_stream},
    {"wait", process_wait},
    {"terminate", process_terminate},
    {"kill", process_kill},
    {"running", process_running},
    {NULL, NULL}
};

static const struct luaL_Reg process[] = {
    {"new", process_new},
    {"strerror", process_strerror},
    {"ERROR_PIPE", NULL},
    {"ERROR_WOULDBLOCK", NULL},
    {"ERROR_TIMEDOUT", NULL},
    {"ERROR_INVALID", NULL},
    {"STREAM_STDIN", NULL},
    {"STREAM_STDOUT", NULL},
    {"STREAM_STDERR", NULL},
    {"WAIT_INFINITE", NULL},
    {"WAIT_DEADLINE", NULL},
    {NULL, NULL}
};

int luaopen_process(lua_State *L)
{
    luaL_newmetatable(L, API_TYPE_PROCESS);
    luaL_setfuncs(L, process_methods, 0);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    luaL_newlib(L, process);

    lua_pushnumber(L, REPROC_EPIPE);
    lua_setfield(L, -2, "ERROR_PIPE");

    lua_pushnumber(L, REPROC_EWOULDBLOCK);
    lua_setfield(L, -2, "ERROR_WOULDBLOCK");

    lua_pushnumber(L, REPROC_ETIMEDOUT);
    lua_setfield(L, -2, "ERROR_TIMEDOUT");

    lua_pushnumber(L, REPROC_EINVAL);
    lua_setfield(L, -2, "ERROR_INVALID");

    lua_pushnumber(L, REPROC_STREAM_IN);
    lua_setfield(L, -2, "STREAM_STDIN");

    lua_pushnumber(L, REPROC_STREAM_OUT);
    lua_setfield(L, -2, "STREAM_STDOUT");

    lua_pushnumber(L, REPROC_STREAM_ERR);
    lua_setfield(L, -2, "STREAM_STDERR");

    return 1;
}
