project('lite', 'c', version: '1.05', default_options : ['c_std=gnu11'])

cc = meson.get_compiler('c')
libm = cc.find_library('m', required : false)
libdl = cc.find_library('dl', required : false)

lua_dep = dependency('lua')
sdl_dep = dependency('sdl2', method: 'config-tool')
stb_truetype_dep = dependency('stb_truetype')

lite_include = include_directories('src')
install_subdir('data', install_dir : 'bin')

subdir('src')
