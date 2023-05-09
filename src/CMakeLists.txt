find_package(SDL2 REQUIRED)
find_package(Freetype REQUIRED)
find_package(lua REQUIRED)

add_subdirectory(api)

list(APPEND
    LITE_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/main.c
    ${CMAKE_CURRENT_SOURCE_DIR}/rencache.c
    ${CMAKE_CURRENT_SOURCE_DIR}/rencache.h
    ${CMAKE_CURRENT_SOURCE_DIR}/renderer.c
    ${CMAKE_CURRENT_SOURCE_DIR}/renderer.h
    ${CMAKE_CURRENT_SOURCE_DIR}/renwindow.c
    ${CMAKE_CURRENT_SOURCE_DIR}/renwindow.h
    ${CMAKE_CURRENT_SOURCE_DIR}/unidata.h
    ${CMAKE_CURRENT_SOURCE_DIR}/utfconv.h
)

if(WIN32)
    list(APPEND
        LITE_SOURCES
        ${CMAKE_SOURCE_DIR}/resources/icons/icon.rc
        ${CMAKE_SOURCE_DIR}/resources/windows/manifest.rc
    )
elseif(APPLE)
    list(APPEND
        LITE_SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/bundle_open.m
    )
endif()

add_executable(lite-xl WIN32 ${LITE_SOURCES})
target_link_libraries(lite-xl PUBLIC api)
target_link_libraries(lite-xl PUBLIC dirmonitor)

target_include_directories(lite-xl PUBLIC ${SDL2_INCLUDE_DIRS})
target_include_directories(lite-xl PUBLIC ${FREETYPE_INCLUDE_DIRS})
target_include_directories(lite-xl PUBLIC ${LUA_INCLUDE_DIRS})
target_link_libraries(lite-xl PUBLIC ${SDL2_LIBRARIES})
target_link_libraries(lite-xl PUBLIC ${FREETYPE_LIBRARIES})
target_link_libraries(lite-xl PUBLIC ${LUA_LIBRARIES})
if (APPLE)
  target_link_libraries(lite-xl PUBLIC "-framework CoreServices")
  target_link_libraries(lite-xl PUBLIC "-framework Foundation")
endif()

target_link_libraries(lite-xl PUBLIC m)

install(TARGETS lite-xl)
