project('lite', 'c', 'cpp', version: '1.05', default_options : ['c_std=gnu11', 'cpp_std=c++03'])

cc = meson.get_compiler('c')
libm = cc.find_library('m', required : false)
libdl = cc.find_library('dl', required : false)

lua_dep = dependency('lua')
sdl_dep = dependency('sdl2', method: 'config-tool')
libagg_dep = dependency('libagg')
freetype_dep = dependency('freetype2')
stb_truetype_dep = dependency('stb_truetype')

lite_include = include_directories('src')
install_subdir('data', install_dir : 'bin')

lite_cdefs = []
lite_link_args = []
if get_option('buildtype') == 'release'
  lite_link_args += ['-static-libgcc', '-static-libstdc++']
endif

lite_rc = []
if host_machine.system() == 'windows'
    windows = import('windows')
    lite_rc += windows.compile_resources('res.rc')
endif

subdir('src')
subdir('tests')
