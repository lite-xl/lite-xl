lite_sources = [
    'api/api.c',
    'api/cp_replace.c',
    'api/renderer.c',
    'api/renderer_font.c',
    'api/system.c',
    'renderer.c',
    'rencache.c',
    'xrdb_parse.c',
    'main.c',
]

executable('lite',
    lite_sources + lite_rc,
    include_directories: [lite_include, font_renderer_include],
    dependencies: [lua_dep, sdl_dep, libm, libdl],
    c_args: lite_cargs,
    link_with: libfontrenderer,
    link_args: lite_link_args,
    install: true,
    gui_app: true,
)

