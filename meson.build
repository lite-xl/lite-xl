project('lite-xl',
    ['c', 'cpp'],
    version : '2.0.0',
    license : 'MIT',
    meson_version : '>= 0.54',
    default_options : ['c_std=gnu11', 'cpp_std=c++03']
)
# TODO: the project version could be automatically generated from git with:
#   version : run_command('bash', 'scripts/version.sh').stdout(),

#===============================================================================
# Configuration
#===============================================================================
conf_data = configuration_data()
conf_data.set('PROJECT_BUILD_DIR', meson.current_build_dir())
conf_data.set('PROJECT_SOURCE_DIR', meson.current_source_dir())
conf_data.set('PROJECT_VERSION', meson.project_version())

configure_file(
    input : 'scripts/start.lua.in',
    output : 'start.lua',
    configuration : conf_data
)
if host_machine.system() == 'windows'
    configure_file(
        input : 'scripts/innosetup/innosetup.iss.in',
        output : 'innosetup.iss',
        configuration : conf_data
    )
endif
#===============================================================================
# Compiler Settings
#===============================================================================
if host_machine.system() == 'darwin'
    add_languages('objc')
endif

cc = meson.get_compiler('c')

lite_cargs = []
# On macos we need to use the SDL renderer to support retina displays
if get_option('renderer') or host_machine.system() == 'darwin'
    lite_cargs += '-DLITE_USE_SDL_RENDERER'
endif
#===============================================================================
# Linker Settings
#===============================================================================
lite_link_args = []
if cc.get_id() == 'gcc' and get_option('buildtype') == 'release'
    lite_link_args += ['-static-libgcc', '-static-libstdc++']
endif

if host_machine.system() == 'darwin'
    lite_link_args += ['-framework', 'CoreServices', '-framework', 'Foundation']
endif
#===============================================================================
# Dependencies
#===============================================================================
libm = cc.find_library('m', required : false)
libdl = cc.find_library('dl', required : false)
libx11 = dependency('x11', required : false)
lua_dep = dependency('lua5.2', required : false)
pcre2_dep = dependency('libpcre2-8')
sdl_dep = dependency('sdl2', method: 'config-tool')

if not lua_dep.found()
    lua_subproject = subproject('lua',
        default_options: ['shared=false', 'use_readline=false', 'app=false']
    )
    lua_dep = lua_subproject.get_variable('lua_dep')
endif

reproc_subproject = subproject('reproc',
    default_options: [
        'default_library=static', 'multithreaded=false',
        'reproc-cpp=false', 'examples=false'
    ]
)
reproc_dep = reproc_subproject.get_variable('reproc_dep')

lite_deps = [lua_dep, sdl_dep, reproc_dep, pcre2_dep, libm, libdl, libx11]

if host_machine.system() == 'windows'
    # Note that we need to explicitly add the windows socket DLL because
    # the pkg-config file from reproc does not include it.
    lite_deps += meson.get_compiler('cpp').find_library('ws2_32', required: true)
endif
#===============================================================================
# Install Configuration
#===============================================================================
if get_option('portable') or host_machine.system() == 'windows'
    lite_bindir = '/'
    lite_docdir = '/doc'
    lite_datadir = '/data'
elif host_machine.system() == 'darwin'
    lite_bindir = 'Contents/MacOS'
    lite_docdir = 'Contents/Resources'
    lite_datadir = 'Contents/Resources'
    install_data('resources/icons/icon.icns', install_dir : 'Contents/Resources')
    install_data('resources/macos/Info.plist', install_dir : 'Contents')
else
    lite_bindir = 'bin'
    lite_docdir = 'share/doc/lite-xl'
    lite_datadir = 'share/lite-xl'
    if host_machine.system() == 'linux'
        install_data('resources/icons/lite-xl.svg',
            install_dir : 'share/icons/hicolor/scalable/apps'
        )
        install_data('resources/linux/org.lite-xl.lite-xl.desktop',
            install_dir : 'share/applications'
        )
        install_data('resources/linux/org.lite-xl.lite-xl.appdata.xml',
            install_dir : 'share/metainfo'
        )
    endif
endif

install_data('licenses/licenses.md', install_dir : lite_docdir)

foreach data_module : ['core', 'fonts', 'plugins', 'colors']
    install_subdir('data' / data_module , install_dir : lite_datadir)
endforeach

install_data(
    meson.current_build_dir() / 'start.lua', install_dir : lite_datadir / 'core'
)
#===============================================================================
# Targets
#===============================================================================
subdir('lib/font_renderer')
subdir('src')
