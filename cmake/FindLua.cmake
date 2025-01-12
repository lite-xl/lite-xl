#
# LUA_FOUND
# LUA_INCLUDE_DIR
# LUA_LIBRARIES

macro(SystemLua)
    include(${CMAKE_ROOT}/Modules/FindLua.cmake)

    if (LUA_FOUND)
        return()
    endif()
endmacro()

macro(FallbackLua)
    include(FetchContent)

    set(patch_path ${CMAKE_CURRENT_LIST_DIR}/lua/lua-unicode.diff)

    find_program(PATCH patch)
    find_package(Git)

    if(NOT PATCH STREQUAL "PATCH-NOTFOUND")
        set(lua_patch ${PATCH} -l -f -p1 -i ${patch_path})
    elseif(Git_FOUND)
        set(lua_patch ${GIT_EXECUTABLE} --work-tree . apply --ignore-whitespace -p1 ${patch_path})
    else()
        message(FATAL_ERROR "Missing \"patch\" or \"git\" commands to apply patch")
    endif()

    cmake_policy(SET CMP0135 OLD)
    FetchContent_Declare(
        lua
        URL https://www.lua.org/ftp/lua-5.4.7.tar.gz
        PATCH_COMMAND ${lua_patch}
        UPDATE_DISCONNECTED 1
    )
    FetchContent_MakeAvailable(lua)
    FetchContent_GetProperties(lua SOURCE_DIR LUA_DIR)

    add_library(lua-static STATIC
        ${LUA_DIR}/src/lapi.c
        ${LUA_DIR}/src/lcode.c
        ${LUA_DIR}/src/lctype.c
        ${LUA_DIR}/src/ldebug.c
        ${LUA_DIR}/src/ldo.c
        ${LUA_DIR}/src/ldump.c
        ${LUA_DIR}/src/lfunc.c
        ${LUA_DIR}/src/lgc.c
        ${LUA_DIR}/src/llex.c
        ${LUA_DIR}/src/lmem.c
        ${LUA_DIR}/src/lobject.c
        ${LUA_DIR}/src/lopcodes.c
        ${LUA_DIR}/src/lparser.c
        ${LUA_DIR}/src/lstate.c
        ${LUA_DIR}/src/lstring.c
        ${LUA_DIR}/src/ltable.c
        ${LUA_DIR}/src/ltm.c
        ${LUA_DIR}/src/lundump.c
        ${LUA_DIR}/src/lvm.c
        ${LUA_DIR}/src/lzio.c
        ${LUA_DIR}/src/lauxlib.c
        ${LUA_DIR}/src/lbaselib.c
        ${LUA_DIR}/src/lcorolib.c
        ${LUA_DIR}/src/ldblib.c
        ${LUA_DIR}/src/liolib.c
        ${LUA_DIR}/src/lmathlib.c
        ${LUA_DIR}/src/loadlib.c
        ${LUA_DIR}/src/loslib.c
        ${LUA_DIR}/src/lstrlib.c
        ${LUA_DIR}/src/ltablib.c
        ${LUA_DIR}/src/lutf8lib.c
        ${LUA_DIR}/src/linit.c
        ${LUA_DIR}/src/utf8_wrappers.c
    )
    target_include_directories(lua-static PUBLIC ${LUA_DIR}/src)

    list(APPEND POSIX_SYSTEM_NAMES
        CYGWIN
        Darwin
        DragonFly
        FreeBSD
        GNU
        Haiku
        Linux
        NetBSD
        OpenBSD
        SunOS
    )
    if(NOT ("${CMAKE_HOST_SYSTEM_NAME}" IN_LIST POSIX_SYSTEM_NAMES))
        target_compile_definitions(lua-static PUBLIC LUA_USE_POSIX)
    endif()

    if (CMAKE_DL_LIBS)
        target_compile_definitions(lua-static PUBLIC LUA_USE_DLOPEN)
        target_link_libraries(lua-static PUBLIC ${CMAKE_DL_LIBS})
    endif()

    find_library(MATH_LIBRARY m)
    if(MATH_LIBRARY)
        target_link_libraries(lua-static PUBLIC ${MATH_LIBRARY})
    endif()

    set(LUA_FOUND TRUE)
    # the include directory will be propagated through the library
    set(LUA_INCLUDE_DIR "")
    set(LUA_LIBRARIES lua-static)

    return()
endmacro()

if (use_system_lua AND NOT "lua" IN_LIST force_fallback_for)
    SystemLua()
endif()
if (NOT offline)
    FallbackLua()
endif()

message(FATAL_ERROR "Lua could not be found")
