/**
 * lite_xl_plugin_api.h
 * API for writing C extension modules loaded by Lite XL.
 * This file is licensed under MIT.
 * 
 * The Lite XL plugin API is quite simple.
 * You would write a lua C extension and replace any references to lua.h, lauxlib.h
 * and lualib.h with lite_xl_plugin_api.h.
 * In your main file (where your entrypoint resides), define LITE_XL_PLUGIN_ENTRYPOINT.
 * If you have multiple entrypoints, define LITE_XL_PLUGIN_ENTRYPOINT in one of them.
 * 
 * After that, you need to create a Lite XL entrypoint, which is formatted as
 * luaopen_lite_xl_xxxxx instead of luaopen_xxxxx.
 * This entrypoint accepts a lua_State and an extra parameter of type void *.
 * In this entrypoint, call lite_xl_plugin_init() with the extra parameter.
 * If you have multiple entrypoints, you must call lite_xl_plugin_init() in
 * each of them.
 * This function is not thread safe, so don't try to do anything stupid.
 * 
 * An example:
 * 
 * #define LITE_XL_PLUGIN_ENTRYPOINT
 * #include "lite_xl_plugin_api.h"
 * int luaopen_lite_xl_xxxxx(lua_State* L, void* XL) {
 *   lite_xl_plugin_init(XL);
 *   ...
 *   return 1;
 * }
 * 
 * You can compile the library just like any Lua library without linking to Lua.
 * An example command would be: gcc -shared -o xxxxx.so xxxxx.c
 * You must not link to ANY lua library to avoid symbol collision.
 * 
 * This file contains stock configuration for a typical installation of Lua 5.4.
 * DO NOT MODIFY ANYTHING. MODIFYING STUFFS IN HERE WILL BREAK
 * COMPATIBILITY WITH LITE XL AND CAUSE UNDEBUGGABLE BUGS.
**/
#ifndef LITE_XL_PLUGIN_API
#define LITE_XL_PLUGIN_API

#include <stdio.h>
#include <stdlib.h>

#ifdef __GNUC__
#define UNUSED __attribute__((__unused__))
#else
#define UNUSED
#endif

/* FOR_EACH macro */
#define CONCAT(arg1, arg2)   CONCAT1(arg1, arg2)
#define CONCAT1(arg1, arg2)  CONCAT2(arg1, arg2)
#define CONCAT2(arg1, arg2)  arg1##arg2
#define FE_1(what, x) what x
#define FE_2(what, x, ...) what x,FE_1(what, __VA_ARGS__)
#define FE_3(what, x, ...) what x,FE_2(what, __VA_ARGS__)
#define FE_4(what, x, ...) what x,FE_3(what,  __VA_ARGS__)
#define FE_5(what, x, ...) what x,FE_4(what,  __VA_ARGS__)
#define FE_6(what, x, ...) what x,FE_5(what,  __VA_ARGS__)
#define FE_7(what, x, ...) what x,FE_6(what,  __VA_ARGS__)
#define FE_8(what, x, ...) what x,FE_7(what,  __VA_ARGS__)
#define FOR_EACH_NARG(...) FOR_EACH_NARG_(__VA_ARGS__, FOR_EACH_RSEQ_N())
#define FOR_EACH_NARG_(...) FOR_EACH_ARG_N(__VA_ARGS__) 
#define FOR_EACH_ARG_N(_1, _2, _3, _4, _5, _6, _7, _8, N, ...) N 
#define FOR_EACH_RSEQ_N() 8, 7, 6, 5, 4, 3, 2, 1, 0
#define FOR_EACH_(N, what, ...) CONCAT(FE_, N)(what, __VA_ARGS__)
#define FOR_EACH(what, ...) FOR_EACH_(FOR_EACH_NARG(__VA_ARGS__), what, __VA_ARGS__)

#define SYMBOL_WRAP_DECL(ret, name, ...) \
  ret name(__VA_ARGS__)

#define SYMBOL_WRAP_CALL(name, ...) \
  __##name(__VA_ARGS__)

#define SYMBOL_WRAP_CALL_FB(name, ...) \
  return __lite_xl_fallback_##name(__VA_ARGS__)

