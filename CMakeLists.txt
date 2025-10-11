cmake_minimum_required(VERSION 3.18)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING
        "Choose the type of build, options are: None Debug Release RelWithDebInfo MinSizeRel." FORCE)
endif()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# Project options
option(bundle "Build a macOS bundle" OFF)
option(source-only "Configure source files only, doesn't checks for dependencies" OFF)
option(portable "Portable install" OFF)
option(renderer "Use SDL renderer" OFF)
set(dirmonitor_backend "" CACHE STRING "define what dirmonitor backend to use")
set(arch_tuple "" CACHE STRING "Specify a custom architecture tuple")
option(use_system_lua "Prefer System Lua" OFF)
set(bundle_plugins "" CACHE STRING "Plugins to bundle when building Lite XL")

option(offline "Don't use fallbacks ")
set(force_fallback_for "" CACHE STRING "Force fallback for those dependencies")

project(lite-xl
    LANGUAGES C
    VERSION 2.1.7
)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_EXTENSIONS ON)

set(PROJECT_VERSION "${CMAKE_PROJECT_VERSION}")
if(NOT CMAKE_BUILD_TYPE STREQUAL "Release")
    find_package(Git)
    if(Git_FOUND)
        execute_process(
            COMMAND ${GIT_EXECUTABLE} rev-parse HEAD
            OUTPUT_VARIABLE GIT_COMMIT
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )

        if (NOT GIT_COMMIT STREQUAL "")
            string(SUBSTRING "${GIT_COMMIT}" 0 8 GIT_COMMIT_SHORT)
            set(PROJECT_VERSION "${PROJECT_VERSION} (git-${GIT_COMMIT_SHORT})")
        endif()

    endif()
endif()

message(STATUS "Project name: ${CMAKE_PROJECT_NAME}")
message(STATUS "Project version: ${PROJECT_VERSION}")

set(PROJECT_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}")
set(PROJECT_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(PROJECT_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")

if (portable OR WIN32)
    set(lite_bindir "/")
    set(lite_docdir "/doc")
    set(lite_datadir "/data")
    set(lpm_userdir "data")
    set(lpm_install_dir "/")
elseif(bundle OR CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    add_compile_definitions(MACOS_USE_BUNDLE)
    set(lite_bindir "Contents/MacOS")
    set(lite_docdir "Contents/Resources")
    set(lite_datadir "Contents/Resources")
    set(lpm_userdir "Resources")
    set(lpm_install_dir "Contents")
else()
    include(GNUInstallDirs)
    set(lite_bindir "bin")
    set(lite_docdir "${CMAKE_INSTALL_DOCDIR}/lite-xl")
    set(lite_datadir "${CMAKE_INSTALL_DATADIR}/lite-xl")
    set(lpm_userdir "lite-xl")
    set(lpm_install_dir "${CMAKE_INSTALL_DATADIR}")

    if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
        set(METAINFO_RELEASES "")
        find_package(Git)
        if(Git_FOUND)
            execute_process(COMMAND ${GIT_EXECUTABLE} tag -l --sort=-version:refname "--format=%(refname:strip=2) %(creatordate:short)" WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" OUTPUT_VARIABLE RELEASE_TAGS OUTPUT_STRIP_TRAILING_WHITESPACE)
            string(REPLACE "\n" ";" TAGS_LIST "${RELEASE_TAGS}")
            foreach(TAG ${TAGS_LIST})
                string(REPLACE " " ";" TAG_LIST ${TAG})
                list(GET TAG_LIST 0 TAG_REF)
                list(GET TAG_LIST 1 TAG_DATE)

                # Check dash usually signifies an alpha or a beta tag
                string(FIND ${TAG_REF} "-" TAG_UNSTABLE)
                # Check if ref starts with v
                string(FIND ${TAG_REF} "v" TAG_V)

                if (NOT ${TAG_UNSTABLE} EQUAL -1 OR NOT ${TAG_V} EQUAL 0)
                    continue()
                endif()

                # releases 1.01 to 1.09 use an invalid versioning scheme sao we ignore them
                if (TAG_REF STREQUAL "v1.0")
                    continue()
                endif()

                list(APPEND RELEASE_LIST "<release version=\"${TAG_REF}\" date=\"${TAG_DATE}\" />")
            endforeach()

            list(LENGTH RELEASE_LIST RELEASE_COUNT)
            if (NOT RELEASE_COUNT EQUAL 0)
                list(JOIN RELEASE_LIST "\n" RELEASE_STR)
                set(METAINFO_RELEASES "<releases>\n${RELEASE_STR}\n</releases>")
            endif()
        endif()
        install(FILES resources/icons/lite-xl.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)
        install(FILES resources/linux/com.lite_xl.LiteXL.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
        configure_file(resources/linux/com.lite_xl.LiteXL.metainfo.xml.in com.lite_xl.LiteXL.metainfo.xml.in)
        install(FILES ${CMAKE_BINARY_DIR}/com.lite_xl.LiteXL.metainfo.xml.in DESTINATION ${CMAKE_INSTALL_DATADIR}/metainfo)
    endif()
endif()

if (CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    enable_language(OBJC)
endif()

configure_file(data/core/start.lua core/start.lua)

install(FILES licenses/licenses.md DESTINATION ${lite_docdir})
install(DIRECTORY docs/api DESTINATION ${lite_datadir})
install(DIRECTORY data/core DESTINATION ${lite_datadir} PATTERN "start.lua" EXCLUDE)
install(DIRECTORY ${CMAKE_BINARY_DIR}/core DESTINATION ${lite_datadir})
foreach(data_module fonts plugins colors)
    install(DIRECTORY data/${data_module} DESTINATION ${lite_datadir})
endforeach()

if (NOT source-only)
    add_subdirectory(src)
endif()
