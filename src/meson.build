lite_sources = [
    'api/api.c',
    'api/cp_replace.c',
    'api/renderer.c',
    'api/renderer_font.c',
    'api/regex.c',
    'api/system.c',
    'renderer.c',
    'renwindow.c',
    'fontdesc.c',
    'rencache.c',
    'main.c',
]

if host_machine.system() == 'darwin'
    lite_sources += 'bundle_open.m'
endif

executable('lite',
    lite_sources + lite_rc,
    include_directories: [lite_include, font_renderer_include],
    dependencies: [lua_dep, sdl_dep, pcre2_dep, libm, libdl, libx11],
    c_args: lite_cargs,
    link_with: libfontrenderer,
    link_args: lite_link_args,
    install: true,
    gui_app: true,
)

