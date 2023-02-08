#ifndef LITE_XL_PLUGIN_API
#define LITE_XL_PLUGIN_API
/**
The lite_xl plugin API is quite simple. Any shared library can be a plugin file, so long
as it has an entrypoint that looks like the following, where xxxxx is the plugin name:

#define LITE_XL_PLUGIN_ENTRYPOINT
#include "lite_xl_plugin_api.h"
int luaopen_lite_xl_xxxxx(lua_State* L, void* XL) {
  lite_xl_plugin_init(XL);
  ...
  return 1;
}

NOTE: `#define LITE_XL_PLUGIN_ENTRYPOINT` needs to be defined only on the
source file where the lite_xl_plugin_init() initialization function is called.

In linux, to compile this file, you'd do: 'gcc -o xxxxx.so -shared xxxxx.c'. Simple!
Due to the way the API is structured, you *should not* link or include lua libraries.
This file was automatically generated. DO NOT MODIFY DIRECTLY.

UNLESS you're us, and you had to modify this file manually to get it ready for 2.1.

Go figure.

**/


#include <stdarg.h>
#include <stdio.h> // for BUFSIZ? this is kinda weird
#include <stdlib.h>

#define SYMBOL_WRAP_DECL(ret, name, ...) \
  ret name(__VA_ARGS__)

#define SYMBOL_WRAP_CALL(name, ...) \
  return __##name(__VA_ARGS__)

#define SYMBOL_WRAP_CALL_FB(name, ...) \
  return __lite_xl_fallback_##name(__VA_ARGS__)

