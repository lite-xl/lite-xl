
while(NOT DIRMONITOR_BACKEND)

    include(CheckSymbolExists)

    check_symbol_exists(inotify_init "sys/inotify.h" HAVE_INOTIFY_INIT)
    if(HAVE_INOTIFY_INIT)
        set(DIRMONITOR_BACKEND "inotify")
        break()
    endif()

    if(APPLE)
        check_include_file("CoreServices/CoreServices.h" HAVE_CORESERVICES)
        if(HAVE_CORESERVICES)
            set(DIRMONITOR_BACKEND "fsevents")
            break()
        endif()
    endif()

    check_symbol_exists(kqueue "sys/event.h" HAVE_KQUEUE)
    if(HAVE_KQUEUE)
        set(DIRMONITOR_BACKEND "kqueue")
        break()
    endif()

    if (WIN32)
        set(DIRMONITOR_BACKEND "win32")
        break()
    endif()

    set(DIRMONITOR_BACKEND "dummy")
    message(WARNING "No suitable backend found, defaulting to dummy backend")
endwhile()

if (NOT DIRMONITOR_BACKEND)
    message(FATAL_ERROR "Could not find a suitable backend")
endif()

message(STATUS "dirmonitor backend: ${DIRMONITOR_BACKEND}")

list(APPEND
    DIRMONITOR_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/${DIRMONITOR_BACKEND}.c"
)

add_library(dirmonitor OBJECT ${DIRMONITOR_SOURCES})
