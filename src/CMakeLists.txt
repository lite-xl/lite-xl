include(CheckIncludeFile)
include(CheckSymbolExists)

find_package(SDL2 REQUIRED)
find_package(Freetype REQUIRED)
find_package(Lua REQUIRED)
find_package(PCRE2 REQUIRED)

list(APPEND lite_sources
    api/api.c
    api/renderer.c
    api/renwindow.c
    api/regex.c
    api/system.c
    api/process.c
    api/utf8.c
    arena_allocator.c
    renderer.c
    renwindow.c
    rencache.c
    main.c
)

list(APPEND lite_sources api/dirmonitor.c)
if (dirmonitor_backend STREQUAL "")
    message(CHECK_START "Finding suitable dirmonitor backend")
    list(APPEND CMAKE_MESSAGE_INDENT "  ")

    check_symbol_exists(inotify_init "sys/inotify.h" HAVE_INOTIFY_INIT)
    check_include_file("CoreServices/CoreServices.h" HAVE_CORESERVICES)
    check_symbol_exists(kqueue "sys/event.h" HAVE_KQUEUE)
    check_symbol_exists(create_inode_watcher "fcntl.h" HAVE_INODE_WATCHER)

    if (HAVE_INOTIFY_INIT)
        set(dirmonitor_backend "inotify" CACHE STRING "" FORCE)
    elseif(HAVE_CORESERVICES)
        set(dirmonitor_backend "fsevents" CACHE STRING "" FORCE)        
    elseif(HAVE_KQUEUE)
        set(dirmonitor_backend "kqueue" CACHE STRING "" FORCE)
    elseif(HAVE_INODE_WATCHER)
        set(dirmonitor_backend "inodewatcher" CACHE STRING "" FORCE)
    elseif(WIN32)
        set(dirmonitor_backend "win32" CACHE STRING "" FORCE)
    else()
        set(dirmonitor_backend "dummy" CACHE STRING "" FORCE)
    endif()

    list(POP_BACK CMAKE_MESSAGE_INDENT)
    message(CHECK_PASS "${dirmonitor_backend}")
endif()

if (dirmonitor_backend STREQUAL "inotify")
    list(APPEND lite_sources api/dirmonitor/inotify.c)
elseif (dirmonitor_backend STREQUAL "fsevents")
    list(APPEND lite_sources api/dirmonitor/fsevents.c)
elseif (dirmonitor_backend STREQUAL "kqueue")
    list(APPEND lite_sources api/dirmonitor/kqueue.c)
elseif (dirmonitor_backend STREQUAL "inodewatcher")
    enable_language(CXX)
    list(APPEND lite_sources api/dirmonitor/inodewatcher.cpp)
elseif (dirmonitor_backend STREQUAL "win32")
    list(APPEND lite_sources api/dirmonitor/win32.c)
elseif (dirmonitor_backend STREQUAL "dummy")
    list(APPEND lite_sources api/dirmonitor/dummy.c)
else()
    message(FATAL_ERROR "Invalid dirmonitor backend ${dirmonitor_backend}")
endif()

if (WIN32)
    list(APPEND lite_sources
        ../resources/icons/icon.rc
        ../resources/icons/manifest.rc
    )
elseif (CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    list(APPEND lite_sources bundle_open.m)
endif()

add_executable(lite-xl WIN32 ${lite_sources})
target_include_directories(lite-xl PUBLIC
    .
    ${SDL2_INCLUDE_DIR}
    ${FREETYPE_INCLUDE_DIRS}
    ${LUA_INCLUDE_DIR}
    ${PCRE2_INCLUDE_DIR}
)
target_link_libraries(lite-xl PUBLIC
    ${SDL2_LIBRARIES}
    ${FREETYPE_LIBRARIES}
    ${LUA_LIBRARIES}
    ${PCRE2_LIBRARIES}
)

if (renderer)
    target_compile_definitions(lite-xl PUBLIC LITE_USE_SDL_RENDERER)
endif()

if (arch_tuple STREQUAL "")
    string(TOLOWER "${CMAKE_SYSTEM_NAME}" LOWER_SYSTEM_NAME)
    string(REPLACE "-" "_" SYSTEM_PROCESSOR "${CMAKE_SYSTEM_PROCESSOR}")

    set(arch_tuple "${SYSTEM_PROCESSOR}-${LOWER_SYSTEM_NAME}" CACHE STRING "" FORCE)
endif()

target_compile_definitions(lite-xl PUBLIC LITE_ARCH_TUPLE="${arch_tuple}")

install(TARGETS lite-xl DESTINATION ${lite_bindir})