#ifdef LITE_XL_PLUGIN_ENTRYPOINT
  #define SYMBOL_DECLARE(ret, name, ...) \
    static ret (*__##name)  (__VA_ARGS__); \
    SYMBOL_WRAP_DECL(ret, name, __VA_ARGS__); \
    static ret __lite_xl_fallback_##name(FOR_EACH(UNUSED, __VA_ARGS__)) { \
      fputs("warning: " #name " is a stub", stderr); \
      exit(1); \
    }
  #define SYMBOL_DECLARE_VARARG(ret, name, ...) \
    static ret (*__##name)  (__VA_ARGS__, ...); \
    SYMBOL_WRAP_DECL(ret, name, __VA_ARGS__, ...); \
    static ret __lite_xl_fallback_##name(FOR_EACH(UNUSED, __VA_ARGS__), ...) { \
      fputs("warning: " #name " is a stub", stderr); \
      exit(1); \
    }
#else
  #define SYMBOL_DECLARE(ret, name, ...) \
    SYMBOL_WRAP_DECL(ret, name, __VA_ARGS__);
  #define SYMBOL_DECLARE_VARARG(ret, name, ...) \
    SYMBOL_WRAP_DECL(ret, name, __VA_ARGS__, ...);
#endif





/*
** $Id: luaconf.h $
** Configuration file for Lua
** See Copyright Notice in lua.h
*/


#ifndef luaconf_h
#define luaconf_h

#include <limits.h>
#include <stddef.h>


/*
** ===================================================================
** General Configuration File for Lua
**
** Some definitions here can be changed externally, through the compiler
** (e.g., with '-D' options): They are commented out or protected
** by '#if !defined' guards. However, several other definitions
** should be changed directly here, either because they affect the
** Lua ABI (by making the changes here, you ensure that all software
** connected to Lua, such as C libraries, will be compiled with the same
** configuration); or because they are seldom changed.
**
** Search for "@@" to find all configurable definitions.
** ===================================================================
*/


/*
** {====================================================================
** System Configuration: macros to adapt (if needed) Lua to some
** particular platform, for instance restricting it to C89.
** =====================================================================
*/

/*
@@ LUA_USE_C89 controls the use of non-ISO-C89 features.
** Define it if you want Lua to avoid the use of a few C99 features
** or Windows-specific features on Windows.
*/
/* #define LUA_USE_C89 */


/*
** By default, Lua on Windows use (some) specific Windows features
*/
#if !defined(LUA_USE_C89) && defined(_WIN32) && !defined(_WIN32_WCE)
#define LUA_USE_WINDOWS  /* enable goodies for regular Windows */
#endif


#if defined(LUA_USE_WINDOWS)
#define LUA_DL_DLL      /* enable support for DLL */
#define LUA_USE_C89     /* broadly, Windows is C89 */
#endif


#if defined(LUA_USE_LINUX)
#define LUA_USE_POSIX
#define LUA_USE_DLOPEN          /* needs an extra library: -ldl */
#endif


#if defined(LUA_USE_MACOSX)
#define LUA_USE_POSIX
#define LUA_USE_DLOPEN          /* MacOS does not need -ldl */
#endif


/*
@@ LUAI_IS32INT is true iff 'int' has (at least) 32 bits.
*/
#define LUAI_IS32INT    ((UINT_MAX >> 30) >= 3)

/* }================================================================== */



/*
** {==================================================================
** Configuration for Number types. These options should not be
** set externally, because any other code connected to Lua must
** use the same configuration.
** ===================================================================
*/

/*
@@ LUA_INT_TYPE defines the type for Lua integers.
@@ LUA_FLOAT_TYPE defines the type for Lua floats.
** Lua should work fine with any mix of these options supported
** by your C compiler. The usual configurations are 64-bit integers
** and 'double' (the default), 32-bit integers and 'float' (for
** restricted platforms), and 'long'/'double' (for C compilers not
** compliant with C99, which may not have support for 'long long').
*/

/* predefined options for LUA_INT_TYPE */
#define LUA_INT_INT             1
#define LUA_INT_LONG            2
#define LUA_INT_LONGLONG        3

/* predefined options for LUA_FLOAT_TYPE */
#define LUA_FLOAT_FLOAT         1
#define LUA_FLOAT_DOUBLE        2
#define LUA_FLOAT_LONGDOUBLE    3


/* Default configuration ('long long' and 'double', for 64-bit Lua) */
#define LUA_INT_DEFAULT         LUA_INT_LONGLONG
#define LUA_FLOAT_DEFAULT       LUA_FLOAT_DOUBLE


/*
@@ LUA_32BITS enables Lua with 32-bit integers and 32-bit floats.
*/
#define LUA_32BITS      0


/*
@@ LUA_C89_NUMBERS ensures that Lua uses the largest types available for
** C89 ('long' and 'double'); Windows always has '__int64', so it does
** not need to use this case.
*/
#if defined(LUA_USE_C89) && !defined(LUA_USE_WINDOWS)
#define LUA_C89_NUMBERS         1
#else
#define LUA_C89_NUMBERS         0
#endif


#if LUA_32BITS          /* { */
/*
** 32-bit integers and 'float'
*/
#if LUAI_IS32INT  /* use 'int' if big enough */
#define LUA_INT_TYPE    LUA_INT_INT
#else  /* otherwise use 'long' */
#define LUA_INT_TYPE    LUA_INT_LONG
#endif
#define LUA_FLOAT_TYPE  LUA_FLOAT_FLOAT

#elif LUA_C89_NUMBERS   /* }{ */
/*
** largest types available for C89 ('long' and 'double')
*/
#define LUA_INT_TYPE    LUA_INT_LONG
#define LUA_FLOAT_TYPE  LUA_FLOAT_DOUBLE

#else           /* }{ */
/* use defaults */

#define LUA_INT_TYPE    LUA_INT_DEFAULT
#define LUA_FLOAT_TYPE  LUA_FLOAT_DEFAULT

#endif                          /* } */


/* }================================================================== */



/*
** {==================================================================
** Configuration for Paths.
** ===================================================================
*/

/*
** LUA_PATH_SEP is the character that separates templates in a path.
** LUA_PATH_MARK is the string that marks the substitution points in a
** template.
** LUA_EXEC_DIR in a Windows path is replaced by the executable's
** directory.
*/
#define LUA_PATH_SEP            ";"
#define LUA_PATH_MARK           "?"
#define LUA_EXEC_DIR            "!"


/*
@@ LUA_PATH_DEFAULT is the default path that Lua uses to look for
** Lua libraries.
@@ LUA_CPATH_DEFAULT is the default path that Lua uses to look for
** C libraries.
** CHANGE them if your machine has a non-conventional directory
** hierarchy or if you want to install your libraries in
** non-conventional directories.
*/

#define LUA_VDIR        LUA_VERSION_MAJOR "." LUA_VERSION_MINOR
#if defined(_WIN32)     /* { */
/*
** In Windows, any exclamation mark ('!') in the path is replaced by the
** path of the directory of the executable file of the current process.
*/
#define LUA_LDIR        "!\\lua\\"
#define LUA_CDIR        "!\\"
#define LUA_SHRDIR      "!\\..\\share\\lua\\" LUA_VDIR "\\"

#if !defined(LUA_PATH_DEFAULT)
#define LUA_PATH_DEFAULT  \
                LUA_LDIR"?.lua;"  LUA_LDIR"?\\init.lua;" \
                LUA_CDIR"?.lua;"  LUA_CDIR"?\\init.lua;" \
                LUA_SHRDIR"?.lua;" LUA_SHRDIR"?\\init.lua;" \
                ".\\?.lua;" ".\\?\\init.lua"
#endif

#if !defined(LUA_CPATH_DEFAULT)
#define LUA_CPATH_DEFAULT \
                LUA_CDIR"?.dll;" \
                LUA_CDIR"..\\lib\\lua\\" LUA_VDIR "\\?.dll;" \
                LUA_CDIR"loadall.dll;" ".\\?.dll"
#endif

#else                   /* }{ */

#define LUA_ROOT        "/usr/local/"
#define LUA_LDIR        LUA_ROOT "share/lua/" LUA_VDIR "/"
#define LUA_CDIR        LUA_ROOT "lib/lua/" LUA_VDIR "/"

#if !defined(LUA_PATH_DEFAULT)
#define LUA_PATH_DEFAULT  \
                LUA_LDIR"?.lua;"  LUA_LDIR"?/init.lua;" \
                LUA_CDIR"?.lua;"  LUA_CDIR"?/init.lua;" \
                "./?.lua;" "./?/init.lua"
#endif

#if !defined(LUA_CPATH_DEFAULT)
#define LUA_CPATH_DEFAULT \
                LUA_CDIR"?.so;" LUA_CDIR"loadall.so;" "./?.so"
#endif

#endif                  /* } */


/*
@@ LUA_DIRSEP is the directory separator (for submodules).
** CHANGE it if your machine does not use "/" as the directory separator
** and is not Windows. (On Windows Lua automatically uses "\".)
*/
#if !defined(LUA_DIRSEP)

#if defined(_WIN32)
#define LUA_DIRSEP      "\\"
#else
#define LUA_DIRSEP      "/"
#endif

#endif

/* }================================================================== */


/*
** {==================================================================
** Marks for exported symbols in the C code
** ===================================================================
*/

/*
@@ LUA_API is a mark for all core API functions.
@@ LUALIB_API is a mark for all auxiliary library functions.
@@ LUAMOD_API is a mark for all standard library opening functions.
** CHANGE them if you need to define those functions in some special way.
** For instance, if you want to create one Windows DLL with the core and
** the libraries, you may want to use the following definition (define
** LUA_BUILD_AS_DLL to get it).
*/
#if defined(LUA_BUILD_AS_DLL)   /* { */

#if defined(LUA_CORE) || defined(LUA_LIB)       /* { */
#define LUA_API __declspec(dllexport)
#else                                           /* }{ */
#define LUA_API __declspec(dllimport)
#endif                                          /* } */

#else                           /* }{ */

#define LUA_API         extern

#endif                          /* } */


/*
** More often than not the libs go together with the core.
*/
#define LUALIB_API      LUA_API
#define LUAMOD_API      LUA_API


/*
@@ LUAI_FUNC is a mark for all extern functions that are not to be
** exported to outside modules.
@@ LUAI_DDEF and LUAI_DDEC are marks for all extern (const) variables,
** none of which to be exported to outside modules (LUAI_DDEF for
** definitions and LUAI_DDEC for declarations).
** CHANGE them if you need to mark them in some special way. Elf/gcc
** (versions 3.2 and later) mark them as "hidden" to optimize access
** when Lua is compiled as a shared library. Not all elf targets support
** this attribute. Unfortunately, gcc does not offer a way to check
** whether the target offers that support, and those without support
** give a warning about it. To avoid these warnings, change to the
** default definition.
*/
#if defined(__GNUC__) && ((__GNUC__*100 + __GNUC_MINOR__) >= 302) && \
    defined(__ELF__)            /* { */
#define LUAI_FUNC       __attribute__((visibility("internal"))) extern
#else                           /* }{ */
#define LUAI_FUNC       extern
#endif                          /* } */

#define LUAI_DDEC(dec)  LUAI_FUNC dec
#define LUAI_DDEF       /* empty */

/* }================================================================== */


/*
** {==================================================================
** Compatibility with previous versions
** ===================================================================
*/

/*
@@ LUA_COMPAT_5_3 controls other macros for compatibility with Lua 5.3.
** You can define it to get all options, or change specific options
** to fit your specific needs.
*/
#if defined(LUA_COMPAT_5_3)     /* { */

/*
@@ LUA_COMPAT_MATHLIB controls the presence of several deprecated
** functions in the mathematical library.
** (These functions were already officially removed in 5.3;
** nevertheless they are still available here.)
*/
#define LUA_COMPAT_MATHLIB

/*
@@ LUA_COMPAT_APIINTCASTS controls the presence of macros for
** manipulating other integer types (lua_pushunsigned, lua_tounsigned,
** luaL_checkint, luaL_checklong, etc.)
** (These macros were also officially removed in 5.3, but they are still
** available here.)
*/
#define LUA_COMPAT_APIINTCASTS


/*
@@ LUA_COMPAT_LT_LE controls the emulation of the '__le' metamethod
** using '__lt'.
*/
#define LUA_COMPAT_LT_LE


/*
@@ The following macros supply trivial compatibility for some
** changes in the API. The macros themselves document how to
** change your code to avoid using them.
** (Once more, these macros were officially removed in 5.3, but they are
** still available here.)
*/
#define lua_strlen(L,i)         lua_rawlen(L, (i))

#define lua_objlen(L,i)         lua_rawlen(L, (i))

#define lua_equal(L,idx1,idx2)          lua_compare(L,(idx1),(idx2),LUA_OPEQ)
#define lua_lessthan(L,idx1,idx2)       lua_compare(L,(idx1),(idx2),LUA_OPLT)

#endif                          /* } */

/* }================================================================== */



/*
** {==================================================================
** Configuration for Numbers (low-level part).
** Change these definitions if no predefined LUA_FLOAT_* / LUA_INT_*
** satisfy your needs.
** ===================================================================
*/

/*
@@ LUAI_UACNUMBER is the result of a 'default argument promotion'
@@ over a floating number.
@@ l_floatatt(x) corrects float attribute 'x' to the proper float type
** by prefixing it with one of FLT/DBL/LDBL.
@@ LUA_NUMBER_FRMLEN is the length modifier for writing floats.
@@ LUA_NUMBER_FMT is the format for writing floats.
@@ lua_number2str converts a float to a string.
@@ l_mathop allows the addition of an 'l' or 'f' to all math operations.
@@ l_floor takes the floor of a float.
@@ lua_str2number converts a decimal numeral to a number.
*/


/* The following definitions are good for most cases here */

#define l_floor(x)              (l_mathop(floor)(x))

#define lua_number2str(s,sz,n)  \
        l_sprintf((s), sz, LUA_NUMBER_FMT, (LUAI_UACNUMBER)(n))

/*
@@ lua_numbertointeger converts a float number with an integral value
** to an integer, or returns 0 if float is not within the range of
** a lua_Integer.  (The range comparisons are tricky because of
** rounding. The tests here assume a two-complement representation,
** where MININTEGER always has an exact representation as a float;
** MAXINTEGER may not have one, and therefore its conversion to float
** may have an ill-defined value.)
*/
#define lua_numbertointeger(n,p) \
  ((n) >= (LUA_NUMBER)(LUA_MININTEGER) && \
   (n) < -(LUA_NUMBER)(LUA_MININTEGER) && \
      (*(p) = (LUA_INTEGER)(n), 1))


/* now the variable definitions */

#if LUA_FLOAT_TYPE == LUA_FLOAT_FLOAT           /* { single float */

#define LUA_NUMBER      float

#define l_floatatt(n)           (FLT_##n)

#define LUAI_UACNUMBER  double

#define LUA_NUMBER_FRMLEN       ""
#define LUA_NUMBER_FMT          "%.7g"

#define l_mathop(op)            op##f

#define lua_str2number(s,p)     strtof((s), (p))


#elif LUA_FLOAT_TYPE == LUA_FLOAT_LONGDOUBLE    /* }{ long double */

#define LUA_NUMBER      long double

#define l_floatatt(n)           (LDBL_##n)

#define LUAI_UACNUMBER  long double

#define LUA_NUMBER_FRMLEN       "L"
#define LUA_NUMBER_FMT          "%.19Lg"

#define l_mathop(op)            op##l

#define lua_str2number(s,p)     strtold((s), (p))

#elif LUA_FLOAT_TYPE == LUA_FLOAT_DOUBLE        /* }{ double */

#define LUA_NUMBER      double

#define l_floatatt(n)           (DBL_##n)

#define LUAI_UACNUMBER  double

#define LUA_NUMBER_FRMLEN       ""
#define LUA_NUMBER_FMT          "%.14g"

#define l_mathop(op)            op

#define lua_str2number(s,p)     strtod((s), (p))

#else                                           /* }{ */

#error "numeric float type not defined"

#endif                                  /* } */



/*
@@ LUA_UNSIGNED is the unsigned version of LUA_INTEGER.
@@ LUAI_UACINT is the result of a 'default argument promotion'
@@ over a LUA_INTEGER.
@@ LUA_INTEGER_FRMLEN is the length modifier for reading/writing integers.
@@ LUA_INTEGER_FMT is the format for writing integers.
@@ LUA_MAXINTEGER is the maximum value for a LUA_INTEGER.
@@ LUA_MININTEGER is the minimum value for a LUA_INTEGER.
@@ LUA_MAXUNSIGNED is the maximum value for a LUA_UNSIGNED.
@@ lua_integer2str converts an integer to a string.
*/


/* The following definitions are good for most cases here */

#define LUA_INTEGER_FMT         "%" LUA_INTEGER_FRMLEN "d"

#define LUAI_UACINT             LUA_INTEGER

#define lua_integer2str(s,sz,n)  \
        l_sprintf((s), sz, LUA_INTEGER_FMT, (LUAI_UACINT)(n))

/*
** use LUAI_UACINT here to avoid problems with promotions (which
** can turn a comparison between unsigneds into a signed comparison)
*/
#define LUA_UNSIGNED            unsigned LUAI_UACINT


/* now the variable definitions */

#if LUA_INT_TYPE == LUA_INT_INT         /* { int */

#define LUA_INTEGER             int
#define LUA_INTEGER_FRMLEN      ""

#define LUA_MAXINTEGER          INT_MAX
#define LUA_MININTEGER          INT_MIN

#define LUA_MAXUNSIGNED         UINT_MAX

#elif LUA_INT_TYPE == LUA_INT_LONG      /* }{ long */

#define LUA_INTEGER             long
#define LUA_INTEGER_FRMLEN      "l"

#define LUA_MAXINTEGER          LONG_MAX
#define LUA_MININTEGER          LONG_MIN

#define LUA_MAXUNSIGNED         ULONG_MAX

#elif LUA_INT_TYPE == LUA_INT_LONGLONG  /* }{ long long */

/* use presence of macro LLONG_MAX as proxy for C99 compliance */
#if defined(LLONG_MAX)          /* { */
/* use ISO C99 stuff */

#define LUA_INTEGER             long long
#define LUA_INTEGER_FRMLEN      "ll"

#define LUA_MAXINTEGER          LLONG_MAX
#define LUA_MININTEGER          LLONG_MIN

#define LUA_MAXUNSIGNED         ULLONG_MAX

#elif defined(LUA_USE_WINDOWS) /* }{ */
/* in Windows, can use specific Windows types */

#define LUA_INTEGER             __int64
#define LUA_INTEGER_FRMLEN      "I64"

#define LUA_MAXINTEGER          _I64_MAX
#define LUA_MININTEGER          _I64_MIN

#define LUA_MAXUNSIGNED         _UI64_MAX

#else                           /* }{ */

#error "Compiler does not support 'long long'. Use option '-DLUA_32BITS' \
  or '-DLUA_C89_NUMBERS' (see file 'luaconf.h' for details)"

#endif                          /* } */

#else                           /* }{ */

#error "numeric integer type not defined"

#endif                          /* } */

/* }================================================================== */


/*
** {==================================================================
** Dependencies with C99 and other C details
** ===================================================================
*/

/*
@@ l_sprintf is equivalent to 'snprintf' or 'sprintf' in C89.
** (All uses in Lua have only one format item.)
*/
#if !defined(LUA_USE_C89)
#define l_sprintf(s,sz,f,i)     snprintf(s,sz,f,i)
#else
#define l_sprintf(s,sz,f,i)     ((void)(sz), sprintf(s,f,i))
#endif


/*
@@ lua_strx2number converts a hexadecimal numeral to a number.
** In C99, 'strtod' does that conversion. Otherwise, you can
** leave 'lua_strx2number' undefined and Lua will provide its own
** implementation.
*/
#if !defined(LUA_USE_C89)
#define lua_strx2number(s,p)            lua_str2number(s,p)
#endif


/*
@@ lua_pointer2str converts a pointer to a readable string in a
** non-specified way.
*/
#define lua_pointer2str(buff,sz,p)      l_sprintf(buff,sz,"%p",p)


/*
@@ lua_number2strx converts a float to a hexadecimal numeral.
** In C99, 'sprintf' (with format specifiers '%a'/'%A') does that.
** Otherwise, you can leave 'lua_number2strx' undefined and Lua will
** provide its own implementation.
*/
#if !defined(LUA_USE_C89)
#define lua_number2strx(L,b,sz,f,n)  \
        ((void)L, l_sprintf(b,sz,f,(LUAI_UACNUMBER)(n)))
#endif


/*
** 'strtof' and 'opf' variants for math functions are not valid in
** C89. Otherwise, the macro 'HUGE_VALF' is a good proxy for testing the
** availability of these variants. ('math.h' is already included in
** all files that use these macros.)
*/
#if defined(LUA_USE_C89) || (defined(HUGE_VAL) && !defined(HUGE_VALF))
#undef l_mathop  /* variants not available */
#undef lua_str2number
#define l_mathop(op)            (lua_Number)op  /* no variant */
#define lua_str2number(s,p)     ((lua_Number)strtod((s), (p)))
#endif


/*
@@ LUA_KCONTEXT is the type of the context ('ctx') for continuation
** functions.  It must be a numerical type; Lua will use 'intptr_t' if
** available, otherwise it will use 'ptrdiff_t' (the nearest thing to
** 'intptr_t' in C89)
*/
#define LUA_KCONTEXT    ptrdiff_t

#if !defined(LUA_USE_C89) && defined(__STDC_VERSION__) && \
    __STDC_VERSION__ >= 199901L
#include <stdint.h>
#if defined(INTPTR_MAX)  /* even in C99 this type is optional */
#undef LUA_KCONTEXT
#define LUA_KCONTEXT    intptr_t
#endif
#endif


/*
@@ lua_getlocaledecpoint gets the locale "radix character" (decimal point).
** Change that if you do not want to use C locales. (Code using this
** macro must include the header 'locale.h'.)
*/
#if !defined(lua_getlocaledecpoint)
#define lua_getlocaledecpoint()         (localeconv()->decimal_point[0])
#endif


/*
** macros to improve jump prediction, used mostly for error handling
** and debug facilities. (Some macros in the Lua API use these macros.
** Define LUA_NOBUILTIN if you do not want '__builtin_expect' in your
** code.)
*/
#if !defined(luai_likely)

#if defined(__GNUC__) && !defined(LUA_NOBUILTIN)
#define luai_likely(x)          (__builtin_expect(((x) != 0), 1))
#define luai_unlikely(x)        (__builtin_expect(((x) != 0), 0))
#else
#define luai_likely(x)          (x)
#define luai_unlikely(x)        (x)
#endif

#endif


#if defined(LUA_CORE) || defined(LUA_LIB)
/* shorter names for Lua's own use */
#define l_likely(x)     luai_likely(x)
#define l_unlikely(x)   luai_unlikely(x)
#endif



/* }================================================================== */


/*
** {==================================================================
** Language Variations
** =====================================================================
*/

/*
@@ LUA_NOCVTN2S/LUA_NOCVTS2N control how Lua performs some
** coercions. Define LUA_NOCVTN2S to turn off automatic coercion from
** numbers to strings. Define LUA_NOCVTS2N to turn off automatic
** coercion from strings to numbers.
*/
/* #define LUA_NOCVTN2S */
/* #define LUA_NOCVTS2N */


/*
@@ LUA_USE_APICHECK turns on several consistency checks on the C API.
** Define it as a help when debugging C code.
*/
#if defined(LUA_USE_APICHECK)
#include <assert.h>
#define luai_apicheck(l,e)      assert(e)
#endif

/* }================================================================== */


/*
** {==================================================================
** Macros that affect the API and must be stable (that is, must be the
** same when you compile Lua and when you compile code that links to
** Lua).
** =====================================================================
*/

/*
@@ LUAI_MAXSTACK limits the size of the Lua stack.
** CHANGE it if you need a different limit. This limit is arbitrary;
** its only purpose is to stop Lua from consuming unlimited stack
** space (and to reserve some numbers for pseudo-indices).
** (It must fit into max(size_t)/32.)
*/
#if LUAI_IS32INT
#define LUAI_MAXSTACK           1000000
#else
#define LUAI_MAXSTACK           15000
#endif


/*
@@ LUA_EXTRASPACE defines the size of a raw memory area associated with
** a Lua state with very fast access.
** CHANGE it if you need a different size.
*/
#define LUA_EXTRASPACE          (sizeof(void *))


/*
@@ LUA_IDSIZE gives the maximum size for the description of the source
@@ of a function in debug information.
** CHANGE it if you want a different size.
*/
#define LUA_IDSIZE      60


/*
@@ LUAL_BUFFERSIZE is the buffer size used by the lauxlib buffer system.
*/
#define LUAL_BUFFERSIZE   ((int)(16 * sizeof(void*) * sizeof(lua_Number)))


/*
@@ LUAI_MAXALIGN defines fields that, when used in a union, ensure
** maximum alignment for the other items in that union.
*/
#define LUAI_MAXALIGN  lua_Number n; double u; void *s; lua_Integer i; long l

/* }================================================================== */

#endif





/*
** $Id: lua.h $
** Lua - A Scripting Language
** Lua.org, PUC-Rio, Brazil (http://www.lua.org)
** See Copyright Notice at the end of this file
*/


#ifndef lua_h
#define lua_h

#include <stdarg.h>
#include <stddef.h>


#define LUA_VERSION_MAJOR       "5"
#define LUA_VERSION_MINOR       "4"
#define LUA_VERSION_RELEASE     "4"

#define LUA_VERSION_NUM                 504
#define LUA_VERSION_RELEASE_NUM         (LUA_VERSION_NUM * 100 + 4)

#define LUA_VERSION     "Lua " LUA_VERSION_MAJOR "." LUA_VERSION_MINOR
#define LUA_RELEASE     LUA_VERSION "." LUA_VERSION_RELEASE
#define LUA_COPYRIGHT   LUA_RELEASE "  Copyright (C) 1994-2022 Lua.org, PUC-Rio"
#define LUA_AUTHORS     "R. Ierusalimschy, L. H. de Figueiredo, W. Celes"


/* mark for precompiled code ('<esc>Lua') */
#define LUA_SIGNATURE   "\x1bLua"

/* option for multiple returns in 'lua_pcall' and 'lua_call' */
#define LUA_MULTRET     (-1)


/*
** Pseudo-indices
** (-LUAI_MAXSTACK is the minimum valid index; we keep some free empty
** space after that to help overflow detection)
*/
#define LUA_REGISTRYINDEX       (-LUAI_MAXSTACK - 1000)
#define lua_upvalueindex(i)     (LUA_REGISTRYINDEX - (i))


/* thread status */
#define LUA_OK          0
#define LUA_YIELD       1
#define LUA_ERRRUN      2
#define LUA_ERRSYNTAX   3
#define LUA_ERRMEM      4
#define LUA_ERRERR      5


typedef struct lua_State lua_State;


/*
** basic types
*/
#define LUA_TNONE               (-1)

#define LUA_TNIL                0
#define LUA_TBOOLEAN            1
#define LUA_TLIGHTUSERDATA      2
#define LUA_TNUMBER             3
#define LUA_TSTRING             4
#define LUA_TTABLE              5
#define LUA_TFUNCTION           6
#define LUA_TUSERDATA           7
#define LUA_TTHREAD             8

#define LUA_NUMTYPES            9



/* minimum Lua stack available to a C function */
#define LUA_MINSTACK    20


/* predefined values in the registry */
#define LUA_RIDX_MAINTHREAD     1
#define LUA_RIDX_GLOBALS        2
#define LUA_RIDX_LAST           LUA_RIDX_GLOBALS


/* type of numbers in Lua */
typedef LUA_NUMBER lua_Number;


/* type for integer functions */
typedef LUA_INTEGER lua_Integer;

/* unsigned integer type */
typedef LUA_UNSIGNED lua_Unsigned;

/* type for continuation-function contexts */
typedef LUA_KCONTEXT lua_KContext;


/*
** Type for C functions registered with Lua
*/
typedef int (*lua_CFunction) (lua_State *L);

/*
** Type for continuation functions
*/
typedef int (*lua_KFunction) (lua_State *L, int status, lua_KContext ctx);


/*
** Type for functions that read/write blocks when loading/dumping Lua chunks
*/
typedef const char * (*lua_Reader) (lua_State *L, void *ud, size_t *sz);

typedef int (*lua_Writer) (lua_State *L, const void *p, size_t sz, void *ud);


/*
** Type for memory-allocation functions
*/
typedef void * (*lua_Alloc) (void *ud, void *ptr, size_t osize, size_t nsize);


/*
** Type for warning functions
*/
typedef void (*lua_WarnFunction) (void *ud, const char *msg, int tocont);




/*
** generic extra include file
*/
#if defined(LUA_USER_H)
#include LUA_USER_H
#endif


/*
** RCS ident string
*/
extern const char lua_ident[];


/*
** state manipulation
*/
SYMBOL_DECLARE(lua_State *, lua_newstate, lua_Alloc f, void *ud)
SYMBOL_DECLARE(void,        lua_close, lua_State *L)
SYMBOL_DECLARE(lua_State *, lua_newthread, lua_State *L)
SYMBOL_DECLARE(int,         lua_resetthread, lua_State *L)

SYMBOL_DECLARE(lua_CFunction, lua_atpanic, lua_State *L, lua_CFunction panicf)


SYMBOL_DECLARE(lua_Number, lua_version, lua_State *L)


/*
** basic stack manipulation
*/
SYMBOL_DECLARE(int , lua_absindex, lua_State *L, int idx)
SYMBOL_DECLARE(int , lua_gettop, lua_State *L)
SYMBOL_DECLARE(void, lua_settop, lua_State *L, int idx)
SYMBOL_DECLARE(void, lua_pushvalue, lua_State *L, int idx)
SYMBOL_DECLARE(void, lua_rotate, lua_State *L, int idx, int n)
SYMBOL_DECLARE(void, lua_copy, lua_State *L, int fromidx, int toidx)
SYMBOL_DECLARE(int , lua_checkstack, lua_State *L, int n)

SYMBOL_DECLARE(void, lua_xmove, lua_State *from, lua_State *to, int n)


/*
** access functions (stack -> C)
*/

SYMBOL_DECLARE(int             , lua_isnumber, lua_State *L, int idx)
SYMBOL_DECLARE(int             , lua_isstring, lua_State *L, int idx)
SYMBOL_DECLARE(int             , lua_iscfunction, lua_State *L, int idx)
SYMBOL_DECLARE(int             , lua_isinteger, lua_State *L, int idx)
SYMBOL_DECLARE(int             , lua_isuserdata, lua_State *L, int idx)
SYMBOL_DECLARE(int             , lua_type, lua_State *L, int idx)
SYMBOL_DECLARE(const char     *, lua_typename, lua_State *L, int tp)

SYMBOL_DECLARE(lua_Number      , lua_tonumberx, lua_State *L, int idx, int *isnum)
SYMBOL_DECLARE(lua_Integer     , lua_tointegerx, lua_State *L, int idx, int *isnum)
SYMBOL_DECLARE(int             , lua_toboolean, lua_State *L, int idx)
SYMBOL_DECLARE(const char     *, lua_tolstring, lua_State *L, int idx, size_t *len)
SYMBOL_DECLARE(lua_Unsigned    , lua_rawlen, lua_State *L, int idx)
SYMBOL_DECLARE(lua_CFunction   , lua_tocfunction, lua_State *L, int idx)
SYMBOL_DECLARE(void           *, lua_touserdata, lua_State *L, int idx)
SYMBOL_DECLARE(lua_State      *, lua_tothread, lua_State *L, int idx)
SYMBOL_DECLARE(const void     *, lua_topointer, lua_State *L, int idx)


/*
** Comparison and arithmetic functions
*/

#define LUA_OPADD       0       /* ORDER TM, ORDER OP */
#define LUA_OPSUB       1
#define LUA_OPMUL       2
#define LUA_OPMOD       3
#define LUA_OPPOW       4
#define LUA_OPDIV       5
#define LUA_OPIDIV      6
#define LUA_OPBAND      7
#define LUA_OPBOR       8
#define LUA_OPBXOR      9
#define LUA_OPSHL       10
#define LUA_OPSHR       11
#define LUA_OPUNM       12
#define LUA_OPBNOT      13

SYMBOL_DECLARE(void  , lua_arith, lua_State *L, int op)

#define LUA_OPEQ        0
#define LUA_OPLT        1
#define LUA_OPLE        2

SYMBOL_DECLARE(int   , lua_rawequal, lua_State *L, int idx1, int idx2)
SYMBOL_DECLARE(int   , lua_compare, lua_State *L, int idx1, int idx2, int op)


/*
** push functions (C -> stack)
*/
SYMBOL_DECLARE(void        , lua_pushnil, lua_State *L)
SYMBOL_DECLARE(void        , lua_pushnumber, lua_State *L, lua_Number n)
SYMBOL_DECLARE(void        , lua_pushinteger, lua_State *L, lua_Integer n)
SYMBOL_DECLARE(const char *, lua_pushlstring, lua_State *L, const char *s, size_t len)
SYMBOL_DECLARE(const char *, lua_pushstring, lua_State *L, const char *s)
SYMBOL_DECLARE(const char *, lua_pushvfstring, lua_State *L, const char *fmt,
                                                      va_list argp)
SYMBOL_DECLARE_VARARG(const char *, lua_pushfstring, lua_State *L, const char *fmt)
SYMBOL_DECLARE(void  , lua_pushcclosure, lua_State *L, lua_CFunction fn, int n)
SYMBOL_DECLARE(void  , lua_pushboolean, lua_State *L, int b)
SYMBOL_DECLARE(void  , lua_pushlightuserdata, lua_State *L, void *p)
SYMBOL_DECLARE(int   , lua_pushthread, lua_State *L)


/*
** get functions (Lua -> stack)
*/
SYMBOL_DECLARE(int , lua_getglobal, lua_State *L, const char *name)
SYMBOL_DECLARE(int , lua_gettable, lua_State *L, int idx)
SYMBOL_DECLARE(int , lua_getfield, lua_State *L, int idx, const char *k)
SYMBOL_DECLARE(int , lua_geti, lua_State *L, int idx, lua_Integer n)
SYMBOL_DECLARE(int , lua_rawget, lua_State *L, int idx)
SYMBOL_DECLARE(int , lua_rawgeti, lua_State *L, int idx, lua_Integer n)
SYMBOL_DECLARE(int , lua_rawgetp, lua_State *L, int idx, const void *p)

SYMBOL_DECLARE(void  , lua_createtable, lua_State *L, int narr, int nrec)
SYMBOL_DECLARE(void *, lua_newuserdatauv, lua_State *L, size_t sz, int nuvalue)
SYMBOL_DECLARE(int  , lua_getmetatable, lua_State *L, int objindex)
SYMBOL_DECLARE(int  , lua_getiuservalue, lua_State *L, int idx, int n)


/*
** set functions (stack -> Lua)
*/
SYMBOL_DECLARE(void  , lua_setglobal, lua_State *L, const char *name)
SYMBOL_DECLARE(void  , lua_settable, lua_State *L, int idx)
SYMBOL_DECLARE(void  , lua_setfield, lua_State *L, int idx, const char *k)
SYMBOL_DECLARE(void  , lua_seti, lua_State *L, int idx, lua_Integer n)
SYMBOL_DECLARE(void  , lua_rawset, lua_State *L, int idx)
SYMBOL_DECLARE(void  , lua_rawseti, lua_State *L, int idx, lua_Integer n)
SYMBOL_DECLARE(void  , lua_rawsetp, lua_State *L, int idx, const void *p)
SYMBOL_DECLARE(int   , lua_setmetatable, lua_State *L, int objindex)
SYMBOL_DECLARE(int   , lua_setiuservalue, lua_State *L, int idx, int n)


/*
** 'load' and 'call' functions (load and run Lua code)
*/
SYMBOL_DECLARE(void, lua_callk, lua_State *L, int nargs, int nresults,
                                lua_KContext ctx, lua_KFunction k)
#define lua_call(L,n,r)         lua_callk(L, (n), (r), 0, NULL)

SYMBOL_DECLARE(int, lua_pcallk, lua_State *L, int nargs, int nresults, int errfunc,
                                lua_KContext ctx, lua_KFunction k)
#define lua_pcall(L,n,r,f)      lua_pcallk(L, (n), (r), (f), 0, NULL)

SYMBOL_DECLARE(int, lua_load, lua_State *L, lua_Reader reader, void *dt,
                              const char *chunkname, const char *mode)

SYMBOL_DECLARE(int, lua_dump, lua_State *L, lua_Writer writer, void *data, int strip)


/*
** coroutine functions
*/
SYMBOL_DECLARE(int, lua_yieldk, lua_State *L, int nresults, lua_KContext ctx,
                                lua_KFunction k)
SYMBOL_DECLARE(int, lua_resume, lua_State *L, lua_State *from, int narg,
                                int *nres)
SYMBOL_DECLARE(int, lua_status, lua_State *L)
SYMBOL_DECLARE(int, lua_isyieldable, lua_State *L)

#define lua_yield(L,n)          lua_yieldk(L, (n), 0, NULL)


/*
** Warning-related functions
*/
SYMBOL_DECLARE(void, lua_setwarnf, lua_State *L, lua_WarnFunction f, void *ud)
SYMBOL_DECLARE(void, lua_warning, lua_State *L, const char *msg, int tocont)


/*
** garbage-collection function and options
*/

#define LUA_GCSTOP              0
#define LUA_GCRESTART           1
#define LUA_GCCOLLECT           2
#define LUA_GCCOUNT             3
#define LUA_GCCOUNTB            4
#define LUA_GCSTEP              5
#define LUA_GCSETPAUSE          6
#define LUA_GCSETSTEPMUL        7
#define LUA_GCISRUNNING         9
#define LUA_GCGEN               10
#define LUA_GCINC               11

SYMBOL_DECLARE_VARARG(int, lua_gc, lua_State *L, int what)


/*
** miscellaneous functions
*/

SYMBOL_DECLARE(int , lua_error, lua_State *L)

SYMBOL_DECLARE(int , lua_next, lua_State *L, int idx)

SYMBOL_DECLARE(void, lua_concat, lua_State *L, int n)
SYMBOL_DECLARE(void, lua_len, lua_State *L, int idx)

SYMBOL_DECLARE(size_t, lua_stringtonumber, lua_State *L, const char *s)

SYMBOL_DECLARE(lua_Alloc, lua_getallocf, lua_State *L, void **ud)
SYMBOL_DECLARE(void     , lua_setallocf, lua_State *L, lua_Alloc f, void *ud)

SYMBOL_DECLARE(void, lua_toclose, lua_State *L, int idx)
SYMBOL_DECLARE(void, lua_closeslot, lua_State *L, int idx)


/*
** {==============================================================
** some useful macros
** ===============================================================
*/

#define lua_getextraspace(L)    ((void *)((char *)(L) - LUA_EXTRASPACE))

#define lua_tonumber(L,i)       lua_tonumberx(L,(i),NULL)
#define lua_tointeger(L,i)      lua_tointegerx(L,(i),NULL)

#define lua_pop(L,n)            lua_settop(L, -(n)-1)

#define lua_newtable(L)         lua_createtable(L, 0, 0)

#define lua_register(L,n,f) (lua_pushcfunction(L, (f)), lua_setglobal(L, (n)))

#define lua_pushcfunction(L,f)  lua_pushcclosure(L, (f), 0)

#define lua_isfunction(L,n)     (lua_type(L, (n)) == LUA_TFUNCTION)
#define lua_istable(L,n)        (lua_type(L, (n)) == LUA_TTABLE)
#define lua_islightuserdata(L,n)        (lua_type(L, (n)) == LUA_TLIGHTUSERDATA)
#define lua_isnil(L,n)          (lua_type(L, (n)) == LUA_TNIL)
#define lua_isboolean(L,n)      (lua_type(L, (n)) == LUA_TBOOLEAN)
#define lua_isthread(L,n)       (lua_type(L, (n)) == LUA_TTHREAD)
#define lua_isnone(L,n)         (lua_type(L, (n)) == LUA_TNONE)
#define lua_isnoneornil(L, n)   (lua_type(L, (n)) <= 0)

#define lua_pushliteral(L, s)   lua_pushstring(L, "" s)

#define lua_pushglobaltable(L)  \
        ((void)lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS))

#define lua_tostring(L,i)       lua_tolstring(L, (i), NULL)


#define lua_insert(L,idx)       lua_rotate(L, (idx), 1)

#define lua_remove(L,idx)       (lua_rotate(L, (idx), -1), lua_pop(L, 1))

#define lua_replace(L,idx)      (lua_copy(L, -1, (idx)), lua_pop(L, 1))

/* }============================================================== */


/*
** {==============================================================
** compatibility macros
** ===============================================================
*/
#if defined(LUA_COMPAT_APIINTCASTS)

#define lua_pushunsigned(L,n)   lua_pushinteger(L, (lua_Integer)(n))
#define lua_tounsignedx(L,i,is) ((lua_Unsigned)lua_tointegerx(L,i,is))
#define lua_tounsigned(L,i)     lua_tounsignedx(L,(i),NULL)

#endif

#define lua_newuserdata(L,s)    lua_newuserdatauv(L,s,1)
#define lua_getuservalue(L,idx) lua_getiuservalue(L,idx,1)
#define lua_setuservalue(L,idx) lua_setiuservalue(L,idx,1)

#define LUA_NUMTAGS             LUA_NUMTYPES

/* }============================================================== */

/*
** {======================================================================
** Debug API
** =======================================================================
*/


/*
** Event codes
*/
#define LUA_HOOKCALL    0
#define LUA_HOOKRET     1
#define LUA_HOOKLINE    2
#define LUA_HOOKCOUNT   3
#define LUA_HOOKTAILCALL 4


/*
** Event masks
*/
#define LUA_MASKCALL    (1 << LUA_HOOKCALL)
#define LUA_MASKRET     (1 << LUA_HOOKRET)
#define LUA_MASKLINE    (1 << LUA_HOOKLINE)
#define LUA_MASKCOUNT   (1 << LUA_HOOKCOUNT)

typedef struct lua_Debug lua_Debug;  /* activation record */


/* Functions to be called by the debugger in specific events */
typedef void (*lua_Hook) (lua_State *L, lua_Debug *ar);


SYMBOL_DECLARE(int, lua_getstack, lua_State *L, int level, lua_Debug *ar)
SYMBOL_DECLARE(int, lua_getinfo, lua_State *L, const char *what, lua_Debug *ar)
SYMBOL_DECLARE(const char *, lua_getlocal, lua_State *L, const lua_Debug *ar, int n)
SYMBOL_DECLARE(const char *, lua_setlocal, lua_State *L, const lua_Debug *ar, int n)
SYMBOL_DECLARE(const char *, lua_getupvalue, lua_State *L, int funcindex, int n)
SYMBOL_DECLARE(const char *, lua_setupvalue, lua_State *L, int funcindex, int n)

SYMBOL_DECLARE(void *, lua_upvalueid, lua_State *L, int fidx, int n)
SYMBOL_DECLARE(void, lua_upvaluejoin, lua_State *L, int fidx1, int n1,
                                      int fidx2, int n2)

SYMBOL_DECLARE(void, lua_sethook, lua_State *L, lua_Hook func, int mask, int count)
SYMBOL_DECLARE(lua_Hook, lua_gethook, lua_State *L)
SYMBOL_DECLARE(int, lua_gethookmask, lua_State *L)
SYMBOL_DECLARE(int, lua_gethookcount, lua_State *L)

SYMBOL_DECLARE(int, lua_setcstacklimit, lua_State *L, unsigned int limit)

struct lua_Debug {
  int event;
  const char *name;     /* (n) */
  const char *namewhat; /* (n) 'global', 'local', 'field', 'method' */
  const char *what;     /* (S) 'Lua', 'C', 'main', 'tail' */
  const char *source;   /* (S) */
  size_t srclen;        /* (S) */
  int currentline;      /* (l) */
  int linedefined;      /* (S) */
  int lastlinedefined;  /* (S) */
  unsigned char nups;   /* (u) number of upvalues */
  unsigned char nparams;/* (u) number of parameters */
  char isvararg;        /* (u) */
  char istailcall;      /* (t) */
  unsigned short ftransfer;   /* (r) index of first value transferred */
  unsigned short ntransfer;   /* (r) number of transferred values */
  char short_src[LUA_IDSIZE]; /* (S) */
  /* private part */
  struct CallInfo *i_ci;  /* active function */
};

/* }====================================================================== */


#endif





/*
** $Id: lauxlib.h $
** Auxiliary functions for building Lua libraries
** See Copyright Notice in lua.h
*/


#ifndef lauxlib_h
#define lauxlib_h


#include <stddef.h>
#include <stdio.h>


/* global table */
#define LUA_GNAME       "_G"


typedef struct luaL_Buffer luaL_Buffer;


/* extra error code for 'luaL_loadfilex' */
#define LUA_ERRFILE     (LUA_ERRERR+1)


/* key, in the registry, for table of loaded modules */
#define LUA_LOADED_TABLE        "_LOADED"


/* key, in the registry, for table of preloaded loaders */
#define LUA_PRELOAD_TABLE       "_PRELOAD"


typedef struct luaL_Reg {
  const char *name;
  lua_CFunction func;
} luaL_Reg;


#define LUAL_NUMSIZES   (sizeof(lua_Integer)*16 + sizeof(lua_Number))

SYMBOL_DECLARE(void, luaL_checkversion_, lua_State *L, lua_Number ver, size_t sz)
#define luaL_checkversion(L)  \
          luaL_checkversion_(L, LUA_VERSION_NUM, LUAL_NUMSIZES)

SYMBOL_DECLARE(int, luaL_getmetafield, lua_State *L, int obj, const char *e)
SYMBOL_DECLARE(int, luaL_callmeta, lua_State *L, int obj, const char *e)
SYMBOL_DECLARE(const char *, luaL_tolstring, lua_State *L, int idx, size_t *len)
SYMBOL_DECLARE(int, luaL_argerror, lua_State *L, int arg, const char *extramsg)
SYMBOL_DECLARE(int, luaL_typeerror, lua_State *L, int arg, const char *tname)
SYMBOL_DECLARE(const char *, luaL_checklstring, lua_State *L, int arg,
                                                size_t *l)
SYMBOL_DECLARE(const char *, luaL_optlstring, lua_State *L, int arg,
                                              const char *def, size_t *l)
SYMBOL_DECLARE(lua_Number, luaL_checknumber, lua_State *L, int arg)
SYMBOL_DECLARE(lua_Number, luaL_optnumber, lua_State *L, int arg, lua_Number def)

SYMBOL_DECLARE(lua_Integer, luaL_checkinteger, lua_State *L, int arg)
SYMBOL_DECLARE(lua_Integer, luaL_optinteger, lua_State *L, int arg,
                                              lua_Integer def)

SYMBOL_DECLARE(void, luaL_checkstack, lua_State *L, int sz, const char *msg)
SYMBOL_DECLARE(void, luaL_checktype, lua_State *L, int arg, int t)
SYMBOL_DECLARE(void, luaL_checkany, lua_State *L, int arg)

SYMBOL_DECLARE(int  , luaL_newmetatable, lua_State *L, const char *tname)
SYMBOL_DECLARE(void , luaL_setmetatable, lua_State *L, const char *tname)
SYMBOL_DECLARE(void *, luaL_testudata, lua_State *L, int ud, const char *tname)
SYMBOL_DECLARE(void *, luaL_checkudata, lua_State *L, int ud, const char *tname)

SYMBOL_DECLARE(void, luaL_where, lua_State *L, int lvl)
SYMBOL_DECLARE_VARARG(int, luaL_error, lua_State *L, const char *fmt)

SYMBOL_DECLARE(int, luaL_checkoption, lua_State *L, int arg, const char *def,
                                      const char *const lst[])

SYMBOL_DECLARE(int, luaL_fileresult, lua_State *L, int stat, const char *fname)
SYMBOL_DECLARE(int, luaL_execresult, lua_State *L, int stat)


/* predefined references */
#define LUA_NOREF       (-2)
#define LUA_REFNIL      (-1)

SYMBOL_DECLARE(int, luaL_ref, lua_State *L, int t)
SYMBOL_DECLARE(void, luaL_unref, lua_State *L, int t, int ref)

SYMBOL_DECLARE(int, luaL_loadfilex, lua_State *L, const char *filename,
                                    const char *mode)

#define luaL_loadfile(L,f)      luaL_loadfilex(L,f,NULL)

SYMBOL_DECLARE(int, luaL_loadbufferx, lua_State *L, const char *buff, size_t sz,
                                      const char *name, const char *mode)
SYMBOL_DECLARE(int, luaL_loadstring, lua_State *L, const char *s)

SYMBOL_DECLARE(lua_State *, luaL_newstate, void)

SYMBOL_DECLARE(lua_Integer, luaL_len, lua_State *L, int idx)

SYMBOL_DECLARE(void, luaL_addgsub, luaL_Buffer *b, const char *s,
                                    const char *p, const char *r)
SYMBOL_DECLARE(const char *, luaL_gsub, lua_State *L, const char *s,
                                        const char *p, const char *r)

SYMBOL_DECLARE(void, luaL_setfuncs, lua_State *L, const luaL_Reg *l, int nup)

SYMBOL_DECLARE(int, luaL_getsubtable, lua_State *L, int idx, const char *fname)

SYMBOL_DECLARE(void, luaL_traceback, lua_State *L, lua_State *L1,
                                  const char *msg, int level)

SYMBOL_DECLARE(void, luaL_requiref, lua_State *L, const char *modname,
                                     lua_CFunction openf, int glb)

/*
** ===============================================================
** some useful macros
** ===============================================================
*/


#define luaL_newlibtable(L,l)   \
  lua_createtable(L, 0, sizeof(l)/sizeof((l)[0]) - 1)

#define luaL_newlib(L,l)  \
  (luaL_checkversion(L), luaL_newlibtable(L,l), luaL_setfuncs(L,l,0))

#define luaL_argcheck(L, cond,arg,extramsg)     \
        ((void)(luai_likely(cond) || luaL_argerror(L, (arg), (extramsg))))

#define luaL_argexpected(L,cond,arg,tname)      \
        ((void)(luai_likely(cond) || luaL_typeerror(L, (arg), (tname))))

#define luaL_checkstring(L,n)   (luaL_checklstring(L, (n), NULL))
#define luaL_optstring(L,n,d)   (luaL_optlstring(L, (n), (d), NULL))

#define luaL_typename(L,i)      lua_typename(L, lua_type(L,(i)))

#define luaL_dofile(L, fn) \
        (luaL_loadfile(L, fn) || lua_pcall(L, 0, LUA_MULTRET, 0))

#define luaL_dostring(L, s) \
        (luaL_loadstring(L, s) || lua_pcall(L, 0, LUA_MULTRET, 0))

#define luaL_getmetatable(L,n)  (lua_getfield(L, LUA_REGISTRYINDEX, (n)))

#define luaL_opt(L,f,n,d)       (lua_isnoneornil(L,(n)) ? (d) : f(L,(n)))

#define luaL_loadbuffer(L,s,sz,n)       luaL_loadbufferx(L,s,sz,n,NULL)


/*
** Perform arithmetic operations on lua_Integer values with wrap-around
** semantics, as the Lua core does.
*/
#define luaL_intop(op,v1,v2)  \
        ((lua_Integer)((lua_Unsigned)(v1) op (lua_Unsigned)(v2)))


/* push the value used to represent failure/error */
#define luaL_pushfail(L)        lua_pushnil(L)


/*
** Internal assertions for in-house debugging
*/
#if !defined(lua_assert)

#if defined LUAI_ASSERT
  #include <assert.h>
  #define lua_assert(c)         assert(c)
#else
  #define lua_assert(c)         ((void)0)
#endif

#endif



/*
** {======================================================
** Generic Buffer manipulation
** =======================================================
*/

struct luaL_Buffer {
  char *b;  /* buffer address */
  size_t size;  /* buffer size */
  size_t n;  /* number of characters in buffer */
  lua_State *L;
  union {
    LUAI_MAXALIGN;  /* ensure maximum alignment for buffer */
    char b[LUAL_BUFFERSIZE];  /* initial buffer */
  } init;
};


#define luaL_bufflen(bf)        ((bf)->n)
#define luaL_buffaddr(bf)       ((bf)->b)


#define luaL_addchar(B,c) \
  ((void)((B)->n < (B)->size || luaL_prepbuffsize((B), 1)), \
   ((B)->b[(B)->n++] = (c)))

#define luaL_addsize(B,s)       ((B)->n += (s))

#define luaL_buffsub(B,s)       ((B)->n -= (s))

SYMBOL_DECLARE(void, luaL_buffinit, lua_State *L, luaL_Buffer *B)
SYMBOL_DECLARE(char *, luaL_prepbuffsize, luaL_Buffer *B, size_t sz)
SYMBOL_DECLARE(void, luaL_addlstring, luaL_Buffer *B, const char *s, size_t l)
SYMBOL_DECLARE(void, luaL_addstring, luaL_Buffer *B, const char *s)
SYMBOL_DECLARE(void, luaL_addvalue, luaL_Buffer *B)
SYMBOL_DECLARE(void, luaL_pushresult, luaL_Buffer *B)
SYMBOL_DECLARE(void, luaL_pushresultsize, luaL_Buffer *B, size_t sz)
SYMBOL_DECLARE(char *, luaL_buffinitsize, lua_State *L, luaL_Buffer *B, size_t sz)

#define luaL_prepbuffer(B)      luaL_prepbuffsize(B, LUAL_BUFFERSIZE)

/* }====================================================== */



/*
** {======================================================
** File handles for IO library
** =======================================================
*/

/*
** A file handle is a userdata with metatable 'LUA_FILEHANDLE' and
** initial structure 'luaL_Stream' (it may contain other fields
** after that initial structure).
*/

#define LUA_FILEHANDLE          "FILE*"


typedef struct luaL_Stream {
  FILE *f;  /* stream (NULL for incompletely created streams) */
  lua_CFunction closef;  /* to close stream (NULL for closed streams) */
} luaL_Stream;

/* }====================================================== */

/*
** {==================================================================
** "Abstraction Layer" for basic report of messages and errors
** ===================================================================
*/

/* print a string */
#if !defined(lua_writestring)
#define lua_writestring(s,l)   fwrite((s), sizeof(char), (l), stdout)
#endif

/* print a newline and flush the output */
#if !defined(lua_writeline)
#define lua_writeline()        (lua_writestring("\n", 1), fflush(stdout))
#endif

/* print an error message */
#if !defined(lua_writestringerror)
#define lua_writestringerror(s,p) \
        (fprintf(stderr, (s), (p)), fflush(stderr))
#endif

/* }================================================================== */


/*
** {============================================================
** Compatibility with deprecated conversions
** =============================================================
*/
#if defined(LUA_COMPAT_APIINTCASTS)

#define luaL_checkunsigned(L,a) ((lua_Unsigned)luaL_checkinteger(L,a))
#define luaL_optunsigned(L,a,d) \
        ((lua_Unsigned)luaL_optinteger(L,a,(lua_Integer)(d)))

#define luaL_checkint(L,n)      ((int)luaL_checkinteger(L, (n)))
#define luaL_optint(L,n,d)      ((int)luaL_optinteger(L, (n), (d)))

#define luaL_checklong(L,n)     ((long)luaL_checkinteger(L, (n)))
#define luaL_optlong(L,n,d)     ((long)luaL_optinteger(L, (n), (d)))

#endif
/* }============================================================ */



#endif





/*
** $Id: lualib.h $
** Lua standard libraries
** See Copyright Notice in lua.h
*/


#ifndef lualib_h
#define lualib_h


/* version suffix for environment variable names */
#define LUA_VERSUFFIX          "_" LUA_VERSION_MAJOR "_" LUA_VERSION_MINOR


SYMBOL_DECLARE(int, luaopen_base, lua_State *L)

#define LUA_COLIBNAME   "coroutine"
SYMBOL_DECLARE(int, luaopen_coroutine, lua_State *L)

#define LUA_TABLIBNAME  "table"
SYMBOL_DECLARE(int, luaopen_table, lua_State *L)

#define LUA_IOLIBNAME   "io"
SYMBOL_DECLARE(int, luaopen_io, lua_State *L)

#define LUA_OSLIBNAME   "os"
SYMBOL_DECLARE(int, luaopen_os, lua_State *L)

#define LUA_STRLIBNAME  "string"
SYMBOL_DECLARE(int, luaopen_string, lua_State *L)

#define LUA_UTF8LIBNAME "utf8"
SYMBOL_DECLARE(int, luaopen_utf8, lua_State *L)

#define LUA_MATHLIBNAME "math"
SYMBOL_DECLARE(int, luaopen_math, lua_State *L)

#define LUA_DBLIBNAME   "debug"
SYMBOL_DECLARE(int, luaopen_debug, lua_State *L)

#define LUA_LOADLIBNAME "package"
SYMBOL_DECLARE(int, luaopen_package, lua_State *L)


/* open all previous libraries */
SYMBOL_DECLARE(void, luaL_openlibs, lua_State *L)


#endif





#ifdef LITE_XL_PLUGIN_ENTRYPOINT

SYMBOL_WRAP_DECL(lua_State *, lua_newstate, lua_Alloc f, void *ud) {
  return SYMBOL_WRAP_CALL(lua_newstate, f, ud);
}
SYMBOL_WRAP_DECL(void, lua_close, lua_State *L) {
  SYMBOL_WRAP_CALL(lua_close, L);
}
SYMBOL_WRAP_DECL(lua_State *, lua_newthread, lua_State *L) {
  return SYMBOL_WRAP_CALL(lua_newthread, L);
}
SYMBOL_WRAP_DECL(int, lua_resetthread, lua_State *L) {
  return SYMBOL_WRAP_CALL(lua_resetthread, L);
}

SYMBOL_WRAP_DECL(lua_CFunction, lua_atpanic, lua_State *L, lua_CFunction panicf) {
  return SYMBOL_WRAP_CALL(lua_atpanic, L, panicf);
}


SYMBOL_WRAP_DECL(lua_Number, lua_version, lua_State *L) {
  return SYMBOL_WRAP_CALL(lua_version, L);
}





SYMBOL_WRAP_DECL(int, lua_absindex, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_absindex, L, idx);
}
SYMBOL_WRAP_DECL(int, lua_gettop, lua_State *L) {
  return SYMBOL_WRAP_CALL(lua_gettop, L);
}
SYMBOL_WRAP_DECL(void, lua_settop, lua_State *L, int idx) {
  SYMBOL_WRAP_CALL(lua_settop, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_pushvalue, lua_State *L, int idx) {
  SYMBOL_WRAP_CALL(lua_pushvalue, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_rotate, lua_State *L, int idx, int n) {
  SYMBOL_WRAP_CALL(lua_rotate, L, idx, n);
}
SYMBOL_WRAP_DECL(void, lua_copy, lua_State *L, int fromidx, int toidx) {
  SYMBOL_WRAP_CALL(lua_copy, L, fromidx, toidx);
}
SYMBOL_WRAP_DECL(int, lua_checkstack, lua_State *L, int sz) {
  return SYMBOL_WRAP_CALL(lua_checkstack, L, sz);
}
SYMBOL_WRAP_DECL(void, lua_xmove, lua_State *from, lua_State *to, int n) {
  SYMBOL_WRAP_CALL(lua_xmove, from, to, n);
}






SYMBOL_WRAP_DECL(int, lua_isnumber, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_isnumber, L, idx);
}
SYMBOL_WRAP_DECL(int, lua_isstring, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_isstring, L, idx);
}
SYMBOL_WRAP_DECL(int, lua_iscfunction, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_iscfunction, L, idx);
}
SYMBOL_WRAP_DECL(int, lua_isinteger, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_isinteger, L, idx);
}
SYMBOL_WRAP_DECL(int, lua_isuserdata, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_isuserdata, L, idx);
}
SYMBOL_WRAP_DECL(int, lua_type, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_type, L, idx);
}
SYMBOL_WRAP_DECL(const char *, lua_typename, lua_State *L, int tp) {
  return SYMBOL_WRAP_CALL(lua_typename, L, tp);
}

