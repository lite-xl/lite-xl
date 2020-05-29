lite_sources = [
    'api/api.c',
    'api/renderer.c',
    'api/renderer_font.c',
    'api/system.c',
    'renderer.c',
    'agg_font_freetype.cpp',
    'font_render_capi.cpp',
    'rencache.c',
    'main.c',
]

executable('stb-font-render-test',
    'stb_font_render_test.c',
    include_directories: lite_include,
    dependencies: [sdl_dep, stb_truetype_dep, libm, libdl],
    install: false,
)
