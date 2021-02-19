project('lite', 'c', 'cpp', version: '1.0', default_options : ['c_std=gnu11', 'cpp_std=c++03'])

cc = meson.get_compiler('c')
libm = cc.find_library('m', required : false)
libdl = cc.find_library('dl', required : false)
lua_dep = dependency('lua5.2', required : false)

if not lua_dep.found()
    lua_subproject = subproject('lua', default_options: [
        'shared=disabled', 'use_readline=false'
    ])
    lua_dep = lua_subproject.get_variable('lua_dep')
endif

sdl_dep = dependency('sdl2', method: 'config-tool')

lite_cargs = []
if get_option('portable')
    lite_cargs += ['-DLITE_XL_DATA_USE_EXEDIR']
    lite_datadir = 'data'
else
    lite_datadir = 'share/lite-xl'
endif

lite_include = include_directories('src')
foreach data_module : ['core', 'fonts', 'plugins', 'colors']
    install_subdir('data' / data_module , install_dir : lite_datadir)
endforeach

lite_link_args = []
if cc.get_id() == 'gcc' and get_option('buildtype') == 'release'
    lite_link_args += ['-static-libgcc', '-static-libstdc++']
endif

lite_rc = []
if host_machine.system() == 'windows'
    windows = import('windows')
    lite_rc += windows.compile_resources('res.rc')
endif

subdir('lib/font_renderer')
subdir('src')

