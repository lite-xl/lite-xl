project('luajit', 'c', version : '2.1.0')

make_command = find_program('make', required : true)

build_command = [make_command, 'amalg']

if host_machine.system() == 'darwin'
    build_command += 'MACOSX_DEPLOYMENT_TARGET=10.11'
endif

build_command += [
    'CFLAGS=-fPIC',
    'XCFLAGS=-DLUAJIT_ENABLE_LUA52COMPAT',
    'BUILDMODE=static', '-l', '90', '-j'
]

run_command(build_command, check : true)

cc = meson.get_compiler('c')

luajit = cc.find_library('luajit',
    dirs : [ meson.current_source_dir() + '/src'],
    required : true,
    static : true
)

luajit_dep = declare_dependency(
    dependencies: luajit,
    include_directories: include_directories('src')
)
