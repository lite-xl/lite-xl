#
# SDL2_FOUND
# SDL2_INCLUDE_DIR
# SDL2_LIBRARIES

macro(SystemSDL2)
    find_package(SDL2 CONFIG)

    if (SDL2_FOUND)
        message(STATUS "Found SDL2: ${SDL2_LIBRARIES}")
        return()
    endif()
endmacro()

macro(FallbackSDL2)
    include(FetchContent)

    # SDL2 options
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "")
    set(BUILD_STATIC_LIBS ON CACHE BOOL "")

    FetchContent_Declare(
            sdl2
            GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
            GIT_TAG release-2.30.11
            GIT_SHALLOW TRUE
            GIT_PROGRESS TRUE
    )
    FetchContent_MakeAvailable(sdl2)

    set(SDL2_FOUND TRUE)
    # the include directory will be propagated through the library
    set(SDL2_INCLUDE_DIR "")
    set(SDL2_LIBRARIES SDL2::SDL2main SDL2::SDL2-static)

    return()
endmacro()

if (NOT "sdl2" IN_LIST force_fallback_for)
    SystemSDL2()
endif()
if (NOT offline)
    FallbackSDL2()
endif()

message(FATAL_ERROR "SDL2 could not be found")
