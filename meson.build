project('lite', 'c', 'cpp', version: '1.06', default_options : ['c_std=gnu11', 'cpp_std=c++03'])

cc = meson.get_compiler('c')
libm = cc.find_library('m', required : false)
libdl = cc.find_library('dl', required : false)

lua_dep = dependency('lua', version: ['>=5.2.0', '<5.3.0'])
sdl_dep = dependency('sdl2', method: 'config-tool')

lite_include = include_directories('src')
install_subdir('data', install_dir : 'bin')

lite_link_args = []
if get_option('buildtype') == 'release'
  lite_link_args += ['-static-libgcc', '-static-libstdc++']
endif

lite_rc = []
if host_machine.system() == 'windows'
    windows = import('windows')
    lite_rc += windows.compile_resources('res.rc')
endif

subdir('lib/font_renderer')
subdir('src')

