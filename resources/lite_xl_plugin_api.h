#ifndef LITE_XL_PLUGIN_API
#define LITE_XL_PLUGIN_API
/**
The lite_xl plugin API is quite simple. Any shared library can be a plugin file, so long
as it has an entrypoint that looks like the following, where xxxxx is the plugin name:
#include "lite_xl_plugin_api.h"
int lua_open_lite_xl_xxxxx(lua_State* L, void* XL) {
  lite_xl_plugin_init(XL);
  ...
  return 1;
}
In linux, to compile this file, you'd do: 'gcc -o xxxxx.so -shared xxxxx.c'. Simple!
Due to the way the API is structured, you *should not* link or include lua libraries.
This file was automatically generated. DO NOT MODIFY DIRECTLY.
**/


#include <stdarg.h>
#include <stdio.h> // for BUFSIZ? this is kinda weird

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
typedef LUA_NUMBER lua_Number;
typedef LUA_INTEGER lua_Integer;
typedef LUA_UNSIGNED lua_Unsigned;
typedef struct lua_Debug lua_Debug;
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
static	lua_State *(*lua_newstate)	(lua_Alloc f, void *ud);
static	void (*lua_close)	(lua_State *L);
static	lua_State *(*lua_newthread)	(lua_State *L);
static	lua_CFunction (*lua_atpanic)	(lua_State *L, lua_CFunction panicf);
static	const lua_Number *(*lua_version)	(lua_State *L);
static	int (*lua_absindex)	(lua_State *L, int idx);
static	int (*lua_gettop)	(lua_State *L);
static	void (*lua_settop)	(lua_State *L, int idx);
static	void (*lua_pushvalue)	(lua_State *L, int idx);
static	void (*lua_remove)	(lua_State *L, int idx);
static	void (*lua_insert)	(lua_State *L, int idx);
static	void (*lua_replace)	(lua_State *L, int idx);
static	void (*lua_copy)	(lua_State *L, int fromidx, int toidx);
static	int (*lua_checkstack)	(lua_State *L, int sz);
static	void (*lua_xmove)	(lua_State *from, lua_State *to, int n);
static	int (*lua_isnumber)	(lua_State *L, int idx);
static	int (*lua_isstring)	(lua_State *L, int idx);
static	int (*lua_iscfunction)	(lua_State *L, int idx);
static	int (*lua_isuserdata)	(lua_State *L, int idx);
static	int (*lua_type)	(lua_State *L, int idx);
static	const char *(*lua_typename)	(lua_State *L, int tp);
static	lua_Number (*lua_tonumberx)	(lua_State *L, int idx, int *isnum);
static	lua_Integer (*lua_tointegerx)	(lua_State *L, int idx, int *isnum);
static	lua_Unsigned (*lua_tounsignedx)	(lua_State *L, int idx, int *isnum);
static	int (*lua_toboolean)	(lua_State *L, int idx);
static	const char *(*lua_tolstring)	(lua_State *L, int idx, size_t *len);
static	size_t (*lua_rawlen)	(lua_State *L, int idx);
static	lua_CFunction (*lua_tocfunction)	(lua_State *L, int idx);
static	void *(*lua_touserdata)	(lua_State *L, int idx);
static	lua_State *(*lua_tothread)	(lua_State *L, int idx);
static	const void *(*lua_topointer)	(lua_State *L, int idx);
static	void (*lua_arith)	(lua_State *L, int op);
static	int (*lua_rawequal)	(lua_State *L, int idx1, int idx2);
static	int (*lua_compare)	(lua_State *L, int idx1, int idx2, int op);
static	void (*lua_pushnil)	(lua_State *L);
static	void (*lua_pushnumber)	(lua_State *L, lua_Number n);
static	void (*lua_pushinteger)	(lua_State *L, lua_Integer n);
static	void (*lua_pushunsigned)	(lua_State *L, lua_Unsigned n);
static	const char *(*lua_pushlstring)	(lua_State *L, const char *s, size_t l);
static	const char *(*lua_pushstring)	(lua_State *L, const char *s);
static	const char *(*lua_pushvfstring)	(lua_State *L, const char *fmt, va_list argp);
static	const char *(*lua_pushfstring)	(lua_State *L, const char *fmt, ...);
static	void (*lua_pushcclosure)	(lua_State *L, lua_CFunction fn, int n);
static	void (*lua_pushboolean)	(lua_State *L, int b);
static	void (*lua_pushlightuserdata)	(lua_State *L, void *p);
static	int (*lua_pushthread)	(lua_State *L);
static	void (*lua_getglobal)	(lua_State *L, const char *var);
static	void (*lua_gettable)	(lua_State *L, int idx);
static	void (*lua_getfield)	(lua_State *L, int idx, const char *k);
static	void (*lua_rawget)	(lua_State *L, int idx);
static	void (*lua_rawgeti)	(lua_State *L, int idx, int n);
static	void (*lua_rawgetp)	(lua_State *L, int idx, const void *p);
static	void (*lua_createtable)	(lua_State *L, int narr, int nrec);
static	void *(*lua_newuserdata)	(lua_State *L, size_t sz);
static	int (*lua_getmetatable)	(lua_State *L, int objindex);
static	void (*lua_getuservalue)	(lua_State *L, int idx);
static	void (*lua_setglobal)	(lua_State *L, const char *var);
static	void (*lua_settable)	(lua_State *L, int idx);
static	void (*lua_setfield)	(lua_State *L, int idx, const char *k);
static	void (*lua_rawset)	(lua_State *L, int idx);
static	void (*lua_rawseti)	(lua_State *L, int idx, int n);
static	void (*lua_rawsetp)	(lua_State *L, int idx, const void *p);
static	int (*lua_setmetatable)	(lua_State *L, int objindex);
static	void (*lua_setuservalue)	(lua_State *L, int idx);
static	void (*lua_callk)	(lua_State *L, int nargs, int nresults, int ctx, lua_CFunction k);
static	int (*lua_getctx)	(lua_State *L, int *ctx);
static	int (*lua_pcallk)	(lua_State *L, int nargs, int nresults, int errfunc, int ctx, lua_CFunction k);
static	int (*lua_load)	(lua_State *L, lua_Reader reader, void *dt, const char *chunkname, const char *mode);
static	int (*lua_dump)	(lua_State *L, lua_Writer writer, void *data);
static	int (*lua_yieldk)	(lua_State *L, int nresults, int ctx, lua_CFunction k);
static	int (*lua_resume)	(lua_State *L, lua_State *from, int narg);
static	int (*lua_status)	(lua_State *L);
static	int (*lua_gc)	(lua_State *L, int what, int data);
static	int (*lua_error)	(lua_State *L);
static	int (*lua_next)	(lua_State *L, int idx);
static	void (*lua_concat)	(lua_State *L, int n);
static	void (*lua_len)	(lua_State *L, int idx);
static	lua_Alloc (*lua_getallocf)	(lua_State *L, void **ud);
static	void (*lua_setallocf)	(lua_State *L, lua_Alloc f, void *ud);
static	int (*lua_getstack)	(lua_State *L, int level, lua_Debug *ar);
static	int (*lua_getinfo)	(lua_State *L, const char *what, lua_Debug *ar);
static	const char *(*lua_getlocal)	(lua_State *L, const lua_Debug *ar, int n);
static	const char *(*lua_setlocal)	(lua_State *L, const lua_Debug *ar, int n);
static	const char *(*lua_getupvalue)	(lua_State *L, int funcindex, int n);
static	const char *(*lua_setupvalue)	(lua_State *L, int funcindex, int n);
static	void *(*lua_upvalueid)	(lua_State *L, int fidx, int n);
static	void (*lua_upvaluejoin)	(lua_State *L, int fidx1, int n1, int fidx2, int n2);
static	int (*lua_sethook)	(lua_State *L, lua_Hook func, int mask, int count);
static	lua_Hook (*lua_gethook)	(lua_State *L);
static	int (*lua_gethookmask)	(lua_State *L);
static	int (*lua_gethookcount)	(lua_State *L);
#define lua_h
#define LUA_VERSION_MAJOR "5"
#define LUA_VERSION_MINOR "2"
#define LUA_VERSION_NUM 502
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
#define LUA_HOOKCALL 0
#define LUA_HOOKRET 1
#define LUA_HOOKLINE 2
#define LUA_HOOKCOUNT 3
#define LUA_HOOKTAILCALL 4
#define LUA_MASKCALL (1 << LUA_HOOKCALL)
#define LUA_MASKRET (1 << LUA_HOOKRET)
#define LUA_MASKLINE (1 << LUA_HOOKLINE)
#define LUA_MASKCOUNT (1 << LUA_HOOKCOUNT)
static	lua_State *	__lite_xl_fallback_lua_newstate	(lua_Alloc f, void *ud) { fputs("warning: lua_newstate is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_close	(lua_State *L) { fputs("warning: lua_close is a stub", stderr); }
static	lua_State *	__lite_xl_fallback_lua_newthread	(lua_State *L) { fputs("warning: lua_newthread is a stub", stderr); }
static	lua_CFunction 	__lite_xl_fallback_lua_atpanic	(lua_State *L, lua_CFunction panicf) { fputs("warning: lua_atpanic is a stub", stderr); }
static	const lua_Number *	__lite_xl_fallback_lua_version	(lua_State *L) { fputs("warning: lua_version is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_absindex	(lua_State *L, int idx) { fputs("warning: lua_absindex is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_gettop	(lua_State *L) { fputs("warning: lua_gettop is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_settop	(lua_State *L, int idx) { fputs("warning: lua_settop is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_pushvalue	(lua_State *L, int idx) { fputs("warning: lua_pushvalue is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_remove	(lua_State *L, int idx) { fputs("warning: lua_remove is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_insert	(lua_State *L, int idx) { fputs("warning: lua_insert is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_replace	(lua_State *L, int idx) { fputs("warning: lua_replace is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_copy	(lua_State *L, int fromidx, int toidx) { fputs("warning: lua_copy is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_checkstack	(lua_State *L, int sz) { fputs("warning: lua_checkstack is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_xmove	(lua_State *from, lua_State *to, int n) { fputs("warning: lua_xmove is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_isnumber	(lua_State *L, int idx) { fputs("warning: lua_isnumber is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_isstring	(lua_State *L, int idx) { fputs("warning: lua_isstring is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_iscfunction	(lua_State *L, int idx) { fputs("warning: lua_iscfunction is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_isuserdata	(lua_State *L, int idx) { fputs("warning: lua_isuserdata is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_type	(lua_State *L, int idx) { fputs("warning: lua_type is a stub", stderr); }
static	const char *	__lite_xl_fallback_lua_typename	(lua_State *L, int tp) { fputs("warning: lua_typename is a stub", stderr); }
static	lua_Number 	__lite_xl_fallback_lua_tonumberx	(lua_State *L, int idx, int *isnum) { fputs("warning: lua_tonumberx is a stub", stderr); }
static	lua_Integer 	__lite_xl_fallback_lua_tointegerx	(lua_State *L, int idx, int *isnum) { fputs("warning: lua_tointegerx is a stub", stderr); }
static	lua_Unsigned 	__lite_xl_fallback_lua_tounsignedx	(lua_State *L, int idx, int *isnum) { fputs("warning: lua_tounsignedx is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_toboolean	(lua_State *L, int idx) { fputs("warning: lua_toboolean is a stub", stderr); }
static	const char *	__lite_xl_fallback_lua_tolstring	(lua_State *L, int idx, size_t *len) { fputs("warning: lua_tolstring is a stub", stderr); }
static	size_t 	__lite_xl_fallback_lua_rawlen	(lua_State *L, int idx) { fputs("warning: lua_rawlen is a stub", stderr); }
static	lua_CFunction 	__lite_xl_fallback_lua_tocfunction	(lua_State *L, int idx) { fputs("warning: lua_tocfunction is a stub", stderr); }
static	void *	__lite_xl_fallback_lua_touserdata	(lua_State *L, int idx) { fputs("warning: lua_touserdata is a stub", stderr); }
static	lua_State *	__lite_xl_fallback_lua_tothread	(lua_State *L, int idx) { fputs("warning: lua_tothread is a stub", stderr); }
static	const void *	__lite_xl_fallback_lua_topointer	(lua_State *L, int idx) { fputs("warning: lua_topointer is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_arith	(lua_State *L, int op) { fputs("warning: lua_arith is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_rawequal	(lua_State *L, int idx1, int idx2) { fputs("warning: lua_rawequal is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_compare	(lua_State *L, int idx1, int idx2, int op) { fputs("warning: lua_compare is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_pushnil	(lua_State *L) { fputs("warning: lua_pushnil is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_pushnumber	(lua_State *L, lua_Number n) { fputs("warning: lua_pushnumber is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_pushinteger	(lua_State *L, lua_Integer n) { fputs("warning: lua_pushinteger is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_pushunsigned	(lua_State *L, lua_Unsigned n) { fputs("warning: lua_pushunsigned is a stub", stderr); }
static	const char *	__lite_xl_fallback_lua_pushlstring	(lua_State *L, const char *s, size_t l) { fputs("warning: lua_pushlstring is a stub", stderr); }
static	const char *	__lite_xl_fallback_lua_pushstring	(lua_State *L, const char *s) { fputs("warning: lua_pushstring is a stub", stderr); }
static	const char *	__lite_xl_fallback_lua_pushvfstring	(lua_State *L, const char *fmt, va_list argp) { fputs("warning: lua_pushvfstring is a stub", stderr); }
static	const char *	__lite_xl_fallback_lua_pushfstring	(lua_State *L, const char *fmt, ...) { fputs("warning: lua_pushfstring is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_pushcclosure	(lua_State *L, lua_CFunction fn, int n) { fputs("warning: lua_pushcclosure is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_pushboolean	(lua_State *L, int b) { fputs("warning: lua_pushboolean is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_pushlightuserdata	(lua_State *L, void *p) { fputs("warning: lua_pushlightuserdata is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_pushthread	(lua_State *L) { fputs("warning: lua_pushthread is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_getglobal	(lua_State *L, const char *var) { fputs("warning: lua_getglobal is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_gettable	(lua_State *L, int idx) { fputs("warning: lua_gettable is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_getfield	(lua_State *L, int idx, const char *k) { fputs("warning: lua_getfield is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_rawget	(lua_State *L, int idx) { fputs("warning: lua_rawget is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_rawgeti	(lua_State *L, int idx, int n) { fputs("warning: lua_rawgeti is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_rawgetp	(lua_State *L, int idx, const void *p) { fputs("warning: lua_rawgetp is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_createtable	(lua_State *L, int narr, int nrec) { fputs("warning: lua_createtable is a stub", stderr); }
static	void *	__lite_xl_fallback_lua_newuserdata	(lua_State *L, size_t sz) { fputs("warning: lua_newuserdata is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_getmetatable	(lua_State *L, int objindex) { fputs("warning: lua_getmetatable is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_getuservalue	(lua_State *L, int idx) { fputs("warning: lua_getuservalue is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_setglobal	(lua_State *L, const char *var) { fputs("warning: lua_setglobal is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_settable	(lua_State *L, int idx) { fputs("warning: lua_settable is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_setfield	(lua_State *L, int idx, const char *k) { fputs("warning: lua_setfield is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_rawset	(lua_State *L, int idx) { fputs("warning: lua_rawset is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_rawseti	(lua_State *L, int idx, int n) { fputs("warning: lua_rawseti is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_rawsetp	(lua_State *L, int idx, const void *p) { fputs("warning: lua_rawsetp is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_setmetatable	(lua_State *L, int objindex) { fputs("warning: lua_setmetatable is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_setuservalue	(lua_State *L, int idx) { fputs("warning: lua_setuservalue is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_callk	(lua_State *L, int nargs, int nresults, int ctx, lua_CFunction k) { fputs("warning: lua_callk is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_getctx	(lua_State *L, int *ctx) { fputs("warning: lua_getctx is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_pcallk	(lua_State *L, int nargs, int nresults, int errfunc, int ctx, lua_CFunction k) { fputs("warning: lua_pcallk is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_load	(lua_State *L, lua_Reader reader, void *dt, const char *chunkname, const char *mode) { fputs("warning: lua_load is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_dump	(lua_State *L, lua_Writer writer, void *data) { fputs("warning: lua_dump is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_yieldk	(lua_State *L, int nresults, int ctx, lua_CFunction k) { fputs("warning: lua_yieldk is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_resume	(lua_State *L, lua_State *from, int narg) { fputs("warning: lua_resume is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_status	(lua_State *L) { fputs("warning: lua_status is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_gc	(lua_State *L, int what, int data) { fputs("warning: lua_gc is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_error	(lua_State *L) { fputs("warning: lua_error is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_next	(lua_State *L, int idx) { fputs("warning: lua_next is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_concat	(lua_State *L, int n) { fputs("warning: lua_concat is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_len	(lua_State *L, int idx) { fputs("warning: lua_len is a stub", stderr); }
static	lua_Alloc 	__lite_xl_fallback_lua_getallocf	(lua_State *L, void **ud) { fputs("warning: lua_getallocf is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_setallocf	(lua_State *L, lua_Alloc f, void *ud) { fputs("warning: lua_setallocf is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_getstack	(lua_State *L, int level, lua_Debug *ar) { fputs("warning: lua_getstack is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_getinfo	(lua_State *L, const char *what, lua_Debug *ar) { fputs("warning: lua_getinfo is a stub", stderr); }
static	const char *	__lite_xl_fallback_lua_getlocal	(lua_State *L, const lua_Debug *ar, int n) { fputs("warning: lua_getlocal is a stub", stderr); }
static	const char *	__lite_xl_fallback_lua_setlocal	(lua_State *L, const lua_Debug *ar, int n) { fputs("warning: lua_setlocal is a stub", stderr); }
static	const char *	__lite_xl_fallback_lua_getupvalue	(lua_State *L, int funcindex, int n) { fputs("warning: lua_getupvalue is a stub", stderr); }
static	const char *	__lite_xl_fallback_lua_setupvalue	(lua_State *L, int funcindex, int n) { fputs("warning: lua_setupvalue is a stub", stderr); }
static	void *	__lite_xl_fallback_lua_upvalueid	(lua_State *L, int fidx, int n) { fputs("warning: lua_upvalueid is a stub", stderr); }
static	void 	__lite_xl_fallback_lua_upvaluejoin	(lua_State *L, int fidx1, int n1, int fidx2, int n2) { fputs("warning: lua_upvaluejoin is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_sethook	(lua_State *L, lua_Hook func, int mask, int count) { fputs("warning: lua_sethook is a stub", stderr); }
static	lua_Hook 	__lite_xl_fallback_lua_gethook	(lua_State *L) { fputs("warning: lua_gethook is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_gethookmask	(lua_State *L) { fputs("warning: lua_gethookmask is a stub", stderr); }
static	int 	__lite_xl_fallback_lua_gethookcount	(lua_State *L) { fputs("warning: lua_gethookcount is a stub", stderr); }

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
static	void (*luaL_checkversion_)	(lua_State *L, lua_Number ver);
static	int (*luaL_getmetafield)	(lua_State *L, int obj, const char *e);
static	int (*luaL_callmeta)	(lua_State *L, int obj, const char *e);
static	const char *(*luaL_tolstring)	(lua_State *L, int idx, size_t *len);
static	int (*luaL_argerror)	(lua_State *L, int numarg, const char *extramsg);
static	const char *(*luaL_checklstring)	(lua_State *L, int numArg, size_t *l);
static	const char *(*luaL_optlstring)	(lua_State *L, int numArg, const char *def, size_t *l);
static	lua_Number (*luaL_checknumber)	(lua_State *L, int numArg);
static	lua_Number (*luaL_optnumber)	(lua_State *L, int nArg, lua_Number def);
static	lua_Integer (*luaL_checkinteger)	(lua_State *L, int numArg);
static	lua_Integer (*luaL_optinteger)	(lua_State *L, int nArg, lua_Integer def);
static	lua_Unsigned (*luaL_checkunsigned)	(lua_State *L, int numArg);
static	lua_Unsigned (*luaL_optunsigned)	(lua_State *L, int numArg, lua_Unsigned def);
static	void (*luaL_checkstack)	(lua_State *L, int sz, const char *msg);
static	void (*luaL_checktype)	(lua_State *L, int narg, int t);
static	void (*luaL_checkany)	(lua_State *L, int narg);
static	int (*luaL_newmetatable)	(lua_State *L, const char *tname);
static	void (*luaL_setmetatable)	(lua_State *L, const char *tname);
static	void *(*luaL_testudata)	(lua_State *L, int ud, const char *tname);
static	void *(*luaL_checkudata)	(lua_State *L, int ud, const char *tname);
static	void (*luaL_where)	(lua_State *L, int lvl);
static	int (*luaL_error)	(lua_State *L, const char *fmt, ...);
static	int (*luaL_checkoption)	(lua_State *L, int narg, const char *def, const char *const lst[]);
static	int (*luaL_fileresult)	(lua_State *L, int stat, const char *fname);
static	int (*luaL_execresult)	(lua_State *L, int stat);
static	int (*luaL_ref)	(lua_State *L, int t);
static	void (*luaL_unref)	(lua_State *L, int t, int ref);
static	int (*luaL_loadfilex)	(lua_State *L, const char *filename, const char *mode);
static	int (*luaL_loadbufferx)	(lua_State *L, const char *buff, size_t sz, const char *name, const char *mode);
static	int (*luaL_loadstring)	(lua_State *L, const char *s);
static	lua_State *(*luaL_newstate)	(void);
static	int (*luaL_len)	(lua_State *L, int idx);
static	const char *(*luaL_gsub)	(lua_State *L, const char *s, const char *p, const char *r);
static	void (*luaL_setfuncs)	(lua_State *L, const luaL_Reg *l, int nup);
static	int (*luaL_getsubtable)	(lua_State *L, int idx, const char *fname);
static	void (*luaL_traceback)	(lua_State *L, lua_State *L1, const char *msg, int level);
static	void (*luaL_requiref)	(lua_State *L, const char *modname, lua_CFunction openf, int glb);
static	void (*luaL_buffinit)	(lua_State *L, luaL_Buffer *B);
static	char *(*luaL_prepbuffsize)	(luaL_Buffer *B, size_t sz);
static	void (*luaL_addlstring)	(luaL_Buffer *B, const char *s, size_t l);
static	void (*luaL_addstring)	(luaL_Buffer *B, const char *s);
static	void (*luaL_addvalue)	(luaL_Buffer *B);
static	void (*luaL_pushresult)	(luaL_Buffer *B);
static	void (*luaL_pushresultsize)	(luaL_Buffer *B, size_t sz);
static	char *(*luaL_buffinitsize)	(lua_State *L, luaL_Buffer *B, size_t sz);
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
static	void 	__lite_xl_fallback_luaL_checkversion_	(lua_State *L, lua_Number ver) { fputs("warning: luaL_checkversion_ is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_getmetafield	(lua_State *L, int obj, const char *e) { fputs("warning: luaL_getmetafield is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_callmeta	(lua_State *L, int obj, const char *e) { fputs("warning: luaL_callmeta is a stub", stderr); }
static	const char *	__lite_xl_fallback_luaL_tolstring	(lua_State *L, int idx, size_t *len) { fputs("warning: luaL_tolstring is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_argerror	(lua_State *L, int numarg, const char *extramsg) { fputs("warning: luaL_argerror is a stub", stderr); }
static	const char *	__lite_xl_fallback_luaL_checklstring	(lua_State *L, int numArg, size_t *l) { fputs("warning: luaL_checklstring is a stub", stderr); }
static	const char *	__lite_xl_fallback_luaL_optlstring	(lua_State *L, int numArg, const char *def, size_t *l) { fputs("warning: luaL_optlstring is a stub", stderr); }
static	lua_Number 	__lite_xl_fallback_luaL_checknumber	(lua_State *L, int numArg) { fputs("warning: luaL_checknumber is a stub", stderr); }
static	lua_Number 	__lite_xl_fallback_luaL_optnumber	(lua_State *L, int nArg, lua_Number def) { fputs("warning: luaL_optnumber is a stub", stderr); }
static	lua_Integer 	__lite_xl_fallback_luaL_checkinteger	(lua_State *L, int numArg) { fputs("warning: luaL_checkinteger is a stub", stderr); }
static	lua_Integer 	__lite_xl_fallback_luaL_optinteger	(lua_State *L, int nArg, lua_Integer def) { fputs("warning: luaL_optinteger is a stub", stderr); }
static	lua_Unsigned 	__lite_xl_fallback_luaL_checkunsigned	(lua_State *L, int numArg) { fputs("warning: luaL_checkunsigned is a stub", stderr); }
static	lua_Unsigned 	__lite_xl_fallback_luaL_optunsigned	(lua_State *L, int numArg, lua_Unsigned def) { fputs("warning: luaL_optunsigned is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_checkstack	(lua_State *L, int sz, const char *msg) { fputs("warning: luaL_checkstack is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_checktype	(lua_State *L, int narg, int t) { fputs("warning: luaL_checktype is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_checkany	(lua_State *L, int narg) { fputs("warning: luaL_checkany is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_newmetatable	(lua_State *L, const char *tname) { fputs("warning: luaL_newmetatable is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_setmetatable	(lua_State *L, const char *tname) { fputs("warning: luaL_setmetatable is a stub", stderr); }
static	void *	__lite_xl_fallback_luaL_testudata	(lua_State *L, int ud, const char *tname) { fputs("warning: luaL_testudata is a stub", stderr); }
static	void *	__lite_xl_fallback_luaL_checkudata	(lua_State *L, int ud, const char *tname) { fputs("warning: luaL_checkudata is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_where	(lua_State *L, int lvl) { fputs("warning: luaL_where is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_error	(lua_State *L, const char *fmt, ...) { fputs("warning: luaL_error is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_checkoption	(lua_State *L, int narg, const char *def, const char *const lst[]) { fputs("warning: luaL_checkoption is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_fileresult	(lua_State *L, int stat, const char *fname) { fputs("warning: luaL_fileresult is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_execresult	(lua_State *L, int stat) { fputs("warning: luaL_execresult is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_ref	(lua_State *L, int t) { fputs("warning: luaL_ref is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_unref	(lua_State *L, int t, int ref) { fputs("warning: luaL_unref is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_loadfilex	(lua_State *L, const char *filename, const char *mode) { fputs("warning: luaL_loadfilex is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_loadbufferx	(lua_State *L, const char *buff, size_t sz, const char *name, const char *mode) { fputs("warning: luaL_loadbufferx is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_loadstring	(lua_State *L, const char *s) { fputs("warning: luaL_loadstring is a stub", stderr); }
static	lua_State *	__lite_xl_fallback_luaL_newstate	(void) { fputs("warning: luaL_newstate is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_len	(lua_State *L, int idx) { fputs("warning: luaL_len is a stub", stderr); }
static	const char *	__lite_xl_fallback_luaL_gsub	(lua_State *L, const char *s, const char *p, const char *r) { fputs("warning: luaL_gsub is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_setfuncs	(lua_State *L, const luaL_Reg *l, int nup) { fputs("warning: luaL_setfuncs is a stub", stderr); }
static	int 	__lite_xl_fallback_luaL_getsubtable	(lua_State *L, int idx, const char *fname) { fputs("warning: luaL_getsubtable is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_traceback	(lua_State *L, lua_State *L1, const char *msg, int level) { fputs("warning: luaL_traceback is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_requiref	(lua_State *L, const char *modname, lua_CFunction openf, int glb) { fputs("warning: luaL_requiref is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_buffinit	(lua_State *L, luaL_Buffer *B) { fputs("warning: luaL_buffinit is a stub", stderr); }
static	char *	__lite_xl_fallback_luaL_prepbuffsize	(luaL_Buffer *B, size_t sz) { fputs("warning: luaL_prepbuffsize is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_addlstring	(luaL_Buffer *B, const char *s, size_t l) { fputs("warning: luaL_addlstring is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_addstring	(luaL_Buffer *B, const char *s) { fputs("warning: luaL_addstring is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_addvalue	(luaL_Buffer *B) { fputs("warning: luaL_addvalue is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_pushresult	(luaL_Buffer *B) { fputs("warning: luaL_pushresult is a stub", stderr); }
static	void 	__lite_xl_fallback_luaL_pushresultsize	(luaL_Buffer *B, size_t sz) { fputs("warning: luaL_pushresultsize is a stub", stderr); }
static	char *	__lite_xl_fallback_luaL_buffinitsize	(lua_State *L, luaL_Buffer *B, size_t sz) { fputs("warning: luaL_buffinitsize is a stub", stderr); }

#define IMPORT_SYMBOL(name, ret, ...) name = (name = (ret (*) (__VA_ARGS__)) symbol(#name), name == NULL ? &__lite_xl_fallback_##name : name)
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
	IMPORT_SYMBOL(lua_remove, void , lua_State *L, int idx);
	IMPORT_SYMBOL(lua_insert, void , lua_State *L, int idx);
	IMPORT_SYMBOL(lua_replace, void , lua_State *L, int idx);
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
	IMPORT_SYMBOL(lua_newuserdata, void *, lua_State *L, size_t sz);
	IMPORT_SYMBOL(lua_getmetatable, int , lua_State *L, int objindex);
	IMPORT_SYMBOL(lua_getuservalue, void , lua_State *L, int idx);
	IMPORT_SYMBOL(lua_setglobal, void , lua_State *L, const char *var);
	IMPORT_SYMBOL(lua_settable, void , lua_State *L, int idx);
	IMPORT_SYMBOL(lua_setfield, void , lua_State *L, int idx, const char *k);
	IMPORT_SYMBOL(lua_rawset, void , lua_State *L, int idx);
	IMPORT_SYMBOL(lua_rawseti, void , lua_State *L, int idx, int n);
	IMPORT_SYMBOL(lua_rawsetp, void , lua_State *L, int idx, const void *p);
	IMPORT_SYMBOL(lua_setmetatable, int , lua_State *L, int objindex);
	IMPORT_SYMBOL(lua_setuservalue, void , lua_State *L, int idx);
	IMPORT_SYMBOL(lua_callk, void , lua_State *L, int nargs, int nresults, int ctx, lua_CFunction k);
	IMPORT_SYMBOL(lua_getctx, int , lua_State *L, int *ctx);
	IMPORT_SYMBOL(lua_pcallk, int , lua_State *L, int nargs, int nresults, int errfunc, int ctx, lua_CFunction k);
	IMPORT_SYMBOL(lua_load, int , lua_State *L, lua_Reader reader, void *dt, const char *chunkname, const char *mode);
	IMPORT_SYMBOL(lua_dump, int , lua_State *L, lua_Writer writer, void *data);
	IMPORT_SYMBOL(lua_yieldk, int , lua_State *L, int nresults, int ctx, lua_CFunction k);
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
}
#endif
