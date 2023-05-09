#
# LUA_FOUND
# LUA_INCLUDE_DIRS
# LUA_LIBRARIES

find_package(PkgConfig QUIET)
if (PKG_CONFIG_FOUND)
    pkg_check_modules(_LUA lua QUIET)
endif()

find_path(LUA_INC
    NAMES lua.h
    HINTS
        ${_LUA_INCLUDE_DIRS}
)

find_library(LUA_LIB
    NAMES ${_LUA_LIBRARIES} lua
    HINTS
        ${_LUA_LIBRARY_DIRS}
        ${_LUA_STATIC_LIBRARY_DIRS}
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(lua DEFAULT_MSG LUA_LIB LUA_INC)
mark_as_advanced(LUA_INC LUA_LIB)

if(LUA_FOUND)
    set(LUA_INCLUDE_DIRS ${LUA_INC})
    set(LUA_LIBRARIES ${LUA_LIB})
endif()
