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

#define READ_BUF_SIZE 2048

#define L_GETTABLE(L, idx, key, conv, def) (  \
    lua_getfield(L, idx, key),                \
    conv(L, -1, def)                          \
)

#define L_GETNUM(L, idx, key, def) L_GETTABLE(L, idx, key, luaL_optnumber, def)
#define L_GETSTR(L, idx, key, def) L_GETTABLE(L, idx, key, luaL_optstring, def)

#define L_SETNUM(L, idx, key, n) (lua_pushnumber(L, n), lua_setfield(L, idx - 1, key))

#define L_RETURN_REPROC_ERROR(L, code) {      \
    lua_pushnil(L);                           \
    lua_pushstring(L, reproc_strerror(code)); \
    lua_pushnumber(L, code);                  \
    return 3;                                 \
}

#define ASSERT_MALLOC(ptr)                      \
    if (ptr == NULL)                            \
        L_RETURN_REPROC_ERROR(L, REPROC_ENOMEM)

#define ASSERT_REPROC_ERRNO(L, code) { \
    if (code < 0)                      \
        L_RETURN_REPROC_ERROR(L, code) \
}

typedef struct {
    reproc_t * process;
    bool running;
    int returncode;
} process_t;

// this function should be called instead of reproc_wait
static int poll_process(process_t* proc, int timeout)
{
    int ret = reproc_wait(proc->process, timeout);
    if (ret != REPROC_ETIMEDOUT) {
        proc->running = false;
        proc->returncode = ret;
    }
    return ret;
}

static int kill_process(process_t* proc)
{
    int ret = reproc_stop(
        proc->process,
        (reproc_stop_actions) {
            {REPROC_STOP_KILL, 0},
            {REPROC_STOP_TERMINATE, 0},
            {REPROC_STOP_NOOP, 0}
        }
    );

    if (ret != REPROC_ETIMEDOUT) {
        proc->running = false;
        proc->returncode = ret;
    }

    return ret;
}

static int process_start(lua_State* L)
{
    luaL_checktype(L, 1, LUA_TTABLE);
    if (lua_isnoneornil(L, 2)) {
        lua_settop(L, 1); // remove the nil if it's there
        lua_newtable(L);
    }
    luaL_checktype(L, 2, LUA_TTABLE);

    int cmd_len = lua_rawlen(L, 1);
    const char** cmd = malloc(sizeof(char *) * (cmd_len + 1));
    ASSERT_MALLOC(cmd);
    cmd[cmd_len] = NULL;

    for(int i = 0; i < cmd_len; i++) {
        lua_rawgeti(L, 1, i + 1);

        cmd[i] = luaL_checkstring(L, -1);
        lua_pop(L, 1);
    }

    int deadline = L_GETNUM(L, 2, "timeout", 0);
    const char* cwd =L_GETSTR(L, 2, "cwd", NULL);
    int redirect_in = L_GETNUM(L, 2, "stdin", REPROC_REDIRECT_DEFAULT);
    int redirect_out = L_GETNUM(L, 2, "stdout", REPROC_REDIRECT_DEFAULT);
    int redirect_err = L_GETNUM(L, 2, "stderr", REPROC_REDIRECT_DEFAULT);
    lua_pop(L, 5); // remove args we just read

    if (
        redirect_in > REPROC_REDIRECT_STDOUT
        || redirect_out > REPROC_REDIRECT_STDOUT
        || redirect_err > REPROC_REDIRECT_STDOUT)
    {
        lua_pushnil(L);
        lua_pushliteral(L, "redirect to handles, FILE* and paths are not supported");
        return 2;
    }

    // env
    luaL_getsubtable(L, 2, "env");
    const char **env = NULL;
    int env_len = 0;

    lua_pushnil(L); 
    while (lua_next(L, -2) != 0) {
        env_len++;
        lua_pop(L, 1);
    }

    if (env_len > 0) {
        env = malloc(sizeof(char*) * (env_len + 1));
        env[env_len] = NULL;

        int i = 0;
        lua_pushnil(L);
        while (lua_next(L, -2) != 0) {
            lua_pushliteral(L, "=");
            lua_pushvalue(L, -3); // push the key to the top
            lua_concat(L, 3); // key=value

            env[i++] = luaL_checkstring(L, -1);
            lua_pop(L, 1);
        }
    }

    reproc_t* proc = reproc_new();
    int out = reproc_start(
        proc,
        (const char* const*) cmd,
        (reproc_options) {
            .working_directory = cwd,
            .deadline = deadline,
            .nonblocking = true,
            .env = {
                .behavior = REPROC_ENV_EXTEND,
                .extra = env
            },
            .redirect = {
                .in.type = redirect_in,
                .out.type = redirect_out,
                .err.type = redirect_err
            }
        }
    );

    if (out < 0) {
        reproc_destroy(proc);
        L_RETURN_REPROC_ERROR(L, out);
    }

    process_t* self = lua_newuserdata(L, sizeof(process_t));
    self->process = proc;
    self->running = true;

    // this is equivalent to using lua_setmetatable()
    luaL_setmetatable(L, API_TYPE_PROCESS);
    return 1;
}

static int process_strerror(lua_State* L)
{
    int error_code = luaL_checknumber(L, 1);

    if (error_code < 0)
        lua_pushstring(L, reproc_strerror(error_code));
    else
        lua_pushnil(L);
 
    return 1;
}

static int f_gc(lua_State* L)
{
    process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);

    if(self->process) {
        kill_process(self);
        reproc_destroy(self->process);
        self->process = NULL;
    }

    return 0;
}

static int f_tostring(lua_State* L)
{
    luaL_checkudata(L, 1, API_TYPE_PROCESS);

    lua_pushliteral(L, API_TYPE_PROCESS);
    return 1;
}

