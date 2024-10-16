project(
  'lua-5.4',
  'c',
  license: 'MIT',
  meson_version: '>=0.49.2',
  version: '5.4.6',
  default_options: ['c_std=c99', 'warning_level=2'],
)

lua_versions = meson.project_version().split('.')
cc = meson.get_compiler('c')

# Skip bogus warning.
add_project_arguments(cc.get_supported_arguments('-Wno-string-plus-int', '-Wno-stringop-overflow'), language: 'c')

# Platform-specific defines.
is_posix = host_machine.system() not in ['windows', 'emscripten', 'android']
if is_posix
  add_project_arguments('-DLUA_USE_POSIX', language: 'c')
elif get_option('default_library') != 'static' and host_machine.system() == 'windows'
  add_project_arguments('-DLUA_BUILD_AS_DLL', language: 'c')
endif

# Library dependencies.
lua_lib_deps = [cc.find_library('m', required: false)]

if meson.version().version_compare('>= 0.62')
  dl_dep = dependency('dl', required: get_option('loadlib'))
else
  dl_dep = cc.find_library('dl', required: get_option('loadlib'))
endif

if dl_dep.found()
  lua_lib_deps += dl_dep
  add_project_arguments('-DLUA_USE_DLOPEN', language: 'c')
endif

# Interpreter dependencies.
lua_exe_deps = []
lua_exe_args = []

readline_dep = dependency('readline', required: get_option('line_editing'))
if readline_dep.found()
  lua_exe_deps += readline_dep
  lua_exe_args += '-DLUA_USE_READLINE'
else
  readline_dep = dependency('libedit', required: get_option('line_editing'))
endif

# Targets.
lua_lib = library(
  'lua',
  'src/lapi.c',
  'src/lauxlib.c',
  'src/lbaselib.c',
  'src/lcode.c',
  'src/lcorolib.c',
  'src/lctype.c',
  'src/ldblib.c',
  'src/ldebug.c',
  'src/ldo.c',
  'src/ldump.c',
  'src/lfunc.c',
  'src/lgc.c',
  'src/linit.c',
  'src/liolib.c',
  'src/llex.c',
  'src/lmathlib.c',
  'src/lmem.c',
  'src/loadlib.c',
  'src/lobject.c',
  'src/lopcodes.c',
  'src/loslib.c',
  'src/lparser.c',
  'src/lstate.c',
  'src/lstring.c',
  'src/lstrlib.c',
  'src/ltable.c',
  'src/ltablib.c',
  'src/ltm.c',
  'src/lundump.c',
  'src/lutf8lib.c',
  'src/lvm.c',
  'src/lzio.c',
  'src/utf8_wrappers.c',
  dependencies: lua_lib_deps,
  version: meson.project_version(),
  soversion: lua_versions[0] + '.' + lua_versions[1],
  implicit_include_directories: false,
  install: true,
)

inc = include_directories('src')
lua_dep = declare_dependency(
  link_with: lua_lib,
  include_directories: inc,
)

if get_option('interpreter')
  lua_exe = executable(
    'lua',
    'src/lua.c',
    c_args: lua_exe_args,
    dependencies: [lua_dep, lua_exe_deps],
    export_dynamic: dl_dep.found(),
    implicit_include_directories: false,
  )

  if get_option('default_library') == 'static'
    luac_exe = executable(
      'luac',
      'src/luac.c',
      dependencies: lua_dep,
      implicit_include_directories: false,
    )
  endif
endif
