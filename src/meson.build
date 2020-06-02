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

lite_cdefs += ['-DFONT_RENDERER_HEIGHT_HACK']

executable('lite',
    lite_sources,
    include_directories: lite_include,
    dependencies: [lua_dep, sdl_dep, libagg_dep, freetype_dep, libm, libdl],
    link_args: lite_link_args,
    cpp_args: lite_cdefs,
    install: true,
    gui_app: true,
)
