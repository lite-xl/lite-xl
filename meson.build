project('lite', 'c', 'cpp', default_options : ['c_std=gnu11', 'cpp_std=c++03'])

if host_machine.system() == 'darwin'
    add_languages('objc')
endif

cc = meson.get_compiler('c')
libm = cc.find_library('m', required : false)
libdl = cc.find_library('dl', required : false)
libx11 = dependency('x11', required : false)
lua_dep = dependency('lua5.2', required : false)
pcre2_dep = dependency('libpcre2', required : false)

if not lua_dep.found()
    lua_subproject = subproject('lua', default_options: ['shared=false', 'use_readline=false', 'app=false'])
    lua_dep = lua_subproject.get_variable('lua_dep')
endif

sdl_dep = dependency('sdl2', method: 'config-tool')

lite_cargs = []
if get_option('portable')
    lite_docdir = 'doc'
    lite_datadir = 'data'
else
    lite_docdir = 'share/doc'
    lite_datadir = 'share/lite-xl'
endif

lite_include = include_directories('src')
foreach data_module : ['core', 'fonts', 'plugins', 'colors']
    install_subdir('data' / data_module , install_dir : lite_datadir)
endforeach

foreach file : ['usage.md', 'licenses.md', 'contributors.md', 'default-keymap.md']
    install_data('doc' / file, install_dir : lite_docdir)
endforeach

lite_link_args = []
if cc.get_id() == 'gcc' and get_option('buildtype') == 'release'
    lite_link_args += ['-static-libgcc', '-static-libstdc++']
endif
if host_machine.system() == 'darwin'
    lite_link_args += ['-framework', 'CoreServices', '-framework', 'Foundation']
endif

lite_rc = []
if host_machine.system() == 'windows'
    windows = import('windows')
    lite_rc += windows.compile_resources('res.rc')
endif

# On macos we need to use the SDL renderer to support retina displays
if get_option('renderer') or host_machine.system() == 'darwin'
    lite_cargs += '-DLITE_USE_SDL_RENDERER'
endif

subdir('lib/font_renderer')
subdir('src')

