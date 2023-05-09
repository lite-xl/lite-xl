cmake_minimum_required(VERSION 3.12 FATAL_ERROR)

if(CMAKE_POLICY_DEFAULT_CMP0017 OR CMAKE_POLICY_DEFAULT_CMP0020)
    # touch these to remove warnings
endif()

# Set the default build type to release
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING
        "Choose the type of build, options are: None Debug Release RelWithDebInfo MinSizeRel." FORCE)
endif()

project(lite-xl VERSION 2.1.1 LANGUAGES C)

option(MACOS_BUNDLE, "Build a MacOS bundle" OFF)
option(SOURCE_ONLY "Configure source files only, doesn't check for dependencies" OFF)
option(PORTABLE "Portable install" OFF)
option(SDL_RENDERER "Use SDL renderer" OFF)
set(DIRMONITOR_BACKEND "" CACHE STRING "Select a dirmonitor backend")
set(ARCH_TUPLE "${CMAKE_SYSTEM_PROCESSOR}" CACHE STRING "Specify a custom architecture tuple")

add_compile_definitions(LITE_ARCH_TUPLE="${ARCH_TUPLE}")
if(SDL_RENDERER OR APPLE)
    add_compile_definitions(LITE_USE_SDL_RENDERER)
endif()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

if (PORTABLE OR WIN32)
    set(LITE_BINDIR "")
    set(LITE_DOCDIR "doc")
    set(LITE_DATADIR "data")
elseif(MACOS_BUNDLE AND APPLE)
    add_compile_definitions(MACOS_USE_BUNDLE)
    set(CONTENTS_DIR "Contents")
    set(LITE_BINDIR "${CONTENTS_DIR}/MacOS")
    set(LITE_DOCDIR "${CONTENTS_DIR}/Resources")
    set(LITE_DATADIR "${CONTENTS_DIR}/Resources")

    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/resources/macos/Info.plist.in"
        "Info.plist"
        @ONLY
    )

    install(FILES ${CMAKE_SOURCE_DIR}/resources/icons/icon.icns DESTINATION ${LITE_DATADIR})
    install(FILES Info.plist DESTINATION ${CONTENTS_DIR})
else()
    include(GNUInstallDirs)
    set(LITE_BINDIR "${CMAKE_INSTALL_BINDIR}")
    set(LITE_DOCDIR "${CMAKE_INSTALL_DOCDIR}")
    set(LITE_DATADIR "${CMAKE_INSTALL_DATADIR}/lite-xl")
    if (UNIX)
        install(FILES ${CMAKE_SOURCE_DIR}/resources/icons/lite-xl.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps/)
        install(FILES ${CMAKE_SOURCE_DIR}/resources/linux/org.lite_xl.lite_xl.appdata.xml DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo/)
        install(FILES ${CMAKE_SOURCE_DIR}/resources/linux/org.lite_xl.lite_xl.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications/)
    endif()
endif()

install(FILES ${CMAKE_SOURCE_DIR}/licenses/licenses.md DESTINATION ${LITE_DOCDIR})

install(DIRECTORY ${CMAKE_SOURCE_DIR}/docs/api DESTINATION ${LITE_DATADIR})
install(DIRECTORY ${CMAKE_SOURCE_DIR}/data/core DESTINATION ${LITE_DATADIR} FILES_MATCHING PATTERN "start.lua" EXCLUDE)
foreach(module fonts plugins colors)
    install(DIRECTORY "${CMAKE_SOURCE_DIR}/data/${module}" DESTINATION ${LITE_DATADIR})
endforeach()

if (NOT SOURCE_ONLY)
    add_subdirectory(src)

    if (WIN32)
        configure_file(
            "${CMAKE_CURRENT_SOURCE_DIR}/scripts/innosetup/innosetup.iss.in"
            "innosetup.iss"
            @ONLY
        )
    endif()
endif()
