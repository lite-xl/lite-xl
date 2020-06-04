executable('stb-font-render-test',
    'stb_font_render_test.c',
    include_directories: lite_include,
    dependencies: [sdl_dep, stb_truetype_dep, libm, libdl],
    install: false,
)

executable('agg-font-render-test',
    'agg_font_render_test.c',
    include_directories: [lite_include, font_renderer_include],
    dependencies: [sdl_dep, libm, libdl],
    link_with: libfontrenderer,
    install: false,
)