#ifdef LITE_XL_PLUGIN_ENTRYPOINT
  #define SYMBOL_DECLARE(ret, name, ...) \
    static ret (*__##name)  (__VA_ARGS__); \
    SYMBOL_WRAP_DECL(ret, name, __VA_ARGS__); \
    static ret __lite_xl_fallback_##name(__VA_ARGS__) { \
      fputs("warning: " #name " is a stub", stderr); \
      exit(1); \
    }
#else
  #define SYMBOL_DECLARE(ret, name, ...) \
    SYMBOL_WRAP_DECL(ret, name, __VA_ARGS__);
#endif

/** luaconf.h **/

#ifndef lconfig_h
#define lconfig_h
#include <limits.h>
#include <stddef.h>
#if !defined(LUA_ANSI) && defined(__STRICT_ANSI__)
#define LUA_ANSI
#endif
#if !defined(LUA_ANSI) && defined(_WIN32) && !defined(_WIN32_WCE)
#define LUA_WIN
#endif
#if defined(LUA_WIN)
#define LUA_DL_DLL
#define LUA_USE_AFORMAT
#endif
#if defined(LUA_USE_LINUX)
#define LUA_USE_POSIX
#define LUA_USE_DLOPEN
#define LUA_USE_READLINE
#define LUA_USE_STRTODHEX
#define LUA_USE_AFORMAT
#define LUA_USE_LONGLONG
#endif
#if defined(LUA_USE_MACOSX)
#define LUA_USE_POSIX
#define LUA_USE_DLOPEN
#define LUA_USE_READLINE
#define LUA_USE_STRTODHEX
#define LUA_USE_AFORMAT
#define LUA_USE_LONGLONG
#endif
#if defined(LUA_USE_POSIX)
#define LUA_USE_MKSTEMP
#define LUA_USE_ISATTY
#define LUA_USE_POPEN
#define LUA_USE_ULONGJMP
#define LUA_USE_GMTIME_R
#endif
#if defined(_WIN32)
#define LUA_LDIR "!\\lua\\"
#define LUA_CDIR "!\\"
#define LUA_PATH_DEFAULT LUA_LDIR"?.lua;" LUA_LDIR"?\\init.lua;" LUA_CDIR"?.lua;" LUA_CDIR"?\\init.lua;" ".\\?.lua"
#define LUA_CPATH_DEFAULT LUA_CDIR"?.dll;" LUA_CDIR"loadall.dll;" ".\\?.dll"
#else
#define LUA_VDIR LUA_VERSION_MAJOR "." LUA_VERSION_MINOR "/"
#define LUA_ROOT "/usr/local/"
#define LUA_LDIR LUA_ROOT "share/lua/" LUA_VDIR
#define LUA_CDIR LUA_ROOT "lib/lua/" LUA_VDIR
#define LUA_PATH_DEFAULT LUA_LDIR"?.lua;" LUA_LDIR"?/init.lua;" LUA_CDIR"?.lua;" LUA_CDIR"?/init.lua;" "./?.lua"
#define LUA_CPATH_DEFAULT LUA_CDIR"?.so;" LUA_CDIR"loadall.so;" "./?.so"
#endif
#if defined(_WIN32)
#define LUA_DIRSEP "\\"
#else
#define LUA_DIRSEP "/"
#endif
#define LUA_ENV "_ENV"
#if defined(LUA_BUILD_AS_DLL)
#if defined(LUA_CORE) || defined(LUA_LIB)
#define LUA_API __declspec(dllexport)
#else
#define LUA_API __declspec(dllimport)
#endif
#else
#define LUA_API extern
#endif
#define LUALIB_API LUA_API
#define LUAMOD_API LUALIB_API
#if defined(__GNUC__) && ((__GNUC__*100 + __GNUC_MINOR__) >= 302) && defined(__ELF__)
#define LUAI_FUNC __attribute__((visibility("hidden"))) extern
#define LUAI_DDEC LUAI_FUNC
#define LUAI_DDEF
#else
#define LUAI_FUNC extern
#define LUAI_DDEC extern
#define LUAI_DDEF
#endif
#define LUA_QL(x) "'" x "'"
#define LUA_QS LUA_QL("%s")
#define LUA_IDSIZE 60
#if defined(LUA_LIB) || defined(lua_c)
#include <stdio.h>
#define luai_writestring(s,l) fwrite((s), sizeof(char), (l), stdout)
#define luai_writeline() (luai_writestring("\n", 1), fflush(stdout))
#endif
#define luai_writestringerror(s,p) (fprintf(stderr, (s), (p)), fflush(stderr))
#define LUAI_MAXSHORTLEN 40
#if defined(LUA_COMPAT_ALL)
#define LUA_COMPAT_UNPACK
#define LUA_COMPAT_LOADERS
#define lua_cpcall(L,f,u) (lua_pushcfunction(L, (f)), lua_pushlightuserdata(L,(u)), lua_pcall(L,1,0,0))
#define LUA_COMPAT_LOG10
#define LUA_COMPAT_LOADSTRING
#define LUA_COMPAT_MAXN
#define lua_strlen(L,i) lua_rawlen(L, (i))
#define lua_objlen(L,i) lua_rawlen(L, (i))
#define lua_equal(L,idx1,idx2) lua_compare(L,(idx1),(idx2),LUA_OPEQ)
#define lua_lessthan(L,idx1,idx2) lua_compare(L,(idx1),(idx2),LUA_OPLT)
#define LUA_COMPAT_MODULE
#endif
#if INT_MAX-20 < 32760
#define LUAI_BITSINT 16
#elif INT_MAX > 2147483640L
#define LUAI_BITSINT 32
#else
#error "you must define LUA_BITSINT with number of bits in an integer"
#endif
#if LUAI_BITSINT >= 32
#define LUA_INT32 int
#define LUAI_UMEM size_t
#define LUAI_MEM ptrdiff_t
#else
#define LUA_INT32 long
#define LUAI_UMEM unsigned long
#define LUAI_MEM long
#endif
#if LUAI_BITSINT >= 32
#define LUAI_MAXSTACK 1000000
#else
#define LUAI_MAXSTACK 15000
#endif
#define LUAI_FIRSTPSEUDOIDX (-LUAI_MAXSTACK - 1000)
#define LUAL_BUFFERSIZE BUFSIZ
#define LUA_NUMBER_DOUBLE
#define LUA_NUMBER double
#define LUAI_UACNUMBER double
#define LUA_NUMBER_SCAN "%lf"
#define LUA_NUMBER_FMT "%.14g"
#define lua_number2str(s,n) sprintf((s), LUA_NUMBER_FMT, (n))
#define LUAI_MAXNUMBER2STR 32
#define l_mathop(x) (x)
#define lua_str2number(s,p) strtod((s), (p))
#if defined(LUA_USE_STRTODHEX)
#define lua_strx2number(s,p) strtod((s), (p))
#endif
#if defined(lobject_c) || defined(lvm_c)
#include <math.h>
#define luai_nummod(L,a,b) ((a) - l_mathop(floor)((a)/(b))*(b))
#define luai_numpow(L,a,b) (l_mathop(pow)(a,b))
#endif
#if defined(LUA_CORE)
#define luai_numadd(L,a,b) ((a)+(b))
#define luai_numsub(L,a,b) ((a)-(b))
#define luai_nummul(L,a,b) ((a)*(b))
#define luai_numdiv(L,a,b) ((a)/(b))
#define luai_numunm(L,a) (-(a))
#define luai_numeq(a,b) ((a)==(b))
#define luai_numlt(L,a,b) ((a)<(b))
#define luai_numle(L,a,b) ((a)<=(b))
#define luai_numisnan(L,a) (!luai_numeq((a), (a)))
#endif
#define LUA_INTEGER ptrdiff_t
#define LUA_KCONTEXT ptrdiff_t
#define LUA_UNSIGNED unsigned LUA_INT32
#if defined(LUA_NUMBER_DOUBLE) && !defined(LUA_ANSI)
#if defined(LUA_WIN) && defined(_MSC_VER) && defined(_M_IX86)
#define LUA_MSASMTRICK
#define LUA_IEEEENDIAN 0
#define LUA_NANTRICK
#elif defined(__i386__) || defined(__i386) || defined(__X86__)
#define LUA_IEEE754TRICK
#define LUA_IEEELL
#define LUA_IEEEENDIAN 0
#define LUA_NANTRICK
#elif defined(__x86_64)
#define LUA_IEEE754TRICK
#define LUA_IEEEENDIAN 0
#elif defined(__POWERPC__) || defined(__ppc__)
#define LUA_IEEE754TRICK
#define LUA_IEEEENDIAN 1
#else
#define LUA_IEEE754TRICK
#endif
#endif
#endif

/** lua.h **/

typedef struct lua_State lua_State;
typedef int (*lua_CFunction) (lua_State *L);
typedef const char * (*lua_Reader) (lua_State *L, void *ud, size_t *sz);
typedef int (*lua_Writer) (lua_State *L, const void* p, size_t sz, void* ud);
typedef void * (*lua_Alloc) (void *ud, void *ptr, size_t osize, size_t nsize);
typedef LUA_KCONTEXT lua_KContext;
typedef LUA_NUMBER lua_Number;
typedef LUA_INTEGER lua_Integer;
typedef LUA_UNSIGNED lua_Unsigned;
typedef struct lua_Debug lua_Debug;
typedef int (*lua_KFunction) (lua_State *L, int status, lua_KContext ctx);
typedef void (*lua_Hook) (lua_State *L, lua_Debug *ar);
struct lua_Debug {
  int event;
  const char *name;
  const char *namewhat;
  const char *what;
  const char *source;
  int currentline;
  int linedefined;
  int lastlinedefined;
  unsigned char nups;
  unsigned char nparams;
  char isvararg;
  char istailcall;
  char short_src[LUA_IDSIZE];
  struct CallInfo *i_ci;
};

SYMBOL_DECLARE(lua_State *,        lua_newstate,          lua_Alloc f, void *ud)
SYMBOL_DECLARE(void,               lua_close,             lua_State *L)
SYMBOL_DECLARE(lua_State *,        lua_newthread,         lua_State *L)
SYMBOL_DECLARE(lua_CFunction,      lua_atpanic,           lua_State *L, lua_CFunction panicf)
SYMBOL_DECLARE(const lua_Number *, lua_version,           lua_State *L)
SYMBOL_DECLARE(int,                lua_absindex,          lua_State *L, int idx)
SYMBOL_DECLARE(int,                lua_gettop,            lua_State *L)
SYMBOL_DECLARE(void,               lua_settop,            lua_State *L, int idx)
SYMBOL_DECLARE(void,               lua_pushvalue,         lua_State *L, int idx)
SYMBOL_DECLARE(void,               lua_copy,              lua_State *L, int fromidx, int toidx)
SYMBOL_DECLARE(int,                lua_checkstack,        lua_State *L, int sz)
SYMBOL_DECLARE(void,               lua_xmove,             lua_State *from, lua_State *to, int n)
SYMBOL_DECLARE(int,                lua_isnumber,          lua_State *L, int idx)
SYMBOL_DECLARE(int,                lua_isstring,          lua_State *L, int idx)
SYMBOL_DECLARE(int,                lua_iscfunction,       lua_State *L, int idx)
SYMBOL_DECLARE(int,                lua_isuserdata,        lua_State *L, int idx)
SYMBOL_DECLARE(int,                lua_type,              lua_State *L, int idx)
SYMBOL_DECLARE(const char *,       lua_typename,          lua_State *L, int tp)
SYMBOL_DECLARE(lua_Number,         lua_tonumberx,         lua_State *L, int idx, int *isnum)
SYMBOL_DECLARE(lua_Integer,        lua_tointegerx,        lua_State *L, int idx, int *isnum)
SYMBOL_DECLARE(lua_Unsigned,       lua_tounsignedx,       lua_State *L, int idx, int *isnum)
SYMBOL_DECLARE(int,                lua_toboolean,         lua_State *L, int idx)
SYMBOL_DECLARE(const char *,       lua_tolstring,         lua_State *L, int idx, size_t *len)
SYMBOL_DECLARE(size_t,             lua_rawlen,            lua_State *L, int idx)
SYMBOL_DECLARE(lua_CFunction,      lua_tocfunction,       lua_State *L, int idx)
SYMBOL_DECLARE(void *,             lua_touserdata,        lua_State *L, int idx)
SYMBOL_DECLARE(lua_State *,        lua_tothread,          lua_State *L, int idx)
SYMBOL_DECLARE(const void *,       lua_topointer,         lua_State *L, int idx)
SYMBOL_DECLARE(void,               lua_arith,             lua_State *L, int op)
SYMBOL_DECLARE(int,                lua_rawequal,          lua_State *L, int idx1, int idx2)
SYMBOL_DECLARE(int,                lua_compare,           lua_State *L, int idx1, int idx2, int op)
SYMBOL_DECLARE(void,               lua_pushnil,           lua_State *L)
SYMBOL_DECLARE(void,               lua_pushnumber,        lua_State *L, lua_Number n)
SYMBOL_DECLARE(void,               lua_pushinteger,       lua_State *L, lua_Integer n)
SYMBOL_DECLARE(void,               lua_pushunsigned,      lua_State *L, lua_Unsigned n)
SYMBOL_DECLARE(const char *,       lua_pushlstring,       lua_State *L, const char *s, size_t l)
SYMBOL_DECLARE(const char *,       lua_pushstring,        lua_State *L, const char *s)
SYMBOL_DECLARE(const char *,       lua_pushvfstring,      lua_State *L, const char *fmt, va_list argp)
SYMBOL_DECLARE(const char *,       lua_pushfstring,       lua_State *L, const char *fmt, ...)
SYMBOL_DECLARE(void,               lua_pushcclosure,      lua_State *L, lua_CFunction fn, int n)
SYMBOL_DECLARE(void,               lua_pushboolean,       lua_State *L, int b)
SYMBOL_DECLARE(void,               lua_pushlightuserdata, lua_State *L, void *p)
SYMBOL_DECLARE(int,                lua_pushthread,        lua_State *L)
SYMBOL_DECLARE(void,               lua_getglobal,         lua_State *L, const char *var)
SYMBOL_DECLARE(void,               lua_gettable,          lua_State *L, int idx)
SYMBOL_DECLARE(void,               lua_getfield,          lua_State *L, int idx, const char *k)
SYMBOL_DECLARE(void,               lua_rawget,            lua_State *L, int idx)
SYMBOL_DECLARE(void,               lua_rawgeti,           lua_State *L, int idx, int n)
SYMBOL_DECLARE(void,               lua_rawgetp,           lua_State *L, int idx, const void *p)
SYMBOL_DECLARE(void,               lua_createtable,       lua_State *L, int narr, int nrec)
SYMBOL_DECLARE(void *,             lua_newuserdata,       lua_State *L, size_t sz)
SYMBOL_DECLARE(void *,             lua_newuserdatauv,     lua_State *L, size_t sz, int nuvalue)
SYMBOL_DECLARE(int,                lua_getmetatable,      lua_State *L, int objindex)
SYMBOL_DECLARE(void,               lua_getuservalue,      lua_State *L, int idx)
SYMBOL_DECLARE(void,               lua_getiuservalue,     lua_State *L, int idx, int n)
SYMBOL_DECLARE(void,               lua_setglobal,         lua_State *L, const char *var)
SYMBOL_DECLARE(void,               lua_settable,          lua_State *L, int idx)
SYMBOL_DECLARE(void,               lua_setfield,          lua_State *L, int idx, const char *k)
SYMBOL_DECLARE(void,               lua_rawset,            lua_State *L, int idx)
SYMBOL_DECLARE(void,               lua_rawseti,           lua_State *L, int idx, int n)
SYMBOL_DECLARE(void,               lua_rawsetp,           lua_State *L, int idx, const void *p)
SYMBOL_DECLARE(int,                lua_setmetatable,      lua_State *L, int objindex)
SYMBOL_DECLARE(void,               lua_setuservalue,      lua_State *L, int idx)
SYMBOL_DECLARE(void,               lua_setiuservalue,     lua_State *L, int idx, int n)
SYMBOL_DECLARE(void,               lua_callk,             lua_State *L, int nargs, int nresults, lua_KContext ctx, lua_KFunction k)
SYMBOL_DECLARE(int,                lua_getctx,            lua_State *L, int *ctx)
SYMBOL_DECLARE(int,                lua_pcallk,            lua_State *L, int nargs, int nresults, int errfunc, lua_KContext ctx, lua_KFunction k)
SYMBOL_DECLARE(int,                lua_load,              lua_State *L, lua_Reader reader, void *dt, const char *chunkname, const char *mode)
SYMBOL_DECLARE(int,                lua_dump,              lua_State *L, lua_Writer writer, void *data, int strip)
SYMBOL_DECLARE(int,                lua_yieldk,            lua_State *L, int nresults, lua_KContext ctx, lua_KFunction k)
SYMBOL_DECLARE(int,                lua_resume,            lua_State *L, lua_State *from, int narg)
SYMBOL_DECLARE(int,                lua_status,            lua_State *L)
SYMBOL_DECLARE(int,                lua_gc,                lua_State *L, int what, int data)
SYMBOL_DECLARE(int,                lua_error,             lua_State *L)
SYMBOL_DECLARE(int,                lua_next,              lua_State *L, int idx)
SYMBOL_DECLARE(void,               lua_concat,            lua_State *L, int n)
SYMBOL_DECLARE(void,               lua_len,               lua_State *L, int idx)
SYMBOL_DECLARE(lua_Alloc,          lua_getallocf,         lua_State *L, void **ud)
SYMBOL_DECLARE(void,               lua_setallocf,         lua_State *L, lua_Alloc f, void *ud)
SYMBOL_DECLARE(int,                lua_getstack,          lua_State *L, int level, lua_Debug *ar)
SYMBOL_DECLARE(int,                lua_getinfo,           lua_State *L, const char *what, lua_Debug *ar)
SYMBOL_DECLARE(const char *,       lua_getlocal,          lua_State *L, const lua_Debug *ar, int n)
SYMBOL_DECLARE(const char *,       lua_setlocal,          lua_State *L, const lua_Debug *ar, int n)
SYMBOL_DECLARE(const char *,       lua_getupvalue,        lua_State *L, int funcindex, int n)
SYMBOL_DECLARE(const char *,       lua_setupvalue,        lua_State *L, int funcindex, int n)
SYMBOL_DECLARE(void *,             lua_upvalueid,         lua_State *L, int fidx, int n)
SYMBOL_DECLARE(void,               lua_upvaluejoin,       lua_State *L, int fidx1, int n1, int fidx2, int n2)
SYMBOL_DECLARE(int,                lua_sethook,           lua_State *L, lua_Hook func, int mask, int count)
SYMBOL_DECLARE(lua_Hook,           lua_gethook,           lua_State *L)
SYMBOL_DECLARE(int,                lua_gethookmask,       lua_State *L)
SYMBOL_DECLARE(int,                lua_gethookcount,      lua_State *L)

#define lua_h
#define LUA_VERSION_MAJOR "5"
#define LUA_VERSION_MINOR "4"
#define LUA_VERSION_NUM 504
#define LUA_VERSION_RELEASE "4"
#define LUA_VERSION "Lua " LUA_VERSION_MAJOR "." LUA_VERSION_MINOR
#define LUA_RELEASE LUA_VERSION "." LUA_VERSION_RELEASE
#define LUA_COPYRIGHT LUA_RELEASE "  Copyright (C) 1994-2015 Lua.org, PUC-Rio"
#define LUA_AUTHORS "R. Ierusalimschy, L. H. de Figueiredo, W. Celes"
#define LUA_SIGNATURE "\033Lua"
#define LUA_MULTRET (-1)
#define LUA_REGISTRYINDEX LUAI_FIRSTPSEUDOIDX
#define lua_upvalueindex(i) (LUA_REGISTRYINDEX - (i))
#define LUA_OK 0
#define LUA_YIELD 1
#define LUA_ERRRUN 2
#define LUA_ERRSYNTAX 3
#define LUA_ERRMEM 4
#define LUA_ERRGCMM 5
#define LUA_ERRERR 6
#define LUA_TNONE (-1)
#define LUA_TNIL 0
#define LUA_TBOOLEAN 1
#define LUA_TLIGHTUSERDATA 2
#define LUA_TNUMBER 3
#define LUA_TSTRING 4
#define LUA_TTABLE 5
#define LUA_TFUNCTION 6
#define LUA_TUSERDATA 7
#define LUA_TTHREAD 8
#define LUA_NUMTAGS 9
#define LUA_MINSTACK 20
#define LUA_RIDX_MAINTHREAD 1
#define LUA_RIDX_GLOBALS 2
#define LUA_RIDX_LAST LUA_RIDX_GLOBALS
#define LUA_OPADD 0
#define LUA_OPSUB 1
#define LUA_OPMUL 2
#define LUA_OPDIV 3
#define LUA_OPMOD 4
#define LUA_OPPOW 5
#define LUA_OPUNM 6
#define LUA_OPEQ 0
#define LUA_OPLT 1
#define LUA_OPLE 2
#define lua_call(L,n,r) lua_callk(L, (n), (r), 0, NULL)
#define lua_pcall(L,n,r,f) lua_pcallk(L, (n), (r), (f), 0, NULL)
#define lua_yield(L,n) lua_yieldk(L, (n), 0, NULL)
#define LUA_GCSTOP 0
#define LUA_GCRESTART 1
#define LUA_GCCOLLECT 2
#define LUA_GCCOUNT 3
#define LUA_GCCOUNTB 4
#define LUA_GCSTEP 5
#define LUA_GCSETPAUSE 6
#define LUA_GCSETSTEPMUL 7
#define LUA_GCSETMAJORINC 8
#define LUA_GCISRUNNING 9
#define LUA_GCGEN 10
#define LUA_GCINC 11
#define lua_tonumber(L,i) lua_tonumberx(L,i,NULL)
#define lua_tointeger(L,i) lua_tointegerx(L,i,NULL)
#define lua_tounsigned(L,i) lua_tounsignedx(L,i,NULL)
#define lua_pop(L,n) lua_settop(L, -(n)-1)
#define lua_newtable(L) lua_createtable(L, 0, 0)
#define lua_register(L,n,f) (lua_pushcfunction(L, (f)), lua_setglobal(L, (n)))
#define lua_pushcfunction(L,f) lua_pushcclosure(L, (f), 0)
#define lua_isfunction(L,n) (lua_type(L, (n)) == LUA_TFUNCTION)
#define lua_istable(L,n) (lua_type(L, (n)) == LUA_TTABLE)
#define lua_islightuserdata(L,n) (lua_type(L, (n)) == LUA_TLIGHTUSERDATA)
#define lua_isnil(L,n) (lua_type(L, (n)) == LUA_TNIL)
#define lua_isboolean(L,n) (lua_type(L, (n)) == LUA_TBOOLEAN)
#define lua_isthread(L,n) (lua_type(L, (n)) == LUA_TTHREAD)
#define lua_isnone(L,n) (lua_type(L, (n)) == LUA_TNONE)
#define lua_isnoneornil(L, n) (lua_type(L, (n)) <= 0)
#define lua_pushliteral(L, s) lua_pushlstring(L, "" s, (sizeof(s)/sizeof(char))-1)
#define lua_pushglobaltable(L) lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS)
#define lua_tostring(L,i) lua_tolstring(L, (i), NULL)
#define lua_insert(L,idx)   lua_rotate(L, (idx), 1)
#define lua_replace(L,idx)  (lua_copy(L, -1, (idx)), lua_pop(L, 1))
#define lua_remove(L,idx)   (lua_rotate(L, (idx), -1), lua_pop(L, 1))
#define LUA_HOOKCALL 0
#define LUA_HOOKRET 1
#define LUA_HOOKLINE 2
#define LUA_HOOKCOUNT 3
#define LUA_HOOKTAILCALL 4
#define LUA_MASKCALL (1 << LUA_HOOKCALL)
#define LUA_MASKRET (1 << LUA_HOOKRET)
#define LUA_MASKLINE (1 << LUA_HOOKLINE)
#define LUA_MASKCOUNT (1 << LUA_HOOKCOUNT)

/** lauxlib.h **/

typedef struct luaL_Reg {
  const char *name;
  lua_CFunction func;
} luaL_Reg;
typedef struct luaL_Buffer {
  char *b;
  size_t size;
  size_t n;
  lua_State *L;
  char initb[LUAL_BUFFERSIZE];
} luaL_Buffer;
typedef struct luaL_Stream {
  FILE *f;
  lua_CFunction closef;
} luaL_Stream;

SYMBOL_DECLARE(void,         luaL_checkversion_,  lua_State *L, lua_Number ver)
SYMBOL_DECLARE(int,          luaL_getmetafield,   lua_State *L, int obj, const char *e)
SYMBOL_DECLARE(int,          luaL_callmeta,       lua_State *L, int obj, const char *e)
SYMBOL_DECLARE(const char *, luaL_tolstring,      lua_State *L, int idx, size_t *len)
SYMBOL_DECLARE(int,          luaL_argerror,       lua_State *L, int numarg, const char *extramsg)
SYMBOL_DECLARE(const char *, luaL_checklstring,   lua_State *L, int numArg, size_t *l)
SYMBOL_DECLARE(const char *, luaL_optlstring,     lua_State *L, int numArg, const char *def, size_t *l)
SYMBOL_DECLARE(lua_Number,   luaL_checknumber,    lua_State *L, int numArg)
SYMBOL_DECLARE(lua_Number,   luaL_optnumber,      lua_State *L, int nArg, lua_Number def)
SYMBOL_DECLARE(lua_Integer,  luaL_checkinteger,   lua_State *L, int numArg)
SYMBOL_DECLARE(lua_Integer,  luaL_optinteger,     lua_State *L, int nArg, lua_Integer def)
SYMBOL_DECLARE(lua_Unsigned, luaL_checkunsigned,  lua_State *L, int numArg)
SYMBOL_DECLARE(lua_Unsigned, luaL_optunsigned,    lua_State *L, int numArg, lua_Unsigned def)
SYMBOL_DECLARE(void,         luaL_checkstack,     lua_State *L, int sz, const char *msg)
SYMBOL_DECLARE(void,         luaL_checktype,      lua_State *L, int narg, int t)
SYMBOL_DECLARE(void,         luaL_checkany,       lua_State *L, int narg)
SYMBOL_DECLARE(int,          luaL_newmetatable,   lua_State *L, const char *tname)
SYMBOL_DECLARE(void,         luaL_setmetatable,   lua_State *L, const char *tname)
SYMBOL_DECLARE(void *,       luaL_testudata,      lua_State *L, int ud, const char *tname)
SYMBOL_DECLARE(void *,       luaL_checkudata,     lua_State *L, int ud, const char *tname)
SYMBOL_DECLARE(void,         luaL_where,          lua_State *L, int lvl)
SYMBOL_DECLARE(int,          luaL_error,          lua_State *L, const char *fmt, ...)
SYMBOL_DECLARE(int,          luaL_checkoption,    lua_State *L, int narg, const char *def, const char *const lst[])
SYMBOL_DECLARE(int,          luaL_fileresult,     lua_State *L, int stat, const char *fname)
SYMBOL_DECLARE(int,          luaL_execresult,     lua_State *L, int stat)
SYMBOL_DECLARE(int,          luaL_ref,            lua_State *L, int t)
SYMBOL_DECLARE(void,         luaL_unref,          lua_State *L, int t, int ref)
SYMBOL_DECLARE(int,          luaL_loadfilex,      lua_State *L, const char *filename, const char *mode)
SYMBOL_DECLARE(int,          luaL_loadbufferx,    lua_State *L, const char *buff, size_t sz, const char *name, const char *mode)
SYMBOL_DECLARE(int,          luaL_loadstring,     lua_State *L, const char *s)
SYMBOL_DECLARE(lua_State *,  luaL_newstate,       void)
SYMBOL_DECLARE(int,          luaL_len,            lua_State *L, int idx)
SYMBOL_DECLARE(const char *, luaL_gsub,           lua_State *L, const char *s, const char *p, const char *r)
SYMBOL_DECLARE(void,         luaL_setfuncs,       lua_State *L, const luaL_Reg *l, int nup)
SYMBOL_DECLARE(int,          luaL_getsubtable,    lua_State *L, int idx, const char *fname)
SYMBOL_DECLARE(void,         luaL_traceback,      lua_State *L, lua_State *L1, const char *msg, int level)
SYMBOL_DECLARE(void,         luaL_requiref,       lua_State *L, const char *modname, lua_CFunction openf, int glb)
SYMBOL_DECLARE(void,         luaL_buffinit,       lua_State *L, luaL_Buffer *B)
SYMBOL_DECLARE(char *,       luaL_prepbuffsize,   luaL_Buffer *B, size_t sz)
SYMBOL_DECLARE(void,         luaL_addlstring,     luaL_Buffer *B, const char *s, size_t l)
SYMBOL_DECLARE(void,         luaL_addstring,      luaL_Buffer *B, const char *s)
SYMBOL_DECLARE(void,         luaL_addvalue,       luaL_Buffer *B)
SYMBOL_DECLARE(void,         luaL_pushresult,     luaL_Buffer *B)
SYMBOL_DECLARE(void,         luaL_pushresultsize, luaL_Buffer *B, size_t sz)
SYMBOL_DECLARE(char *,       luaL_buffinitsize,   lua_State *L, luaL_Buffer *B, size_t sz)
SYMBOL_DECLARE(void,         luaL_openlibs,       lua_State *L)

#define lauxlib_h
#define LUA_ERRFILE (LUA_ERRERR+1)
#define luaL_checkversion(L) luaL_checkversion_(L, LUA_VERSION_NUM)
#define LUA_NOREF (-2)
#define LUA_REFNIL (-1)
#define luaL_loadfile(L,f) luaL_loadfilex(L,f,NULL)
#define luaL_newlibtable(L,l) lua_createtable(L, 0, sizeof(l)/sizeof((l)[0]) - 1)
#define luaL_newlib(L,l) (luaL_newlibtable(L,l), luaL_setfuncs(L,l,0))
#define luaL_argcheck(L, cond,numarg,extramsg) ((void)((cond) || luaL_argerror(L, (numarg), (extramsg))))
#define luaL_checkstring(L,n) (luaL_checklstring(L, (n), NULL))
#define luaL_optstring(L,n,d) (luaL_optlstring(L, (n), (d), NULL))
#define luaL_checkint(L,n) ((int)luaL_checkinteger(L, (n)))
#define luaL_optint(L,n,d) ((int)luaL_optinteger(L, (n), (d)))
#define luaL_checklong(L,n) ((long)luaL_checkinteger(L, (n)))
#define luaL_optlong(L,n,d) ((long)luaL_optinteger(L, (n), (d)))
#define luaL_typename(L,i) lua_typename(L, lua_type(L,(i)))
#define luaL_dofile(L, fn) (luaL_loadfile(L, fn) || lua_pcall(L, 0, LUA_MULTRET, 0))
#define luaL_dostring(L, s) (luaL_loadstring(L, s) || lua_pcall(L, 0, LUA_MULTRET, 0))
#define luaL_getmetatable(L,n) (lua_getfield(L, LUA_REGISTRYINDEX, (n)))
#define luaL_opt(L,f,n,d) (lua_isnoneornil(L,(n)) ? (d) : f(L,(n)))
#define luaL_loadbuffer(L,s,sz,n) luaL_loadbufferx(L,s,sz,n,NULL)
#define luaL_addchar(B,c) ((void)((B)->n < (B)->size || luaL_prepbuffsize((B), 1)), ((B)->b[(B)->n++] = (c)))
#define luaL_addsize(B,s) ((B)->n += (s))
#define luaL_prepbuffer(B) luaL_prepbuffsize(B, LUAL_BUFFERSIZE)
#define LUA_FILEHANDLE "FILE*"

#ifdef LITE_XL_PLUGIN_ENTRYPOINT

SYMBOL_WRAP_DECL(lua_State *, lua_newstate, lua_Alloc f, void *ud){
  SYMBOL_WRAP_CALL(lua_newstate, f, ud);
}
SYMBOL_WRAP_DECL(void, lua_close, lua_State *L){
  SYMBOL_WRAP_CALL(lua_close, L);
}
SYMBOL_WRAP_DECL(lua_State *, lua_newthread, lua_State *L){
  SYMBOL_WRAP_CALL(lua_newthread, L);
}
SYMBOL_WRAP_DECL(lua_CFunction, lua_atpanic, lua_State *L, lua_CFunction panicf){
  SYMBOL_WRAP_CALL(lua_atpanic, L, panicf);
}
SYMBOL_WRAP_DECL(const lua_Number *, lua_version, lua_State *L){
  SYMBOL_WRAP_CALL(lua_version, L);
}
SYMBOL_WRAP_DECL(int, lua_absindex, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_absindex, L, idx);
}
SYMBOL_WRAP_DECL(int, lua_gettop, lua_State *L){
  SYMBOL_WRAP_CALL(lua_gettop, L);
}
SYMBOL_WRAP_DECL(void, lua_settop, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_settop, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_pushvalue, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_pushvalue, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_copy, lua_State *L, int fromidx, int toidx){
  SYMBOL_WRAP_CALL(lua_copy, L, fromidx, toidx);
}
SYMBOL_WRAP_DECL(int, lua_checkstack, lua_State *L, int sz){
  SYMBOL_WRAP_CALL(lua_checkstack, L, sz);
}
SYMBOL_WRAP_DECL(void, lua_xmove, lua_State *from, lua_State *to, int n){
  SYMBOL_WRAP_CALL(lua_xmove, from, to, n);
}
SYMBOL_WRAP_DECL(int, lua_isnumber, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_isnumber, L, idx);
}
SYMBOL_WRAP_DECL(int, lua_isstring, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_isstring, L, idx);
}
SYMBOL_WRAP_DECL(int, lua_iscfunction, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_iscfunction, L, idx);
}
SYMBOL_WRAP_DECL(int, lua_isuserdata, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_isuserdata, L, idx);
}
SYMBOL_WRAP_DECL(int, lua_type, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_type, L, idx);
}
SYMBOL_WRAP_DECL(const char *, lua_typename, lua_State *L, int tp){
  SYMBOL_WRAP_CALL(lua_typename, L, tp);
}
SYMBOL_WRAP_DECL(lua_Number, lua_tonumberx, lua_State *L, int idx, int *isnum){
  SYMBOL_WRAP_CALL(lua_tonumberx, L, idx, isnum);
}
SYMBOL_WRAP_DECL(lua_Integer, lua_tointegerx, lua_State *L, int idx, int *isnum){
  SYMBOL_WRAP_CALL(lua_tointegerx, L, idx, isnum);
}
SYMBOL_WRAP_DECL(lua_Unsigned, lua_tounsignedx, lua_State *L, int idx, int *isnum){
  SYMBOL_WRAP_CALL(lua_tounsignedx, L, idx, isnum);
}
SYMBOL_WRAP_DECL(int, lua_toboolean, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_toboolean, L, idx);
}
SYMBOL_WRAP_DECL(const char *, lua_tolstring, lua_State *L, int idx, size_t *len){
  SYMBOL_WRAP_CALL(lua_tolstring, L, idx, len);
}
SYMBOL_WRAP_DECL(size_t, lua_rawlen, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_rawlen, L, idx);
}
SYMBOL_WRAP_DECL(lua_CFunction, lua_tocfunction, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_tocfunction, L, idx);
}
SYMBOL_WRAP_DECL(void *, lua_touserdata, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_touserdata, L, idx);
}
SYMBOL_WRAP_DECL(lua_State *, lua_tothread, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_tothread, L, idx);
}
SYMBOL_WRAP_DECL(const void *, lua_topointer, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_topointer, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_arith, lua_State *L, int op){
  SYMBOL_WRAP_CALL(lua_arith, L, op);
}
SYMBOL_WRAP_DECL(int, lua_rawequal, lua_State *L, int idx1, int idx2){
  SYMBOL_WRAP_CALL(lua_rawequal, L, idx1, idx2);
}
SYMBOL_WRAP_DECL(int, lua_compare, lua_State *L, int idx1, int idx2, int op){
  SYMBOL_WRAP_CALL(lua_compare, L, idx1, idx2, op);
}
SYMBOL_WRAP_DECL(void, lua_pushnil, lua_State *L){
  SYMBOL_WRAP_CALL(lua_pushnil, L);
}
SYMBOL_WRAP_DECL(void, lua_pushnumber, lua_State *L, lua_Number n){
  SYMBOL_WRAP_CALL(lua_pushnumber, L, n);
}
SYMBOL_WRAP_DECL(void, lua_pushinteger, lua_State *L, lua_Integer n){
  SYMBOL_WRAP_CALL(lua_pushinteger, L, n);
}
SYMBOL_WRAP_DECL(void, lua_pushunsigned, lua_State *L, lua_Unsigned n){
  SYMBOL_WRAP_CALL(lua_pushunsigned, L, n);
}
SYMBOL_WRAP_DECL(const char *, lua_pushlstring, lua_State *L, const char *s, size_t l){
  SYMBOL_WRAP_CALL(lua_pushlstring, L, s, l);
}
SYMBOL_WRAP_DECL(const char *, lua_pushstring, lua_State *L, const char *s){
  SYMBOL_WRAP_CALL(lua_pushstring, L, s);
}
SYMBOL_WRAP_DECL(const char *, lua_pushvfstring, lua_State *L, const char *fmt, va_list argp){
  SYMBOL_WRAP_CALL(lua_pushvfstring, L, fmt, argp);
}
SYMBOL_WRAP_DECL(const char *, lua_pushfstring, lua_State *L, const char *fmt, ...){
  SYMBOL_WRAP_CALL(lua_pushfstring, L, fmt);
}
SYMBOL_WRAP_DECL(void, lua_pushcclosure, lua_State *L, lua_CFunction fn, int n){
  SYMBOL_WRAP_CALL(lua_pushcclosure, L, fn, n);
}
SYMBOL_WRAP_DECL(void, lua_pushboolean, lua_State *L, int b){
  SYMBOL_WRAP_CALL(lua_pushboolean, L, b);
}
SYMBOL_WRAP_DECL(void, lua_pushlightuserdata, lua_State *L, void *p){
  SYMBOL_WRAP_CALL(lua_pushlightuserdata, L, p);
}
SYMBOL_WRAP_DECL(int, lua_pushthread, lua_State *L){
  SYMBOL_WRAP_CALL(lua_pushthread, L);
}
SYMBOL_WRAP_DECL(void, lua_getglobal, lua_State *L, const char *var){
  SYMBOL_WRAP_CALL(lua_getglobal, L, var);
}
SYMBOL_WRAP_DECL(void, lua_gettable, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_gettable, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_getfield, lua_State *L, int idx, const char *k){
  SYMBOL_WRAP_CALL(lua_getfield, L, idx, k);
}
SYMBOL_WRAP_DECL(void, lua_rawget, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_rawget, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_rawgeti, lua_State *L, int idx, int n){
  SYMBOL_WRAP_CALL(lua_rawgeti, L, idx, n);
}
SYMBOL_WRAP_DECL(void, lua_rawgetp, lua_State *L, int idx, const void *p){
  SYMBOL_WRAP_CALL(lua_rawgetp, L, idx, p);
}
SYMBOL_WRAP_DECL(void, lua_createtable, lua_State *L, int narr, int nrec){
  SYMBOL_WRAP_CALL(lua_createtable, L, narr, nrec);
}
SYMBOL_WRAP_DECL(void *, lua_newuserdata, lua_State *L, size_t sz){
  if (__lua_newuserdatauv != NULL) {
    return lua_newuserdatauv(L, sz, 1);
  } else if (__lua_newuserdata != NULL) {
    SYMBOL_WRAP_CALL(lua_newuserdata, L, sz);
  }
  SYMBOL_WRAP_CALL_FB(lua_newuserdata, L, sz);
}
SYMBOL_WRAP_DECL(void *, lua_newuserdatauv, lua_State *L, size_t sz, int nuvalue){
  SYMBOL_WRAP_CALL(lua_newuserdatauv, L, sz, nuvalue);
}
SYMBOL_WRAP_DECL(int, lua_getmetatable, lua_State *L, int objindex){
  SYMBOL_WRAP_CALL(lua_getmetatable, L, objindex);
}
SYMBOL_WRAP_DECL(void, lua_getuservalue, lua_State *L, int idx){
  if (__lua_getiuservalue != NULL) {
    return lua_getiuservalue(L, idx, 1);
  } else if (__lua_getuservalue != NULL) {
    SYMBOL_WRAP_CALL(lua_getuservalue, L, idx);
  }
  SYMBOL_WRAP_CALL_FB(lua_getuservalue, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_getiuservalue, lua_State *L, int idx, int n){
  SYMBOL_WRAP_CALL(lua_getiuservalue, L, idx, n);
}
SYMBOL_WRAP_DECL(void, lua_setglobal, lua_State *L, const char *var){
  SYMBOL_WRAP_CALL(lua_setglobal, L, var);
}
SYMBOL_WRAP_DECL(void, lua_settable, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_settable, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_setfield, lua_State *L, int idx, const char *k){
  SYMBOL_WRAP_CALL(lua_setfield, L, idx, k);
}
SYMBOL_WRAP_DECL(void, lua_rawset, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_rawset, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_rawseti, lua_State *L, int idx, int n){
  SYMBOL_WRAP_CALL(lua_rawseti, L, idx, n);
}
SYMBOL_WRAP_DECL(void, lua_rawsetp, lua_State *L, int idx, const void *p){
  SYMBOL_WRAP_CALL(lua_rawsetp, L, idx, p);
}
SYMBOL_WRAP_DECL(int, lua_setmetatable, lua_State *L, int objindex){
  SYMBOL_WRAP_CALL(lua_setmetatable, L, objindex);
}
SYMBOL_WRAP_DECL(void, lua_setuservalue, lua_State *L, int idx){
  if (__lua_setiuservalue != NULL) {
    return lua_setiuservalue(L, idx, 1);
  } else if (__lua_setuservalue != NULL) {
    SYMBOL_WRAP_CALL(lua_setuservalue, L, idx);
  }
  SYMBOL_WRAP_CALL_FB(lua_setuservalue, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_setiuservalue, lua_State *L, int idx, int n){
  SYMBOL_WRAP_CALL(lua_setiuservalue, L, idx, n);
}
SYMBOL_WRAP_DECL(void, lua_callk, lua_State *L, int nargs, int nresults, lua_KContext ctx, lua_KFunction k){
  SYMBOL_WRAP_CALL(lua_callk, L, nargs, nresults, ctx, k);
}
SYMBOL_WRAP_DECL(int, lua_getctx, lua_State *L, int *ctx){
  SYMBOL_WRAP_CALL(lua_getctx, L, ctx);
}
SYMBOL_WRAP_DECL(int, lua_pcallk, lua_State *L, int nargs, int nresults, int errfunc, lua_KContext ctx, lua_KFunction k){
  SYMBOL_WRAP_CALL(lua_pcallk, L, nargs, nresults, errfunc, ctx, k);
}
SYMBOL_WRAP_DECL(int, lua_load, lua_State *L, lua_Reader reader, void *dt, const char *chunkname, const char *mode){
  SYMBOL_WRAP_CALL(lua_load, L, reader, dt, chunkname, mode);
}
SYMBOL_WRAP_DECL(int, lua_dump, lua_State *L, lua_Writer writer, void *data, int strip){
  SYMBOL_WRAP_CALL(lua_dump, L, writer, data, strip);
}
SYMBOL_WRAP_DECL(int, lua_yieldk, lua_State *L, int nresults, lua_KContext ctx, lua_KFunction k){
  SYMBOL_WRAP_CALL(lua_yieldk, L, nresults, ctx, k);
}
SYMBOL_WRAP_DECL(int, lua_resume, lua_State *L, lua_State *from, int narg){
  SYMBOL_WRAP_CALL(lua_resume, L, from, narg);
}
SYMBOL_WRAP_DECL(int, lua_status, lua_State *L){
  SYMBOL_WRAP_CALL(lua_status, L);
}
SYMBOL_WRAP_DECL(int, lua_gc, lua_State *L, int what, int data){
  SYMBOL_WRAP_CALL(lua_gc, L, what, data);
}
SYMBOL_WRAP_DECL(int, lua_error, lua_State *L){
  SYMBOL_WRAP_CALL(lua_error, L);
}
SYMBOL_WRAP_DECL(int, lua_next, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_next, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_concat, lua_State *L, int n){
  SYMBOL_WRAP_CALL(lua_concat, L, n);
}
SYMBOL_WRAP_DECL(void, lua_len, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(lua_len, L, idx);
}
SYMBOL_WRAP_DECL(lua_Alloc, lua_getallocf, lua_State *L, void **ud){
  SYMBOL_WRAP_CALL(lua_getallocf, L, ud);
}
SYMBOL_WRAP_DECL(void, lua_setallocf, lua_State *L, lua_Alloc f, void *ud){
  SYMBOL_WRAP_CALL(lua_setallocf, L, f, ud);
}
SYMBOL_WRAP_DECL(int, lua_getstack, lua_State *L, int level, lua_Debug *ar){
  SYMBOL_WRAP_CALL(lua_getstack, L, level, ar);
}
SYMBOL_WRAP_DECL(int, lua_getinfo, lua_State *L, const char *what, lua_Debug *ar){
  SYMBOL_WRAP_CALL(lua_getinfo, L, what, ar);
}
SYMBOL_WRAP_DECL(const char *, lua_getlocal, lua_State *L, const lua_Debug *ar, int n){
  SYMBOL_WRAP_CALL(lua_getlocal, L, ar, n);
}
SYMBOL_WRAP_DECL(const char *, lua_setlocal, lua_State *L, const lua_Debug *ar, int n){
  SYMBOL_WRAP_CALL(lua_setlocal, L, ar, n);
}
SYMBOL_WRAP_DECL(const char *, lua_getupvalue, lua_State *L, int funcindex, int n){
  SYMBOL_WRAP_CALL(lua_getupvalue, L, funcindex, n);
}
SYMBOL_WRAP_DECL(const char *, lua_setupvalue, lua_State *L, int funcindex, int n){
  SYMBOL_WRAP_CALL(lua_setupvalue, L, funcindex, n);
}
SYMBOL_WRAP_DECL(void *, lua_upvalueid, lua_State *L, int fidx, int n){
  SYMBOL_WRAP_CALL(lua_upvalueid, L, fidx, n);
}
SYMBOL_WRAP_DECL(void, lua_upvaluejoin, lua_State *L, int fidx1, int n1, int fidx2, int n2){
  SYMBOL_WRAP_CALL(lua_upvaluejoin, L, fidx1, n1, fidx2, n2);
}
SYMBOL_WRAP_DECL(int, lua_sethook, lua_State *L, lua_Hook func, int mask, int count){
  SYMBOL_WRAP_CALL(lua_sethook, L, func, mask, count);
}
SYMBOL_WRAP_DECL(lua_Hook, lua_gethook, lua_State *L){
  SYMBOL_WRAP_CALL(lua_gethook, L);
}
SYMBOL_WRAP_DECL(int, lua_gethookmask, lua_State *L){
  SYMBOL_WRAP_CALL(lua_gethookmask, L);
}
SYMBOL_WRAP_DECL(int, lua_gethookcount, lua_State *L){
  SYMBOL_WRAP_CALL(lua_gethookcount, L);
}
SYMBOL_WRAP_DECL(void, luaL_checkversion_, lua_State *L, lua_Number ver){
  SYMBOL_WRAP_CALL(luaL_checkversion_, L, ver);
}
SYMBOL_WRAP_DECL(int, luaL_getmetafield, lua_State *L, int obj, const char *e){
  SYMBOL_WRAP_CALL(luaL_getmetafield, L, obj, e);
}
SYMBOL_WRAP_DECL(int, luaL_callmeta, lua_State *L, int obj, const char *e){
  SYMBOL_WRAP_CALL(luaL_callmeta, L, obj, e);
}
SYMBOL_WRAP_DECL(const char *, luaL_tolstring, lua_State *L, int idx, size_t *len){
  SYMBOL_WRAP_CALL(luaL_tolstring, L, idx, len);
}
SYMBOL_WRAP_DECL(int, luaL_argerror, lua_State *L, int numarg, const char *extramsg){
  SYMBOL_WRAP_CALL(luaL_argerror, L, numarg, extramsg);
}
SYMBOL_WRAP_DECL(const char *, luaL_checklstring, lua_State *L, int numArg, size_t *l){
  SYMBOL_WRAP_CALL(luaL_checklstring, L, numArg, l);
}
SYMBOL_WRAP_DECL(const char *, luaL_optlstring, lua_State *L, int numArg, const char *def, size_t *l){
  SYMBOL_WRAP_CALL(luaL_optlstring, L, numArg, def, l);
}
SYMBOL_WRAP_DECL(lua_Number, luaL_checknumber, lua_State *L, int numArg){
  SYMBOL_WRAP_CALL(luaL_checknumber, L, numArg);
}
SYMBOL_WRAP_DECL(lua_Number, luaL_optnumber, lua_State *L, int nArg, lua_Number def){
  SYMBOL_WRAP_CALL(luaL_optnumber, L, nArg, def);
}
SYMBOL_WRAP_DECL(lua_Integer, luaL_checkinteger, lua_State *L, int numArg){
  SYMBOL_WRAP_CALL(luaL_checkinteger, L, numArg);
}
SYMBOL_WRAP_DECL(lua_Integer, luaL_optinteger, lua_State *L, int nArg, lua_Integer def){
  SYMBOL_WRAP_CALL(luaL_optinteger, L, nArg, def);
}
SYMBOL_WRAP_DECL(lua_Unsigned, luaL_checkunsigned, lua_State *L, int numArg){
  SYMBOL_WRAP_CALL(luaL_checkunsigned, L, numArg);
}
SYMBOL_WRAP_DECL(lua_Unsigned, luaL_optunsigned, lua_State *L, int numArg, lua_Unsigned def){
  SYMBOL_WRAP_CALL(luaL_optunsigned, L, numArg, def);
}
SYMBOL_WRAP_DECL(void, luaL_checkstack, lua_State *L, int sz, const char *msg){
  SYMBOL_WRAP_CALL(luaL_checkstack, L, sz, msg);
}
SYMBOL_WRAP_DECL(void, luaL_checktype, lua_State *L, int narg, int t){
  SYMBOL_WRAP_CALL(luaL_checktype, L, narg, t);
}
SYMBOL_WRAP_DECL(void, luaL_checkany, lua_State *L, int narg){
  SYMBOL_WRAP_CALL(luaL_checkany, L, narg);
}
SYMBOL_WRAP_DECL(int, luaL_newmetatable, lua_State *L, const char *tname){
  SYMBOL_WRAP_CALL(luaL_newmetatable, L, tname);
}
SYMBOL_WRAP_DECL(void, luaL_setmetatable, lua_State *L, const char *tname){
  SYMBOL_WRAP_CALL(luaL_setmetatable, L, tname);
}
SYMBOL_WRAP_DECL(void *, luaL_testudata, lua_State *L, int ud, const char *tname){
  SYMBOL_WRAP_CALL(luaL_testudata, L, ud, tname);
}
SYMBOL_WRAP_DECL(void *, luaL_checkudata, lua_State *L, int ud, const char *tname){
  SYMBOL_WRAP_CALL(luaL_checkudata, L, ud, tname);
}
SYMBOL_WRAP_DECL(void, luaL_where, lua_State *L, int lvl){
  SYMBOL_WRAP_CALL(luaL_where, L, lvl);
}
SYMBOL_WRAP_DECL(int, luaL_error, lua_State *L, const char *fmt, ...){
  va_list argp;
  va_start(argp, fmt);
  luaL_where(L, 1);
  lua_pushvfstring(L, fmt, argp);
  va_end(argp);
  lua_concat(L, 2);
  return lua_error(L);
}
SYMBOL_WRAP_DECL(int, luaL_checkoption, lua_State *L, int narg, const char *def, const char *const lst[]){
  SYMBOL_WRAP_CALL(luaL_checkoption, L, narg, def, lst);
}
SYMBOL_WRAP_DECL(int, luaL_fileresult, lua_State *L, int stat, const char *fname){
  SYMBOL_WRAP_CALL(luaL_fileresult, L, stat, fname);
}
SYMBOL_WRAP_DECL(int, luaL_execresult, lua_State *L, int stat){
  SYMBOL_WRAP_CALL(luaL_execresult, L, stat);
}
SYMBOL_WRAP_DECL(int, luaL_ref, lua_State *L, int t){
  SYMBOL_WRAP_CALL(luaL_ref, L, t);
}
SYMBOL_WRAP_DECL(void, luaL_unref, lua_State *L, int t, int ref){
  SYMBOL_WRAP_CALL(luaL_unref, L, t, ref);
}
SYMBOL_WRAP_DECL(int, luaL_loadfilex, lua_State *L, const char *filename, const char *mode){
  SYMBOL_WRAP_CALL(luaL_loadfilex, L, filename, mode);
}
SYMBOL_WRAP_DECL(int, luaL_loadbufferx, lua_State *L, const char *buff, size_t sz, const char *name, const char *mode){
  SYMBOL_WRAP_CALL(luaL_loadbufferx, L, buff, sz, name, mode);
}
SYMBOL_WRAP_DECL(int, luaL_loadstring, lua_State *L, const char *s){
  SYMBOL_WRAP_CALL(luaL_loadstring, L, s);
}
SYMBOL_WRAP_DECL(lua_State *, luaL_newstate, void){
 return __luaL_newstate();
}
SYMBOL_WRAP_DECL(int, luaL_len, lua_State *L, int idx){
  SYMBOL_WRAP_CALL(luaL_len, L, idx);
}
SYMBOL_WRAP_DECL(const char *, luaL_gsub, lua_State *L, const char *s, const char *p, const char *r){
  SYMBOL_WRAP_CALL(luaL_gsub, L, s, p, r);
}
SYMBOL_WRAP_DECL(void, luaL_setfuncs, lua_State *L, const luaL_Reg *l, int nup){
  SYMBOL_WRAP_CALL(luaL_setfuncs, L, l, nup);
}
SYMBOL_WRAP_DECL(int, luaL_getsubtable, lua_State *L, int idx, const char *fname){
  SYMBOL_WRAP_CALL(luaL_getsubtable, L, idx, fname);
}
SYMBOL_WRAP_DECL(void, luaL_traceback, lua_State *L, lua_State *L1, const char *msg, int level){
  SYMBOL_WRAP_CALL(luaL_traceback, L, L1, msg, level);
}
SYMBOL_WRAP_DECL(void, luaL_requiref, lua_State *L, const char *modname, lua_CFunction openf, int glb){
  SYMBOL_WRAP_CALL(luaL_requiref, L, modname, openf, glb);
}
SYMBOL_WRAP_DECL(void, luaL_buffinit, lua_State *L, luaL_Buffer *B){
  SYMBOL_WRAP_CALL(luaL_buffinit, L, B);
}
SYMBOL_WRAP_DECL(char *, luaL_prepbuffsize, luaL_Buffer *B, size_t sz){
  SYMBOL_WRAP_CALL(luaL_prepbuffsize, B, sz);
}
SYMBOL_WRAP_DECL(void, luaL_addlstring, luaL_Buffer *B, const char *s, size_t l){
  SYMBOL_WRAP_CALL(luaL_addlstring, B, s, l);
}
SYMBOL_WRAP_DECL(void, luaL_addstring, luaL_Buffer *B, const char *s){
  SYMBOL_WRAP_CALL(luaL_addstring, B, s);
}
SYMBOL_WRAP_DECL(void, luaL_addvalue, luaL_Buffer *B){
  SYMBOL_WRAP_CALL(luaL_addvalue, B);
}
SYMBOL_WRAP_DECL(void, luaL_pushresult, luaL_Buffer *B){
  SYMBOL_WRAP_CALL(luaL_pushresult, B);
}
SYMBOL_WRAP_DECL(void, luaL_pushresultsize, luaL_Buffer *B, size_t sz){
  SYMBOL_WRAP_CALL(luaL_pushresultsize, B, sz);
}
SYMBOL_WRAP_DECL(char *, luaL_buffinitsize, lua_State *L, luaL_Buffer *B, size_t sz){
  SYMBOL_WRAP_CALL(luaL_buffinitsize, L, B, sz);
}
SYMBOL_WRAP_DECL(void, luaL_openlibs, lua_State *L){
  SYMBOL_WRAP_CALL(luaL_openlibs, L);
}

#define IMPORT_SYMBOL(name, ret, ...) \
  __##name = (\
    __##name = (ret (*) (__VA_ARGS__)) symbol(#name), \
    __##name == NULL ? &__lite_xl_fallback_##name : __##name\
  )

#define IMPORT_SYMBOL_OPT(name, ret, ...) \
  __##name = symbol(#name)

static void lite_xl_plugin_init(void *XL) {
  void* (*symbol)(const char *) = (void* (*) (const char *)) XL;
  IMPORT_SYMBOL(lua_newstate, lua_State *, lua_Alloc f, void *ud);
  IMPORT_SYMBOL(lua_close, void , lua_State *L);
  IMPORT_SYMBOL(lua_newthread, lua_State *, lua_State *L);
  IMPORT_SYMBOL(lua_atpanic, lua_CFunction , lua_State *L, lua_CFunction panicf);
  IMPORT_SYMBOL(lua_version, const lua_Number *, lua_State *L);
  IMPORT_SYMBOL(lua_absindex, int , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_gettop, int , lua_State *L);
  IMPORT_SYMBOL(lua_settop, void , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_pushvalue, void , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_copy, void , lua_State *L, int fromidx, int toidx);
  IMPORT_SYMBOL(lua_checkstack, int , lua_State *L, int sz);
  IMPORT_SYMBOL(lua_xmove, void , lua_State *from, lua_State *to, int n);
  IMPORT_SYMBOL(lua_isnumber, int , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_isstring, int , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_iscfunction, int , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_isuserdata, int , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_type, int , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_typename, const char *, lua_State *L, int tp);
  IMPORT_SYMBOL(lua_tonumberx, lua_Number , lua_State *L, int idx, int *isnum);
  IMPORT_SYMBOL(lua_tointegerx, lua_Integer , lua_State *L, int idx, int *isnum);
  IMPORT_SYMBOL(lua_tounsignedx, lua_Unsigned , lua_State *L, int idx, int *isnum);
  IMPORT_SYMBOL(lua_toboolean, int , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_tolstring, const char *, lua_State *L, int idx, size_t *len);
  IMPORT_SYMBOL(lua_rawlen, size_t , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_tocfunction, lua_CFunction , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_touserdata, void *, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_tothread, lua_State *, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_topointer, const void *, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_arith, void , lua_State *L, int op);
  IMPORT_SYMBOL(lua_rawequal, int , lua_State *L, int idx1, int idx2);
  IMPORT_SYMBOL(lua_compare, int , lua_State *L, int idx1, int idx2, int op);
  IMPORT_SYMBOL(lua_pushnil, void , lua_State *L);
  IMPORT_SYMBOL(lua_pushnumber, void , lua_State *L, lua_Number n);
  IMPORT_SYMBOL(lua_pushinteger, void , lua_State *L, lua_Integer n);
  IMPORT_SYMBOL(lua_pushunsigned, void , lua_State *L, lua_Unsigned n);
  IMPORT_SYMBOL(lua_pushlstring, const char *, lua_State *L, const char *s, size_t l);
  IMPORT_SYMBOL(lua_pushstring, const char *, lua_State *L, const char *s);
  IMPORT_SYMBOL(lua_pushvfstring, const char *, lua_State *L, const char *fmt, va_list argp);
  IMPORT_SYMBOL(lua_pushfstring, const char *, lua_State *L, const char *fmt, ...);
  IMPORT_SYMBOL(lua_pushcclosure, void , lua_State *L, lua_CFunction fn, int n);
  IMPORT_SYMBOL(lua_pushboolean, void , lua_State *L, int b);
  IMPORT_SYMBOL(lua_pushlightuserdata, void , lua_State *L, void *p);
  IMPORT_SYMBOL(lua_pushthread, int , lua_State *L);
  IMPORT_SYMBOL(lua_getglobal, void , lua_State *L, const char *var);
  IMPORT_SYMBOL(lua_gettable, void , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_getfield, void , lua_State *L, int idx, const char *k);
  IMPORT_SYMBOL(lua_rawget, void , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_rawgeti, void , lua_State *L, int idx, int n);
  IMPORT_SYMBOL(lua_rawgetp, void , lua_State *L, int idx, const void *p);
  IMPORT_SYMBOL(lua_createtable, void , lua_State *L, int narr, int nrec);
  IMPORT_SYMBOL_OPT(lua_newuserdata, void *, lua_State *L, size_t sz);
  IMPORT_SYMBOL(lua_newuserdatauv, void *, lua_State *L, size_t sz, int nuvalue);
  IMPORT_SYMBOL(lua_getmetatable, int , lua_State *L, int objindex);
  IMPORT_SYMBOL_OPT(lua_getuservalue, void , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_getiuservalue, void , lua_State *L, int idx, int n);
  IMPORT_SYMBOL(lua_setglobal, void , lua_State *L, const char *var);
  IMPORT_SYMBOL(lua_settable, void , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_setfield, void , lua_State *L, int idx, const char *k);
  IMPORT_SYMBOL(lua_rawset, void , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_rawseti, void , lua_State *L, int idx, int n);
  IMPORT_SYMBOL(lua_rawsetp, void , lua_State *L, int idx, const void *p);
  IMPORT_SYMBOL(lua_setmetatable, int , lua_State *L, int objindex);
  IMPORT_SYMBOL_OPT(lua_setuservalue, void , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_setiuservalue, void , lua_State *L, int idx, int n);
  IMPORT_SYMBOL(lua_callk, void , lua_State *L, int nargs, int nresults, lua_KContext ctx, lua_KFunction k);
  IMPORT_SYMBOL(lua_getctx, int , lua_State *L, int *ctx);
  IMPORT_SYMBOL(lua_pcallk, int , lua_State *L, int nargs, int nresults, int errfunc, lua_KContext ctx, lua_KFunction k);
  IMPORT_SYMBOL(lua_load, int , lua_State *L, lua_Reader reader, void *dt, const char *chunkname, const char *mode);
  IMPORT_SYMBOL(lua_dump, int , lua_State *L, lua_Writer writer, void *data, int strip);
  IMPORT_SYMBOL(lua_yieldk, int , lua_State *L, int nresults, lua_KContext ctx, lua_KFunction k);
  IMPORT_SYMBOL(lua_resume, int , lua_State *L, lua_State *from, int narg);
  IMPORT_SYMBOL(lua_status, int , lua_State *L);
  IMPORT_SYMBOL(lua_gc, int , lua_State *L, int what, int data);
  IMPORT_SYMBOL(lua_error, int , lua_State *L);
  IMPORT_SYMBOL(lua_next, int , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_concat, void , lua_State *L, int n);
  IMPORT_SYMBOL(lua_len, void , lua_State *L, int idx);
  IMPORT_SYMBOL(lua_getallocf, lua_Alloc , lua_State *L, void **ud);
  IMPORT_SYMBOL(lua_setallocf, void , lua_State *L, lua_Alloc f, void *ud);
  IMPORT_SYMBOL(lua_getstack, int , lua_State *L, int level, lua_Debug *ar);
  IMPORT_SYMBOL(lua_getinfo, int , lua_State *L, const char *what, lua_Debug *ar);
  IMPORT_SYMBOL(lua_getlocal, const char *, lua_State *L, const lua_Debug *ar, int n);
  IMPORT_SYMBOL(lua_setlocal, const char *, lua_State *L, const lua_Debug *ar, int n);
  IMPORT_SYMBOL(lua_getupvalue, const char *, lua_State *L, int funcindex, int n);
  IMPORT_SYMBOL(lua_setupvalue, const char *, lua_State *L, int funcindex, int n);
  IMPORT_SYMBOL(lua_upvalueid, void *, lua_State *L, int fidx, int n);
  IMPORT_SYMBOL(lua_upvaluejoin, void , lua_State *L, int fidx1, int n1, int fidx2, int n2);
  IMPORT_SYMBOL(lua_sethook, int , lua_State *L, lua_Hook func, int mask, int count);
  IMPORT_SYMBOL(lua_gethook, lua_Hook , lua_State *L);
  IMPORT_SYMBOL(lua_gethookmask, int , lua_State *L);
  IMPORT_SYMBOL(lua_gethookcount, int , lua_State *L);
  IMPORT_SYMBOL(luaL_checkversion_, void , lua_State *L, lua_Number ver);
  IMPORT_SYMBOL(luaL_getmetafield, int , lua_State *L, int obj, const char *e);
  IMPORT_SYMBOL(luaL_callmeta, int , lua_State *L, int obj, const char *e);
  IMPORT_SYMBOL(luaL_tolstring, const char *, lua_State *L, int idx, size_t *len);
  IMPORT_SYMBOL(luaL_argerror, int , lua_State *L, int numarg, const char *extramsg);
  IMPORT_SYMBOL(luaL_checklstring, const char *, lua_State *L, int numArg, size_t *l);
  IMPORT_SYMBOL(luaL_optlstring, const char *, lua_State *L, int numArg, const char *def, size_t *l);
  IMPORT_SYMBOL(luaL_checknumber, lua_Number , lua_State *L, int numArg);
  IMPORT_SYMBOL(luaL_optnumber, lua_Number , lua_State *L, int nArg, lua_Number def);
  IMPORT_SYMBOL(luaL_checkinteger, lua_Integer , lua_State *L, int numArg);
  IMPORT_SYMBOL(luaL_optinteger, lua_Integer , lua_State *L, int nArg, lua_Integer def);
  IMPORT_SYMBOL(luaL_checkunsigned, lua_Unsigned , lua_State *L, int numArg);
  IMPORT_SYMBOL(luaL_optunsigned, lua_Unsigned , lua_State *L, int numArg, lua_Unsigned def);
  IMPORT_SYMBOL(luaL_checkstack, void , lua_State *L, int sz, const char *msg);
  IMPORT_SYMBOL(luaL_checktype, void , lua_State *L, int narg, int t);
  IMPORT_SYMBOL(luaL_checkany, void , lua_State *L, int narg);
  IMPORT_SYMBOL(luaL_newmetatable, int , lua_State *L, const char *tname);
  IMPORT_SYMBOL(luaL_setmetatable, void , lua_State *L, const char *tname);
  IMPORT_SYMBOL(luaL_testudata, void *, lua_State *L, int ud, const char *tname);
  IMPORT_SYMBOL(luaL_checkudata, void *, lua_State *L, int ud, const char *tname);
  IMPORT_SYMBOL(luaL_where, void , lua_State *L, int lvl);
  IMPORT_SYMBOL(luaL_error, int , lua_State *L, const char *fmt, ...);
  IMPORT_SYMBOL(luaL_checkoption, int , lua_State *L, int narg, const char *def, const char *const lst[]);
  IMPORT_SYMBOL(luaL_fileresult, int , lua_State *L, int stat, const char *fname);
  IMPORT_SYMBOL(luaL_execresult, int , lua_State *L, int stat);
  IMPORT_SYMBOL(luaL_ref, int , lua_State *L, int t);
  IMPORT_SYMBOL(luaL_unref, void , lua_State *L, int t, int ref);
  IMPORT_SYMBOL(luaL_loadfilex, int , lua_State *L, const char *filename, const char *mode);
  IMPORT_SYMBOL(luaL_loadbufferx, int , lua_State *L, const char *buff, size_t sz, const char *name, const char *mode);
  IMPORT_SYMBOL(luaL_loadstring, int , lua_State *L, const char *s);
  IMPORT_SYMBOL(luaL_newstate, lua_State *, void);
  IMPORT_SYMBOL(luaL_len, int , lua_State *L, int idx);
  IMPORT_SYMBOL(luaL_gsub, const char *, lua_State *L, const char *s, const char *p, const char *r);
  IMPORT_SYMBOL(luaL_setfuncs, void , lua_State *L, const luaL_Reg *l, int nup);
  IMPORT_SYMBOL(luaL_getsubtable, int , lua_State *L, int idx, const char *fname);
  IMPORT_SYMBOL(luaL_traceback, void , lua_State *L, lua_State *L1, const char *msg, int level);
  IMPORT_SYMBOL(luaL_requiref, void , lua_State *L, const char *modname, lua_CFunction openf, int glb);
  IMPORT_SYMBOL(luaL_buffinit, void , lua_State *L, luaL_Buffer *B);
  IMPORT_SYMBOL(luaL_prepbuffsize, char *, luaL_Buffer *B, size_t sz);
  IMPORT_SYMBOL(luaL_addlstring, void , luaL_Buffer *B, const char *s, size_t l);
  IMPORT_SYMBOL(luaL_addstring, void , luaL_Buffer *B, const char *s);
  IMPORT_SYMBOL(luaL_addvalue, void , luaL_Buffer *B);
  IMPORT_SYMBOL(luaL_pushresult, void , luaL_Buffer *B);
  IMPORT_SYMBOL(luaL_pushresultsize, void , luaL_Buffer *B, size_t sz);
  IMPORT_SYMBOL(luaL_buffinitsize, char *, lua_State *L, luaL_Buffer *B, size_t sz);
  IMPORT_SYMBOL(luaL_openlibs, void, lua_State* L);
}

#endif /* LITE_XL_PLUGIN_ENTRYPOINT */

#endif /* LITE_XL_PLUGIN_API */