static int f_pid(lua_State* L)
{
    process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);

    lua_pushnumber(L, reproc_pid(self->process));
    return 1;
}

static int f_returncode(lua_State *L)
{
    process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
    int ret = poll_process(self, 0);

    if (self->running)
        lua_pushnil(L);
    else
        lua_pushnumber(L, ret);

    return 1;
}

static int g_read(lua_State* L, int stream)
{
    process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
    unsigned long read_size = luaL_optunsigned(L, 2, READ_BUF_SIZE);

    luaL_Buffer b;
    uint8_t* buffer = (uint8_t*) luaL_buffinitsize(L, &b, read_size);

    int out = reproc_read(
        self->process,
        stream,
        buffer,
        read_size
    );

    if (out >= 0)
        luaL_addsize(&b, out); 
    luaL_pushresult(&b);

    if (out == REPROC_EPIPE) {
        kill_process(self);
        ASSERT_REPROC_ERRNO(L, out);
    }

    return 1;
}

static int f_read_stdout(lua_State* L)
{
    return g_read(L, REPROC_STREAM_OUT);
}

static int f_read_stderr(lua_State* L)
{
    return g_read(L, REPROC_STREAM_ERR);
}

static int f_read(lua_State* L)
{
    int stream = luaL_checknumber(L, 2);
    lua_remove(L, 2);
    if (stream > REPROC_STREAM_ERR)
        L_RETURN_REPROC_ERROR(L, REPROC_EINVAL);

    return g_read(L, stream);
}

static int f_write(lua_State* L)
{
    process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);

    size_t data_size = 0;
    const char* data = luaL_checklstring(L, 2, &data_size);

    int out = reproc_write(
        self->process,
        (uint8_t*) data,
        data_size
    );
    if (out == REPROC_EPIPE) {
        kill_process(self);
        L_RETURN_REPROC_ERROR(L, out);
    }

    lua_pushnumber(L, out);
    return 1;
}

static int f_close_stream(lua_State* L)
{
    process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);

    int stream = luaL_checknumber(L, 2);
    int out = reproc_close(self->process, stream);
    ASSERT_REPROC_ERRNO(L, out);

    lua_pushboolean(L, 1);
    return 1;
}

static int f_wait(lua_State* L)
{
    process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
    
    int timeout = luaL_optnumber(L, 2, 0);
    
    int ret = poll_process(self, timeout);
    // negative returncode is also used for signals on POSIX
    if (ret == REPROC_ETIMEDOUT)
        L_RETURN_REPROC_ERROR(L, ret);

    lua_pushnumber(L, ret);
    return 1;
}

static int f_terminate(lua_State* L)
{
    process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);

    int out = reproc_terminate(self->process);
    ASSERT_REPROC_ERRNO(L, out);

    poll_process(self, 0);
    lua_pushboolean(L, 1);

    return 1;
}

static int f_kill(lua_State* L)
{
    process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);

    int out = reproc_kill(self->process);
    ASSERT_REPROC_ERRNO(L, out);

    poll_process(self, 0);
    lua_pushboolean(L, 1);

    return 1;
}

static int f_running(lua_State* L)
{
    process_t* self = (process_t*) luaL_checkudata(L, 1, API_TYPE_PROCESS);
    
    poll_process(self, 0);
    lua_pushboolean(L, self->running);

    return 1;
}

static const struct luaL_Reg lib[] = {
    {"start", process_start},
    {"strerror", process_strerror},
    {"__gc", f_gc},
    {"__tostring", f_tostring},
    {"pid", f_pid},
    {"returncode", f_returncode},
    {"read", f_read},
    {"read_stdout", f_read_stdout},
    {"read_stderr", f_read_stderr},
    {"write", f_write},
    {"close_stream", f_close_stream},
    {"wait", f_wait},
    {"terminate", f_terminate},
    {"kill", f_kill},
    {"running", f_running},
    {NULL, NULL}
};

int luaopen_process(lua_State *L)
{
    luaL_newmetatable(L, API_TYPE_PROCESS);
    luaL_setfuncs(L, lib, 0);
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    // constants
    L_SETNUM(L, -1, "ERROR_INVAL", REPROC_EINVAL);
    L_SETNUM(L, -1, "ERROR_TIMEDOUT", REPROC_ETIMEDOUT);
    L_SETNUM(L, -1, "ERROR_PIPE", REPROC_EPIPE);
    L_SETNUM(L, -1, "ERROR_NOMEM", REPROC_ENOMEM);
    L_SETNUM(L, -1, "ERROR_WOULDBLOCK", REPROC_EWOULDBLOCK);

    L_SETNUM(L, -1, "WAIT_INFINITE", REPROC_INFINITE);
    L_SETNUM(L, -1, "WAIT_DEADLINE", REPROC_DEADLINE);

    L_SETNUM(L, -1, "STREAM_STDIN", REPROC_STREAM_IN);
    L_SETNUM(L, -1, "STREAM_STDOUT", REPROC_STREAM_OUT);
    L_SETNUM(L, -1, "STREAM_STDERR", REPROC_STREAM_ERR);

    L_SETNUM(L, -1, "REDIRECT_DEFAULT", REPROC_REDIRECT_DEFAULT);
    L_SETNUM(L, -1, "REDIRECT_PIPE", REPROC_REDIRECT_PIPE);
    L_SETNUM(L, -1, "REDIRECT_PARENT", REPROC_REDIRECT_PARENT);
    L_SETNUM(L, -1, "REDIRECT_DISCARD", REPROC_REDIRECT_DISCARD);
    L_SETNUM(L, -1, "REDIRECT_STDOUT", REPROC_REDIRECT_STDOUT);

    return 1;
}
