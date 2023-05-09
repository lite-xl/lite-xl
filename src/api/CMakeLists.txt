find_package(PCRE2 REQUIRED)
find_package(SDL2 REQUIRED)
find_package(lua REQUIRED)

add_subdirectory(dirmonitor)

list(APPEND
  API_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/api.c
    ${CMAKE_CURRENT_SOURCE_DIR}/api.h
    ${CMAKE_CURRENT_SOURCE_DIR}/dirmonitor.c
    ${CMAKE_CURRENT_SOURCE_DIR}/process.c
    ${CMAKE_CURRENT_SOURCE_DIR}/regex.c
    ${CMAKE_CURRENT_SOURCE_DIR}/renderer.c
    ${CMAKE_CURRENT_SOURCE_DIR}/system.c
    ${CMAKE_CURRENT_SOURCE_DIR}/utf8.c
)

add_library(api OBJECT ${API_SOURCES})
target_include_directories(api PUBLIC ${SDL2_INCLUDE_DIRS})
target_include_directories(api PUBLIC ${PCRE2_INCLUDE_DIRS})
target_include_directories(api PUBLIC ${LUA_INCLUDE_DIRS})
target_link_libraries(api PUBLIC ${SDL2_LIBRARIES})
target_link_libraries(api PUBLIC ${PCRE2_LIBRARIES})
target_link_libraries(api PUBLIC ${LUA_LIBRARIES})
