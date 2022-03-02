project('lite-xl',
    ['c'],
    version : '2.0.5',
    license : 'MIT',
    meson_version : '>= 0.42',
    default_options : [
        'c_std=gnu11',
        'wrap_mode=nofallback'
    ]
)

#===============================================================================
# Project version including git commit if possible
#===============================================================================
version = meson.project_version()

if get_option('buildtype') != 'release'
    git_command = find_program('git', required : false)

    if git_command.found()
        git_branch = run_command(
            [git_command, 'branch', '--show-current']
        ).stdout().strip()
        git_commit = run_command(
            [git_command, 'rev-parse', git_branch]
        ).stdout().strip()

        if git_commit != ''
            version += ' (git-' + git_commit.substring(0, 8) + ')'
        endif
    endif
endif

#===============================================================================
# Configuration
#===============================================================================
conf_data = configuration_data()
conf_data.set('PROJECT_BUILD_DIR', meson.current_build_dir())
conf_data.set('PROJECT_SOURCE_DIR', meson.current_source_dir())
conf_data.set('PROJECT_VERSION', version)

#===============================================================================
# Compiler Settings
#===============================================================================
if host_machine.system() == 'darwin'
    add_languages('objc')
endif

cc = meson.get_compiler('c')

lite_includes = []
lite_cargs = ['-DSDL_MAIN_HANDLED', '-DPCRE2_STATIC']
# On macos we need to use the SDL renderer to support retina displays
if get_option('renderer') or host_machine.system() == 'darwin'
    lite_cargs += '-DLITE_USE_SDL_RENDERER'
endif
#===============================================================================
# Linker Settings
#===============================================================================
lite_link_args = []
if cc.get_id() == 'gcc' and get_option('buildtype') == 'release'
    lite_link_args += ['-static-libgcc']
endif

if host_machine.system() == 'darwin'
    lite_link_args += ['-framework', 'CoreServices', '-framework', 'Foundation']
endif
#===============================================================================
# Dependencies
#===============================================================================
if not get_option('source-only')
    libm = cc.find_library('m', required : false)
    libdl = cc.find_library('dl', required : false)
    threads_dep = dependency('threads')


    lua_fallback = ['lua', 'lua_dep']
    lua_quick_fallback = []
    if get_option('wrap_mode') == 'forcefallback'
        lua_quick_fallback = lua_fallback
    endif

    lua_dep = dependency('lua5.4', fallback: lua_quick_fallback, required : false)
    if not lua_dep.found()
        lua_dep = dependency('lua', fallback: ['lua', 'lua_dep'],
            default_options: ['default_library=static', 'line_editing=false', 'interpreter=false']
        )
    endif

    pcre2_dep = dependency('libpcre2-8', fallback: ['pcre2', 'libpcre2_8'],
        default_options: ['default_library=static', 'grep=false', 'test=false']
    )

    freetype_dep = dependency('freetype2', fallback: ['freetype2', 'freetype_dep'],
        default_options: ['default_library=static', 'zlib=disabled', 'bzip2=disabled', 'png=disabled', 'harfbuzz=disabled', 'brotli=disabled']
    )

    sdl_dep = dependency('sdl2', fallback: ['sdl2', 'sdl2_dep'],
        default_options: ['default_library=static']
    )

    lite_deps = [lua_dep, sdl_dep, freetype_dep, pcre2_dep, libm, libdl, threads_dep]
endif
#===============================================================================
# Install Configuration
#===============================================================================
if get_option('portable') or host_machine.system() == 'windows'
    lite_bindir = '/'
    lite_docdir = '/doc'
    lite_datadir = '/data'
elif get_option('bundle') and host_machine.system() == 'darwin'
    lite_cargs += '-DMACOS_USE_BUNDLE'
    lite_bindir = 'Contents/MacOS'
    lite_docdir = 'Contents/Resources'
    lite_datadir = 'Contents/Resources'
    install_data('resources/icons/icon.icns', install_dir : 'Contents/Resources')
    configure_file(
        input : 'resources/macos/Info.plist.in',
        output : 'Info.plist',
        configuration : conf_data,
        install : true,
        install_dir : 'Contents'
    )
else
    lite_bindir = 'bin'
    lite_docdir = 'share/doc/lite-xl'
    lite_datadir = 'share/lite-xl'
    if host_machine.system() == 'linux'
        install_data('resources/icons/lite-xl.svg',
            install_dir : 'share/icons/hicolor/scalable/apps'
        )
        install_data('resources/linux/org.lite_xl.lite_xl.desktop',
            install_dir : 'share/applications'
        )
        install_data('resources/linux/org.lite_xl.lite_xl.appdata.xml',
            install_dir : 'share/metainfo'
        )
    endif
endif

install_data('licenses/licenses.md', install_dir : lite_docdir)

install_subdir('data/core' , install_dir : lite_datadir, exclude_files : 'start.lua')
foreach data_module : ['fonts', 'plugins', 'colors']
    install_subdir(join_paths('data', data_module), install_dir : lite_datadir)
endforeach

configure_file(
    input : 'data/core/start.lua',
    output : 'start.lua',
    configuration : conf_data,
    install_dir : join_paths(lite_datadir, 'core'),
)

if not get_option('source-only')
    subdir('lib/dmon')
    subdir('src')
    subdir('scripts')
endif