SYMBOL_WRAP_DECL(lua_Number, lua_tonumberx, lua_State *L, int idx, int *isnum) {
  return SYMBOL_WRAP_CALL(lua_tonumberx, L, idx, isnum);
}
SYMBOL_WRAP_DECL(lua_Integer, lua_tointegerx, lua_State *L, int idx, int *isnum) {
  return SYMBOL_WRAP_CALL(lua_tointegerx, L, idx, isnum);
}
SYMBOL_WRAP_DECL(int, lua_toboolean, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_toboolean, L, idx);
}
SYMBOL_WRAP_DECL(const char *, lua_tolstring, lua_State *L, int idx, size_t *len) {
  return SYMBOL_WRAP_CALL(lua_tolstring, L, idx, len);
}
SYMBOL_WRAP_DECL(lua_Unsigned, lua_rawlen, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_rawlen, L, idx);
}
SYMBOL_WRAP_DECL(lua_CFunction, lua_tocfunction, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_tocfunction, L, idx);
}
SYMBOL_WRAP_DECL(void *, lua_touserdata, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_touserdata, L, idx);
}
SYMBOL_WRAP_DECL(lua_State *, lua_tothread, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_tothread, L, idx);
}
SYMBOL_WRAP_DECL(const void *, lua_topointer, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_topointer, L, idx);
}






