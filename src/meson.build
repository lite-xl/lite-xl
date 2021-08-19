lite_sources = [
    'api/api.c',
    'api/cp_replace.c',
    'api/renderer.c',
    'api/renderer_font.c',
    'api/regex.c',
    'api/system.c',
    'api/process.c',
    'renderer.c',
    'renwindow.c',
    'fontdesc.c',
    'rencache.c',
    'main.c',
]

lite_rc = []
if host_machine.system() == 'windows'
    windows = import('windows')
    lite_rc += windows.compile_resources('../resources/icons/icon.rc')
elif host_machine.system() == 'darwin'
    lite_sources += 'bundle_open.m'
endif

lite_include = include_directories('.')

executable('lite-xl',
    lite_sources + lite_rc,
    include_directories: [lite_include, font_renderer_include],
    dependencies: lite_deps,
    c_args: lite_cargs,
    objc_args: lite_cargs,
    link_with: libfontrenderer,
    link_args: lite_link_args,
    install_dir: lite_bindir,
    install: true,
    gui_app: true,
)
