#
# FREETYPE_FOUND
# FREETYPE_INCLUDE_DIRS
# FREETYPE_LIBRARIES

macro(SystemFreetype)
    include(${CMAKE_ROOT}/Modules/FindFreetype.cmake)

    if (FREETYPE_FOUND)
        return()
    endif()
endmacro()

macro(FallbackFreetype)
    include(FetchContent)

    # Freetype options
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "")
    set(BUILD_STATIC_LIBS ON CACHE BOOL "")
    set(FT_DISABLE_ZLIB ON CACHE BOOL "")
    set(FT_DISABLE_BZIP2 ON CACHE BOOL "")
    set(FT_DISABLE_PNG ON CACHE BOOL "")
    set(FT_DISABLE_HARFBUZZ ON CACHE BOOL "")
    set(FT_DISABLE_BROTLI ON CACHE BOOL "")

    FetchContent_Declare(
            freetype
            GIT_REPOSITORY https://gitlab.freedesktop.org/freetype/freetype.git
            GIT_TAG VER-2-13-3
            GIT_SHALLOW TRUE
            GIT_PROGRESS TRUE
    )
    FetchContent_MakeAvailable(freetype)

    set(FREETYPE_FOUND TRUE)
    # the include directory will be propagated through the library
    set(FREETYPE_INCLUDE_DIRS "")
    set(FREETYPE_LIBRARIES freetype)

    return()
endmacro()

if (NOT "freetype" IN_LIST force_fallback_for)
    SystemFreetype()
endif()
if (NOT offline)
    FallbackFreetype()
endif()

message(FATAL_ERROR "Freetype could not be found")