SYMBOL_WRAP_DECL(void, lua_arith, lua_State *L, int op) {
  SYMBOL_WRAP_CALL(lua_arith, L, op);
}

SYMBOL_WRAP_DECL(int, lua_rawequal, lua_State *L, int idx1, int idx2) {
  return SYMBOL_WRAP_CALL(lua_rawequal, L, idx1, idx2);
}
SYMBOL_WRAP_DECL(int, lua_compare, lua_State *L, int idx1, int idx2, int op) {
  return SYMBOL_WRAP_CALL(lua_compare, L, idx1, idx2, op);
}

SYMBOL_WRAP_DECL(void, lua_pushnil, lua_State *L) {
  SYMBOL_WRAP_CALL(lua_pushnil, L);
}
SYMBOL_WRAP_DECL(void, lua_pushnumber, lua_State *L, lua_Number n) {
  SYMBOL_WRAP_CALL(lua_pushnumber, L, n);
}
SYMBOL_WRAP_DECL(void, lua_pushinteger, lua_State *L, lua_Integer n) {
  SYMBOL_WRAP_CALL(lua_pushinteger, L, n);
}
SYMBOL_WRAP_DECL(const char *, lua_pushlstring, lua_State *L, const char *s, size_t l) {
  return SYMBOL_WRAP_CALL(lua_pushlstring, L, s, l);
}
SYMBOL_WRAP_DECL(const char *, lua_pushstring, lua_State *L, const char *s) {
  return SYMBOL_WRAP_CALL(lua_pushstring, L, s);
}
SYMBOL_WRAP_DECL(const char *, lua_pushvfstring, lua_State *L, const char *fmt, va_list argp) {
  return SYMBOL_WRAP_CALL(lua_pushvfstring, L, fmt, argp);
}
SYMBOL_WRAP_DECL(const char *, lua_pushfstring, lua_State *L, const char *fmt, ...) {
  const char *res;
  va_list argp;
  va_start(argp, fmt);
  res = lua_pushvfstring(L, fmt, argp);
  va_end(argp);
  return res;
}
SYMBOL_WRAP_DECL(void, lua_pushcclosure, lua_State *L, lua_CFunction fn, int n) {
  SYMBOL_WRAP_CALL(lua_pushcclosure, L, fn, n);
}
SYMBOL_WRAP_DECL(void, lua_pushboolean, lua_State *L, int b) {
  SYMBOL_WRAP_CALL(lua_pushboolean, L, b);
}
SYMBOL_WRAP_DECL(void, lua_pushlightuserdata, lua_State *L, void *p) {
  SYMBOL_WRAP_CALL(lua_pushlightuserdata, L, p);
}
SYMBOL_WRAP_DECL(int, lua_pushthread, lua_State *L) {
  return SYMBOL_WRAP_CALL(lua_pushthread, L);
}





