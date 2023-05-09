#
# PCRE2_FOUND
# PCRE2_INCLUDE_DIRS
# PCRE2_LIBRARIES

find_package(PkgConfig QUIET)
if (PKG_CONFIG_FOUND)
    pkg_check_modules(_PCRE2 libpcre2-8 QUIET)
endif()

find_path(PCRE2_INC
    NAMES pcre2.h
    HINTS
        ${_PCRE2_INCLUDE_DIRS}
)

find_library(PCRE2_LIB
    NAMES ${_PCRE2_LIBRARIES} pcre2-8
    HINTS
        ${_PCRE2_LIBRARY_DIRS}
        ${_PCRE2_STATIC_LIBRARY_DIRS}
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(PCRE2 DEFAULT_MSG PCRE2_LIB PCRE2_INC)
mark_as_advanced(PCRE2_INC PCRE2_LIB)

if(PCRE2_FOUND)
    set(PCRE2_INCLUDE_DIRS ${PCRE2_INC})
    set(PCRE2_LIBRARIES ${PCRE2_LIB})
endif()
