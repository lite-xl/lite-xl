executable('stb-font-render-test',
    'stb_font_render_test.c',
    include_directories: lite_include,
    dependencies: [sdl_dep, stb_truetype_dep, libm, libdl],
    install: false,
)

executable('agg-font-render-test',
    ['../src/agg_font_freetype.cpp', '../src/font_renderer.cpp', 'agg_font_render_test.c'],
    include_directories: lite_include,
    cpp_args: renderer_cdefs,
    dependencies: [sdl_dep, libagg_dep, freetype_dep, libm, libdl],
    install: false,
)