SYMBOL_WRAP_DECL(int, lua_getglobal, lua_State *L, const char *var) {
  return SYMBOL_WRAP_CALL(lua_getglobal, L, var);
}
SYMBOL_WRAP_DECL(int, lua_gettable, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_gettable, L, idx);
}
SYMBOL_WRAP_DECL(int, lua_getfield, lua_State *L, int idx, const char *k) {
  return SYMBOL_WRAP_CALL(lua_getfield, L, idx, k);
}
SYMBOL_WRAP_DECL(int , lua_geti, lua_State *L, int idx, lua_Integer n) {
  return SYMBOL_WRAP_CALL(lua_geti, L, idx, n);
}
SYMBOL_WRAP_DECL(int, lua_rawget, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_rawget, L, idx);
}
SYMBOL_WRAP_DECL(int, lua_rawgeti, lua_State *L, int idx, lua_Integer n) {
  return SYMBOL_WRAP_CALL(lua_rawgeti, L, idx, n);
}
SYMBOL_WRAP_DECL(int, lua_rawgetp, lua_State *L, int idx, const void *p) {
  return SYMBOL_WRAP_CALL(lua_rawgetp, L, idx, p);
}
SYMBOL_WRAP_DECL(void, lua_createtable, lua_State *L, int narr, int nrec) {
  SYMBOL_WRAP_CALL(lua_createtable, L, narr, nrec);
}
SYMBOL_WRAP_DECL(void *, lua_newuserdatauv, lua_State *L, size_t sz, int nuvalue) {
  return SYMBOL_WRAP_CALL(lua_newuserdatauv, L, sz, nuvalue);
}
SYMBOL_WRAP_DECL(int, lua_getmetatable, lua_State *L, int objindex) {
  return SYMBOL_WRAP_CALL(lua_getmetatable, L, objindex);
}
SYMBOL_WRAP_DECL(int, lua_getiuservalue, lua_State *L, int idx, int n) {
  return SYMBOL_WRAP_CALL(lua_getiuservalue, L, idx, n);
}

