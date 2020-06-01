lite_sources = [
    'api/api.c',
    'api/renderer.c',
    'api/renderer_font.c',
    'api/system.c',
    'renderer.c',
    'agg_font_freetype.cpp',
    'font_renderer.cpp',
    'rencache.c',
    'main.c',
]

executable('lite',
    lite_sources,
    include_directories: lite_include,
    dependencies: [lua_dep, sdl_dep, stb_truetype_dep, libagg_dep, freetype_dep, libm, libdl],
    install: true,
    gui_app: true,
)
