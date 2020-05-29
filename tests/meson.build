executable('stb-font-render-test',
    'stb_font_render_test.c',
    include_directories: lite_include,
    dependencies: [sdl_dep, stb_truetype_dep, libm, libdl],
    install: false,
)

executable('agg-font-render-test',
    ['agg_font_render_test.cpp', '../src/agg_font_freetype.cpp'],
    include_directories: lite_include,
    dependencies: [sdl_dep, libagg_dep, freetype_dep, libm, libdl],
    install: false,
)