SYMBOL_WRAP_DECL(void, lua_setglobal, lua_State *L, const char *var) {
  SYMBOL_WRAP_CALL(lua_setglobal, L, var);
}
SYMBOL_WRAP_DECL(void, lua_settable, lua_State *L, int idx) {
  SYMBOL_WRAP_CALL(lua_settable, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_setfield, lua_State *L, int idx, const char *k) {
  SYMBOL_WRAP_CALL(lua_setfield, L, idx, k);
}
SYMBOL_WRAP_DECL(void, lua_seti, lua_State *L, int idx, lua_Integer n) {
  SYMBOL_WRAP_CALL(lua_seti, L, idx, n);
}
SYMBOL_WRAP_DECL(void, lua_rawset, lua_State *L, int idx) {
  SYMBOL_WRAP_CALL(lua_rawset, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_rawseti, lua_State *L, int idx, lua_Integer n) {
  SYMBOL_WRAP_CALL(lua_rawseti, L, idx, n);
}
SYMBOL_WRAP_DECL(void, lua_rawsetp, lua_State *L, int idx, const void *p) {
  SYMBOL_WRAP_CALL(lua_rawsetp, L, idx, p);
}
SYMBOL_WRAP_DECL(int, lua_setmetatable, lua_State *L, int objindex) {
  return SYMBOL_WRAP_CALL(lua_setmetatable, L, objindex);
}
SYMBOL_WRAP_DECL(int, lua_setiuservalue, lua_State *L, int idx, int n) {
  return SYMBOL_WRAP_CALL(lua_setiuservalue, L, idx, n);
}





SYMBOL_WRAP_DECL(void, lua_callk, lua_State *L, int nargs, int nresults, lua_KContext ctx, lua_KFunction k) {
  SYMBOL_WRAP_CALL(lua_callk, L, nargs, nresults, ctx, k);
}
SYMBOL_WRAP_DECL(int, lua_pcallk, lua_State *L, int nargs, int nresults, int errfunc, lua_KContext ctx, lua_KFunction k) {
  return SYMBOL_WRAP_CALL(lua_pcallk, L, nargs, nresults, errfunc, ctx, k);
}
SYMBOL_WRAP_DECL(int, lua_load, lua_State *L, lua_Reader reader, void *dt, const char *chunkname, const char *mode) {
  return SYMBOL_WRAP_CALL(lua_load, L, reader, dt, chunkname, mode);
}
SYMBOL_WRAP_DECL(int, lua_dump, lua_State *L, lua_Writer writer, void *data, int strip) {
  return SYMBOL_WRAP_CALL(lua_dump, L, writer, data, strip);
}





SYMBOL_WRAP_DECL(int, lua_yieldk, lua_State *L, int nresults, lua_KContext ctx, lua_KFunction k) {
  return SYMBOL_WRAP_CALL(lua_yieldk, L, nresults, ctx, k);
}
SYMBOL_WRAP_DECL(int, lua_resume, lua_State *L, lua_State *from, int narg, int *nres) {
  return SYMBOL_WRAP_CALL(lua_resume, L, from, narg, nres);
}
SYMBOL_WRAP_DECL(int, lua_status, lua_State *L) {
  return SYMBOL_WRAP_CALL(lua_status, L);
}
SYMBOL_WRAP_DECL(int, lua_isyieldable, lua_State *L) {
  return SYMBOL_WRAP_CALL(lua_isyieldable, L);
}





SYMBOL_WRAP_DECL(void, lua_setwarnf, lua_State *L, lua_WarnFunction f, void *ud) {
  SYMBOL_WRAP_CALL(lua_setwarnf, L, f, ud);
}
SYMBOL_WRAP_DECL(void, lua_warning, lua_State *L, const char *msg, int tocont) {
  SYMBOL_WRAP_CALL(lua_warning, L, msg, tocont);
}






SYMBOL_WRAP_DECL(int, lua_gc, lua_State *L, int what, ...) {
  /* there are no straightforward ways of passing data. */
  int r;
  va_list ap;
  va_start(ap, what);
  if (what == LUA_GCSTEP) {
    int stepsize = va_arg(ap, int);
    r = __lua_gc(L, what, stepsize);
  } else if (what == LUA_GCINC) {
    int pause = va_arg(ap, int);
    int stepmul = va_arg(ap, int);
    int stepsize = va_arg(ap, int);
    r = __lua_gc(L, what, pause, stepmul, stepsize);
  } else if (what == LUA_GCGEN) {
    int minormul = va_arg(ap, int);
    int majormul = va_arg(ap, int);
    r = __lua_gc(L, what, minormul, majormul);
  } else {
    r = __lua_gc(L, what);
  }
  return r;
}






SYMBOL_WRAP_DECL(int, lua_error, lua_State *L) {
  return SYMBOL_WRAP_CALL(lua_error, L);
}

SYMBOL_WRAP_DECL(int, lua_next, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(lua_next, L, idx);
}

SYMBOL_WRAP_DECL(void, lua_concat, lua_State *L, int n) {
  SYMBOL_WRAP_CALL(lua_concat, L, n);
}
SYMBOL_WRAP_DECL(void, lua_len, lua_State *L, int idx) {
  SYMBOL_WRAP_CALL(lua_len, L, idx);
}

SYMBOL_WRAP_DECL(size_t, lua_stringtonumber, lua_State *L, const char *s) {
  return SYMBOL_WRAP_CALL(lua_stringtonumber, L, s);
}

SYMBOL_WRAP_DECL(lua_Alloc, lua_getallocf, lua_State *L, void **ud) {
  return SYMBOL_WRAP_CALL(lua_getallocf, L, ud);
}
SYMBOL_WRAP_DECL(void, lua_setallocf, lua_State *L, lua_Alloc f, void *ud) {
  SYMBOL_WRAP_CALL(lua_setallocf, L, f, ud);
}

SYMBOL_WRAP_DECL(void, lua_toclose, lua_State *L, int idx) {
  SYMBOL_WRAP_CALL(lua_toclose, L, idx);
}
SYMBOL_WRAP_DECL(void, lua_closeslot, lua_State *L, int idx) {
  SYMBOL_WRAP_CALL(lua_closeslot, L, idx);
}






SYMBOL_WRAP_DECL(int, lua_getstack, lua_State *L, int level, lua_Debug *ar) {
  return SYMBOL_WRAP_CALL(lua_getstack, L, level, ar);
}
SYMBOL_WRAP_DECL(int, lua_getinfo, lua_State *L, const char *what, lua_Debug *ar) {
  return SYMBOL_WRAP_CALL(lua_getinfo, L, what, ar);
}
SYMBOL_WRAP_DECL(const char *, lua_getlocal, lua_State *L, const lua_Debug *ar, int n) {
  return SYMBOL_WRAP_CALL(lua_getlocal, L, ar, n);
}
SYMBOL_WRAP_DECL(const char *, lua_setlocal, lua_State *L, const lua_Debug *ar, int n) {
  return SYMBOL_WRAP_CALL(lua_setlocal, L, ar, n);
}
SYMBOL_WRAP_DECL(const char *, lua_getupvalue, lua_State *L, int funcindex, int n) {
  return SYMBOL_WRAP_CALL(lua_getupvalue, L, funcindex, n);
}
SYMBOL_WRAP_DECL(const char *, lua_setupvalue, lua_State *L, int funcindex, int n) {
  return SYMBOL_WRAP_CALL(lua_setupvalue, L, funcindex, n);
}

SYMBOL_WRAP_DECL(void *, lua_upvalueid, lua_State *L, int fidx, int n) {
  return SYMBOL_WRAP_CALL(lua_upvalueid, L, fidx, n);
}
SYMBOL_WRAP_DECL(void, lua_upvaluejoin, lua_State *L, int fidx1, int n1, int fidx2, int n2) {
  SYMBOL_WRAP_CALL(lua_upvaluejoin, L, fidx1, n1, fidx2, n2);
}

SYMBOL_WRAP_DECL(void, lua_sethook, lua_State *L, lua_Hook func, int mask, int count) {
  SYMBOL_WRAP_CALL(lua_sethook, L, func, mask, count);
}
SYMBOL_WRAP_DECL(lua_Hook, lua_gethook, lua_State *L) {
  return SYMBOL_WRAP_CALL(lua_gethook, L);
}
SYMBOL_WRAP_DECL(int, lua_gethookmask, lua_State *L) {
  return SYMBOL_WRAP_CALL(lua_gethookmask, L);
}
SYMBOL_WRAP_DECL(int, lua_gethookcount, lua_State *L) {
  return SYMBOL_WRAP_CALL(lua_gethookcount, L);
}

SYMBOL_WRAP_DECL(int, lua_setcstacklimit, lua_State *L, unsigned int limit) {
  return SYMBOL_WRAP_CALL(lua_setcstacklimit, L, limit);
}






SYMBOL_WRAP_DECL(void, luaL_checkversion_, lua_State *L, lua_Number ver, size_t sz) {
  SYMBOL_WRAP_CALL(luaL_checkversion_, L, ver, sz);
}
SYMBOL_WRAP_DECL(int, luaL_getmetafield, lua_State *L, int obj, const char *e) {
  return SYMBOL_WRAP_CALL(luaL_getmetafield, L, obj, e);
}
SYMBOL_WRAP_DECL(int, luaL_callmeta, lua_State *L, int obj, const char *e) {
  return SYMBOL_WRAP_CALL(luaL_callmeta, L, obj, e);
}
SYMBOL_WRAP_DECL(const char *, luaL_tolstring, lua_State *L, int idx, size_t *len) {
  return SYMBOL_WRAP_CALL(luaL_tolstring, L, idx, len);
}
SYMBOL_WRAP_DECL(int, luaL_argerror, lua_State *L, int numarg, const char *extramsg) {
  return SYMBOL_WRAP_CALL(luaL_argerror, L, numarg, extramsg);
}
SYMBOL_WRAP_DECL(int, luaL_typeerror, lua_State *L, int arg, const char *tname) {
  return SYMBOL_WRAP_CALL(luaL_typeerror, L, arg, tname);
}
SYMBOL_WRAP_DECL(const char *, luaL_checklstring, lua_State *L, int numArg, size_t *l) {
  return SYMBOL_WRAP_CALL(luaL_checklstring, L, numArg, l);
}
SYMBOL_WRAP_DECL(const char *, luaL_optlstring, lua_State *L, int numArg, const char *def, size_t *l) {
  return SYMBOL_WRAP_CALL(luaL_optlstring, L, numArg, def, l);
}
SYMBOL_WRAP_DECL(lua_Number, luaL_checknumber, lua_State *L, int numArg) {
  return SYMBOL_WRAP_CALL(luaL_checknumber, L, numArg);
}
SYMBOL_WRAP_DECL(lua_Number, luaL_optnumber, lua_State *L, int nArg, lua_Number def) {
  return SYMBOL_WRAP_CALL(luaL_optnumber, L, nArg, def);
}

SYMBOL_WRAP_DECL(lua_Integer, luaL_checkinteger, lua_State *L, int numArg) {
  return SYMBOL_WRAP_CALL(luaL_checkinteger, L, numArg);
}
SYMBOL_WRAP_DECL(lua_Integer, luaL_optinteger, lua_State *L, int nArg, lua_Integer def) {
  return SYMBOL_WRAP_CALL(luaL_optinteger, L, nArg, def);
}

SYMBOL_WRAP_DECL(void, luaL_checkstack, lua_State *L, int sz, const char *msg) {
  SYMBOL_WRAP_CALL(luaL_checkstack, L, sz, msg);
}
SYMBOL_WRAP_DECL(void, luaL_checktype, lua_State *L, int narg, int t) {
  SYMBOL_WRAP_CALL(luaL_checktype, L, narg, t);
}
SYMBOL_WRAP_DECL(void, luaL_checkany, lua_State *L, int narg) {
  SYMBOL_WRAP_CALL(luaL_checkany, L, narg);
}
SYMBOL_WRAP_DECL(int, luaL_newmetatable, lua_State *L, const char *tname) {
  return SYMBOL_WRAP_CALL(luaL_newmetatable, L, tname);
}
SYMBOL_WRAP_DECL(void, luaL_setmetatable, lua_State *L, const char *tname) {
  SYMBOL_WRAP_CALL(luaL_setmetatable, L, tname);
}
SYMBOL_WRAP_DECL(void *, luaL_testudata, lua_State *L, int ud, const char *tname) {
  return SYMBOL_WRAP_CALL(luaL_testudata, L, ud, tname);
}
SYMBOL_WRAP_DECL(void *, luaL_checkudata, lua_State *L, int ud, const char *tname) {
  return SYMBOL_WRAP_CALL(luaL_checkudata, L, ud, tname);
}

SYMBOL_WRAP_DECL(void, luaL_where, lua_State *L, int lvl) {
  SYMBOL_WRAP_CALL(luaL_where, L, lvl);
}
SYMBOL_WRAP_DECL(int, luaL_error, lua_State *L, const char *fmt, ...) {
  va_list argp;
  va_start(argp, fmt);
  luaL_where(L, 1);
  lua_pushvfstring(L, fmt, argp);
  va_end(argp);
  lua_concat(L, 2);
  return lua_error(L);
}

SYMBOL_WRAP_DECL(int, luaL_checkoption, lua_State *L, int narg, const char *def, const char *const lst[]) {
  return SYMBOL_WRAP_CALL(luaL_checkoption, L, narg, def, lst);
}

SYMBOL_WRAP_DECL(int, luaL_fileresult, lua_State *L, int stat, const char *fname) {
  return SYMBOL_WRAP_CALL(luaL_fileresult, L, stat, fname);
}
SYMBOL_WRAP_DECL(int, luaL_execresult, lua_State *L, int stat) {
  return SYMBOL_WRAP_CALL(luaL_execresult, L, stat);
}






SYMBOL_WRAP_DECL(int, luaL_ref, lua_State *L, int t) {
  return SYMBOL_WRAP_CALL(luaL_ref, L, t);
}
SYMBOL_WRAP_DECL(void, luaL_unref, lua_State *L, int t, int ref) {
  SYMBOL_WRAP_CALL(luaL_unref, L, t, ref);
}

SYMBOL_WRAP_DECL(int, luaL_loadfilex, lua_State *L, const char *filename, const char *mode) {
  return SYMBOL_WRAP_CALL(luaL_loadfilex, L, filename, mode);
}

SYMBOL_WRAP_DECL(int, luaL_loadbufferx, lua_State *L, const char *buff, size_t sz, const char *name, const char *mode) {
  return SYMBOL_WRAP_CALL(luaL_loadbufferx, L, buff, sz, name, mode);
}

SYMBOL_WRAP_DECL(int, luaL_loadstring, lua_State *L, const char *s) {
  return SYMBOL_WRAP_CALL(luaL_loadstring, L, s);
}

SYMBOL_WRAP_DECL(lua_State *, luaL_newstate, void) {
 return __luaL_newstate();
}
SYMBOL_WRAP_DECL(lua_Integer, luaL_len, lua_State *L, int idx) {
  return SYMBOL_WRAP_CALL(luaL_len, L, idx);
}

SYMBOL_WRAP_DECL(void, luaL_addgsub, luaL_Buffer *b, const char *s,
                                      const char *p, const char *r) {
  SYMBOL_WRAP_CALL(luaL_addgsub, b, s, p, r);
}
SYMBOL_WRAP_DECL(const char *, luaL_gsub, lua_State *L, const char *s, const char *p, const char *r) {
  return SYMBOL_WRAP_CALL(luaL_gsub, L, s, p, r);
}

SYMBOL_WRAP_DECL(void, luaL_setfuncs, lua_State *L, const luaL_Reg *l, int nup) {
  SYMBOL_WRAP_CALL(luaL_setfuncs, L, l, nup);
}

SYMBOL_WRAP_DECL(int, luaL_getsubtable, lua_State *L, int idx, const char *fname) {
  return SYMBOL_WRAP_CALL(luaL_getsubtable, L, idx, fname);
}

SYMBOL_WRAP_DECL(void, luaL_traceback, lua_State *L, lua_State *L1, const char *msg, int level) {
  SYMBOL_WRAP_CALL(luaL_traceback, L, L1, msg, level);
}

SYMBOL_WRAP_DECL(void, luaL_requiref, lua_State *L, const char *modname, lua_CFunction openf, int glb) {
  SYMBOL_WRAP_CALL(luaL_requiref, L, modname, openf, glb);
}






SYMBOL_WRAP_DECL(void, luaL_buffinit, lua_State *L, luaL_Buffer *B) {
  SYMBOL_WRAP_CALL(luaL_buffinit, L, B);
}
SYMBOL_WRAP_DECL(char *, luaL_prepbuffsize, luaL_Buffer *B, size_t sz) {
  return SYMBOL_WRAP_CALL(luaL_prepbuffsize, B, sz);
}
SYMBOL_WRAP_DECL(void, luaL_addlstring, luaL_Buffer *B, const char *s, size_t l) {
  SYMBOL_WRAP_CALL(luaL_addlstring, B, s, l);
}
SYMBOL_WRAP_DECL(void, luaL_addstring, luaL_Buffer *B, const char *s) {
  SYMBOL_WRAP_CALL(luaL_addstring, B, s);
}
SYMBOL_WRAP_DECL(void, luaL_addvalue, luaL_Buffer *B) {
  SYMBOL_WRAP_CALL(luaL_addvalue, B);
}
SYMBOL_WRAP_DECL(void, luaL_pushresult, luaL_Buffer *B) {
  SYMBOL_WRAP_CALL(luaL_pushresult, B);
}
SYMBOL_WRAP_DECL(void, luaL_pushresultsize, luaL_Buffer *B, size_t sz) {
  SYMBOL_WRAP_CALL(luaL_pushresultsize, B, sz);
}
SYMBOL_WRAP_DECL(char *, luaL_buffinitsize, lua_State *L, luaL_Buffer *B, size_t sz) {
  return SYMBOL_WRAP_CALL(luaL_buffinitsize, L, B, sz);
}

SYMBOL_WRAP_DECL(int, luaopen_base, lua_State *L) {
  return SYMBOL_WRAP_CALL(luaopen_base, L);
}

SYMBOL_WRAP_DECL(int, luaopen_coroutine, lua_State *L) {
  return SYMBOL_WRAP_CALL(luaopen_coroutine, L);
}

SYMBOL_WRAP_DECL(int, luaopen_table, lua_State *L) {
  return SYMBOL_WRAP_CALL(luaopen_table, L);
}

SYMBOL_WRAP_DECL(int, luaopen_io, lua_State *L) {
  return SYMBOL_WRAP_CALL(luaopen_io, L);
}

SYMBOL_WRAP_DECL(int, luaopen_os, lua_State *L) {
  return SYMBOL_WRAP_CALL(luaopen_os, L);
}

SYMBOL_WRAP_DECL(int, luaopen_string, lua_State *L) {
  return SYMBOL_WRAP_CALL(luaopen_string, L);
}

SYMBOL_WRAP_DECL(int, luaopen_utf8, lua_State *L) {
  return SYMBOL_WRAP_CALL(luaopen_utf8, L);
}

SYMBOL_WRAP_DECL(int, luaopen_math, lua_State *L) {
  return SYMBOL_WRAP_CALL(luaopen_math, L);
}

SYMBOL_WRAP_DECL(int, luaopen_debug, lua_State *L) {
  return SYMBOL_WRAP_CALL(luaopen_debug, L);
}

SYMBOL_WRAP_DECL(int, luaopen_package, lua_State *L) {
  return SYMBOL_WRAP_CALL(luaopen_package, L);
}

SYMBOL_WRAP_DECL(void, luaL_openlibs, lua_State *L) {
  SYMBOL_WRAP_CALL(luaL_openlibs, L);
}






#define IMPORT_SYMBOL(name, ret, ...) \
  __##name = (\
    (*(void **) (&__##name) = symbol(#name)), \
    __##name == NULL ? ((ret (*) (__VA_ARGS__)) &__lite_xl_fallback_##name) : __##name\
  )

void lite_xl_plugin_init(void *XL) {
  void* (*symbol)(const char *);
  *(void **) (&symbol) = XL;
  IMPORT_SYMBOL(lua_newstate, lua_State *, lua_Alloc f, void *ud);
  IMPORT_SYMBOL(lua_close, void, lua_State *L);
  IMPORT_SYMBOL(lua_newthread, lua_State *, lua_State *L);
  IMPORT_SYMBOL(lua_resetthread, int, lua_State *L);
  IMPORT_SYMBOL(lua_atpanic, lua_CFunction, lua_State *L, lua_CFunction panicf);
  IMPORT_SYMBOL(lua_version, lua_Number, lua_State *L);
  IMPORT_SYMBOL(lua_absindex, int, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_gettop, int, lua_State *L);
  IMPORT_SYMBOL(lua_settop, void, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_pushvalue, void, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_rotate, void, lua_State *L, int idx, int n);
  IMPORT_SYMBOL(lua_copy, void, lua_State *L, int fromidx, int toidx);
  IMPORT_SYMBOL(lua_checkstack, int, lua_State *L, int sz);
  IMPORT_SYMBOL(lua_xmove, void, lua_State *from, lua_State *to, int n);
  IMPORT_SYMBOL(lua_isnumber, int, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_isstring, int, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_iscfunction, int, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_isinteger, int, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_isuserdata, int, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_type, int, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_typename, const char *, lua_State *L, int tp);
  IMPORT_SYMBOL(lua_tonumberx, lua_Number, lua_State *L, int idx, int *isnum);
  IMPORT_SYMBOL(lua_tointegerx, lua_Integer, lua_State *L, int idx, int *isnum);
  IMPORT_SYMBOL(lua_toboolean, int, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_tolstring, const char *, lua_State *L, int idx, size_t *len);
  IMPORT_SYMBOL(lua_rawlen, lua_Unsigned, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_tocfunction, lua_CFunction, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_touserdata, void *, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_tothread, lua_State *, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_topointer, const void *, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_arith, void, lua_State *L, int op);
  IMPORT_SYMBOL(lua_rawequal, int, lua_State *L, int idx1, int idx2);
  IMPORT_SYMBOL(lua_compare, int, lua_State *L, int idx1, int idx2, int op);
  IMPORT_SYMBOL(lua_pushnil, void, lua_State *L);
  IMPORT_SYMBOL(lua_pushnumber, void, lua_State *L, lua_Number n);
  IMPORT_SYMBOL(lua_pushinteger, void, lua_State *L, lua_Integer n);
  IMPORT_SYMBOL(lua_pushlstring, const char *, lua_State *L, const char *s, size_t l);
  IMPORT_SYMBOL(lua_pushstring, const char *, lua_State *L, const char *s);
  IMPORT_SYMBOL(lua_pushvfstring, const char *, lua_State *L, const char *fmt, va_list argp);
  IMPORT_SYMBOL(lua_pushfstring, const char *, lua_State *L, const char *fmt, ...);
  IMPORT_SYMBOL(lua_pushcclosure, void, lua_State *L, lua_CFunction fn, int n);
  IMPORT_SYMBOL(lua_pushboolean, void, lua_State *L, int b);
  IMPORT_SYMBOL(lua_pushlightuserdata, void, lua_State *L, void *p);
  IMPORT_SYMBOL(lua_pushthread, int, lua_State *L);
  IMPORT_SYMBOL(lua_getglobal, int, lua_State *L, const char *var);
  IMPORT_SYMBOL(lua_gettable, int, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_getfield, int, lua_State *L, int idx, const char *k);
  IMPORT_SYMBOL(lua_geti, int, lua_State *L, int idx, lua_Integer n);
  IMPORT_SYMBOL(lua_rawget, int, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_rawgeti, int, lua_State *L, int idx, lua_Integer n);
  IMPORT_SYMBOL(lua_rawgetp, int, lua_State *L, int idx, const void *p);
  IMPORT_SYMBOL(lua_createtable, void, lua_State *L, int narr, int nrec);
  IMPORT_SYMBOL(lua_newuserdatauv, void *, lua_State *L, size_t sz, int nuvalue);
  IMPORT_SYMBOL(lua_getmetatable, int, lua_State *L, int objindex);
  IMPORT_SYMBOL(lua_getiuservalue, int, lua_State *L, int idx, int n);
  IMPORT_SYMBOL(lua_setglobal, void, lua_State *L, const char *var);
  IMPORT_SYMBOL(lua_settable, void, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_setfield, void, lua_State *L, int idx, const char *k);
  IMPORT_SYMBOL(lua_seti, void, lua_State *L, int idx, lua_Integer n);
  IMPORT_SYMBOL(lua_rawset, void, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_rawseti, void, lua_State *L, int idx, lua_Integer n);
  IMPORT_SYMBOL(lua_rawsetp, void, lua_State *L, int idx, const void *p);
  IMPORT_SYMBOL(lua_setmetatable, int, lua_State *L, int objindex);
  IMPORT_SYMBOL(lua_setiuservalue, int, lua_State *L, int idx, int n);
  IMPORT_SYMBOL(lua_callk, void, lua_State *L, int nargs, int nresults, lua_KContext ctx, lua_KFunction k);
  IMPORT_SYMBOL(lua_pcallk, int, lua_State *L, int nargs, int nresults, int errfunc, lua_KContext ctx, lua_KFunction k);
  IMPORT_SYMBOL(lua_load, int, lua_State *L, lua_Reader reader, void *dt, const char *chunkname, const char *mode);
  IMPORT_SYMBOL(lua_dump, int, lua_State *L, lua_Writer writer, void *data, int strip);
  IMPORT_SYMBOL(lua_yieldk, int, lua_State *L, int nresults, lua_KContext ctx, lua_KFunction k);
  IMPORT_SYMBOL(lua_resume, int, lua_State *L, lua_State *from, int narg, int *nres);
  IMPORT_SYMBOL(lua_status, int, lua_State *L);
  IMPORT_SYMBOL(lua_isyieldable, int, lua_State *L);
  IMPORT_SYMBOL(lua_setwarnf, void, lua_State *L, lua_WarnFunction f, void *ud);
  IMPORT_SYMBOL(lua_warning, void, lua_State *L, const char *msg, int tocont);
  IMPORT_SYMBOL(lua_gc, int, lua_State *L, int what, ...);
  IMPORT_SYMBOL(lua_error, int, lua_State *L);
  IMPORT_SYMBOL(lua_next, int, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_concat, void, lua_State *L, int n);
  IMPORT_SYMBOL(lua_len, void, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_stringtonumber, size_t, lua_State *L, const char *s);
  IMPORT_SYMBOL(lua_getallocf, lua_Alloc, lua_State *L, void **ud);
  IMPORT_SYMBOL(lua_setallocf, void, lua_State *L, lua_Alloc f, void *ud);
  IMPORT_SYMBOL(lua_toclose, void, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_closeslot, void, lua_State *L, int idx);
  IMPORT_SYMBOL(lua_getstack, int, lua_State *L, int level, lua_Debug *ar);
  IMPORT_SYMBOL(lua_getinfo, int, lua_State *L, const char *what, lua_Debug *ar);
  IMPORT_SYMBOL(lua_getlocal, const char *, lua_State *L, const lua_Debug *ar, int n);
  IMPORT_SYMBOL(lua_setlocal, const char *, lua_State *L, const lua_Debug *ar, int n);
  IMPORT_SYMBOL(lua_getupvalue, const char *, lua_State *L, int funcindex, int n);
  IMPORT_SYMBOL(lua_setupvalue, const char *, lua_State *L, int funcindex, int n);
  IMPORT_SYMBOL(lua_upvalueid, void *, lua_State *L, int fidx, int n);
  IMPORT_SYMBOL(lua_upvaluejoin, void, lua_State *L, int fidx1, int n1, int fidx2, int n2);
  IMPORT_SYMBOL(lua_sethook, void, lua_State *L, lua_Hook func, int mask, int count);
  IMPORT_SYMBOL(lua_gethook, lua_Hook, lua_State *L);
  IMPORT_SYMBOL(lua_gethookmask, int, lua_State *L);
  IMPORT_SYMBOL(lua_gethookcount, int, lua_State *L);
  IMPORT_SYMBOL(lua_setcstacklimit, int, lua_State *L, unsigned int limit);
  IMPORT_SYMBOL(luaL_checkversion_, void, lua_State *L, lua_Number ver, size_t sz);
  IMPORT_SYMBOL(luaL_getmetafield, int, lua_State *L, int obj, const char *e);
  IMPORT_SYMBOL(luaL_callmeta, int, lua_State *L, int obj, const char *e);
  IMPORT_SYMBOL(luaL_tolstring, const char *, lua_State *L, int idx, size_t *len);
  IMPORT_SYMBOL(luaL_argerror, int, lua_State *L, int numarg, const char *extramsg);
  IMPORT_SYMBOL(luaL_typeerror, int, lua_State *L, int arg, const char *tname);
  IMPORT_SYMBOL(luaL_checklstring, const char *, lua_State *L, int numArg, size_t *l);
  IMPORT_SYMBOL(luaL_optlstring, const char *, lua_State *L, int numArg, const char *def, size_t *l);
  IMPORT_SYMBOL(luaL_checknumber, lua_Number, lua_State *L, int numArg);
  IMPORT_SYMBOL(luaL_optnumber, lua_Number, lua_State *L, int nArg, lua_Number def);
  IMPORT_SYMBOL(luaL_checkinteger, lua_Integer, lua_State *L, int numArg);
  IMPORT_SYMBOL(luaL_optinteger, lua_Integer, lua_State *L, int nArg, lua_Integer def);
  IMPORT_SYMBOL(luaL_checkstack, void, lua_State *L, int sz, const char *msg);
  IMPORT_SYMBOL(luaL_checktype, void, lua_State *L, int narg, int t);
  IMPORT_SYMBOL(luaL_checkany, void, lua_State *L, int narg);
  IMPORT_SYMBOL(luaL_newmetatable, int, lua_State *L, const char *tname);
  IMPORT_SYMBOL(luaL_setmetatable, void, lua_State *L, const char *tname);
  IMPORT_SYMBOL(luaL_testudata, void *, lua_State *L, int ud, const char *tname);
  IMPORT_SYMBOL(luaL_checkudata, void *, lua_State *L, int ud, const char *tname);
  IMPORT_SYMBOL(luaL_where, void, lua_State *L, int lvl);
  IMPORT_SYMBOL(luaL_error, int, lua_State *L, const char *fmt, ...);
  IMPORT_SYMBOL(luaL_checkoption, int, lua_State *L, int narg, const char *def, const char *const lst[]);
  IMPORT_SYMBOL(luaL_fileresult, int, lua_State *L, int stat, const char *fname);
  IMPORT_SYMBOL(luaL_execresult, int, lua_State *L, int stat);
  IMPORT_SYMBOL(luaL_ref, int, lua_State *L, int t);
  IMPORT_SYMBOL(luaL_unref, void, lua_State *L, int t, int ref);
  IMPORT_SYMBOL(luaL_loadfilex, int, lua_State *L, const char *filename, const char *mode);
  IMPORT_SYMBOL(luaL_loadbufferx, int, lua_State *L, const char *buff, size_t sz, const char *name, const char *mode);
  IMPORT_SYMBOL(luaL_loadstring, int, lua_State *L, const char *s);
  IMPORT_SYMBOL(luaL_newstate, lua_State *, void);
  IMPORT_SYMBOL(luaL_len, lua_Integer, lua_State *L, int idx);
  IMPORT_SYMBOL(luaL_addgsub, void, luaL_Buffer *b, const char *s, const char *p, const char *r);
  IMPORT_SYMBOL(luaL_gsub, const char *, lua_State *L, const char *s, const char *p, const char *r);
  IMPORT_SYMBOL(luaL_setfuncs, void, lua_State *L, const luaL_Reg *l, int nup);
  IMPORT_SYMBOL(luaL_getsubtable, int, lua_State *L, int idx, const char *fname);
  IMPORT_SYMBOL(luaL_traceback, void, lua_State *L, lua_State *L1, const char *msg, int level);
  IMPORT_SYMBOL(luaL_requiref, void, lua_State *L, const char *modname, lua_CFunction openf, int glb);
  IMPORT_SYMBOL(luaL_buffinit, void, lua_State *L, luaL_Buffer *B);
  IMPORT_SYMBOL(luaL_prepbuffsize, char *, luaL_Buffer *B, size_t sz);
  IMPORT_SYMBOL(luaL_addlstring, void, luaL_Buffer *B, const char *s, size_t l);
  IMPORT_SYMBOL(luaL_addstring, void, luaL_Buffer *B, const char *s);
  IMPORT_SYMBOL(luaL_addvalue, void, luaL_Buffer *B);
  IMPORT_SYMBOL(luaL_pushresult, void, luaL_Buffer *B);
  IMPORT_SYMBOL(luaL_pushresultsize, void, luaL_Buffer *B, size_t sz);
  IMPORT_SYMBOL(luaL_buffinitsize, char *, lua_State *L, luaL_Buffer *B, size_t sz);
  IMPORT_SYMBOL(luaopen_base, int, lua_State *L);
  IMPORT_SYMBOL(luaopen_coroutine, int, lua_State *L);
  IMPORT_SYMBOL(luaopen_table, int, lua_State *L);
  IMPORT_SYMBOL(luaopen_io, int, lua_State *L);
  IMPORT_SYMBOL(luaopen_os, int, lua_State *L);
  IMPORT_SYMBOL(luaopen_string, int, lua_State *L);
  IMPORT_SYMBOL(luaopen_utf8, int, lua_State *L);
  IMPORT_SYMBOL(luaopen_math, int, lua_State *L);
  IMPORT_SYMBOL(luaopen_debug, int, lua_State *L);
  IMPORT_SYMBOL(luaopen_package, int, lua_State *L);
  IMPORT_SYMBOL(luaL_openlibs, void, lua_State* L);
}

#undef IMPORT_SYMBOL
#undef IMPORT_SYMBOL_OPT

#else /* LITE_XL_PLUGIN_ENTRYPOINT */

void lite_xl_plugin_init(void *XL);

#endif /* LITE_XL_PLUGIN_ENTRYPOINT */

#undef LITE_XL_API
#undef SYMBOL_WRAP_DECL
#undef SYMBOL_WRAP_CALL
#undef SYMBOL_WRAP_CALL_FB
#undef SYMBOL_DECLARE
#undef SYMBOL_DECLARE_VARARG
#undef UNUSED
#undef CONCAT
#undef CONCAT1
#undef CONCAT2
#undef FE_1
#undef FE_2
#undef FE_3
#undef FE_4
#undef FE_5
#undef FE_6
#undef FE_7
#undef FE_8
#undef FOR_EACH_NARG
#undef FOR_EACH_NARG_
#undef FOR_EACH_ARG_N
#undef FOR_EACH_RSEQ_N
#undef FOR_EACH_
#undef FOR_EACH

#endif /* LITE_XL_PLUGIN_API */

/******************************************************************************
* Copyright (C) 1994-2023 Lua.org, PUC-Rio; Lite XL contributors.
*
* Permission is hereby granted, free of charge, to any person obtaining
* a copy of this software and associated documentation files (the
* "Software"), to deal in the Software without restriction, including
* without limitation the rights to use, copy, modify, merge, publish,
* distribute, sublicense, and/or sell copies of the Software, and to
* permit persons to whom the Software is furnished to do so, subject to
* the following conditions:
*
* The above copyright notice and this permission notice shall be
* included in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
******************************************************************************/ 
