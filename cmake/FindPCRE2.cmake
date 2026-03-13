#
# PCRE2_FOUND
# PCRE2_INCLUDE_DIR
# PCRE2_LIBRARIES

macro(SystemPCRE2)
    find_path(PCRE2_INCLUDE_DIR NAMES pcre2.h DOC "PCRE2 include directory")
    find_library(
        PCRE2_LIBRARIES
        DOC "8 bit PCRE2 library"
        NAMES pcre2-8
    )

    if (NOT PCRE2_LIBRARIES STREQUAL "PCRE2_LIBRARIES-NOTFOUND")
        set(PCRE2_FOUND TRUE)
        message(STATUS "Found PCRE2: ${PCRE2_LIBRARIES}")
        return()
    endif()
endmacro()

macro(FallbackPCRE2)
    include(FetchContent)

    # PCRE2 options
    set(BUILD_SHARED_LIBS OFF CACHE BOOL "")
    set(BUILD_STATIC_LIBS ON CACHE BOOL "")
    set(PCRE2_BUILD_PCRE2_8 ON CACHE BOOL "")
    set(PCRE2_BUILD_PCRE2_16 OFF CACHE BOOL "")
    set(PCRE2_BUILD_PCRE2_32 OFF CACHE BOOL "")
    set(PCRE2_BUILD_TESTS OFF CACHE BOOL "")
    set(PCRE2_BUILD_PCRE2GREP OFF CACHE BOOL "")
    set(PCRE2_BUILD_TESTS OFF CACHE BOOL "")

    FetchContent_Declare(
            pcre2
            GIT_REPOSITORY https://github.com/PCRE2Project/pcre2.git
            GIT_TAG pcre2-10.44 
            GIT_SHALLOW TRUE
            GIT_PROGRESS TRUE
    )
    FetchContent_MakeAvailable(pcre2)

    set(PCRE2_FOUND TRUE)
    # the include directory will be propagated through the library
    set(PCRE2_INCLUDE_DIR "")
    set(PCRE2_LIBRARIES pcre2-8-static)

    return()
endmacro()

if (NOT "pcre2" IN_LIST force_fallback_for)
    SystemPCRE2()
endif()
if (NOT offline)
    FallbackPCRE2()
endif()

message(FATAL_ERROR "PCRE2 could not be found")
