project('lite-xl',
    ['c'],
    version : '2.1.7',
    license : 'MIT',
    meson_version : '>= 0.63',
    default_options : [
        'c_std=gnu11'
    ]
)

#===============================================================================
# Project version including git commit if possible
#===============================================================================
version = meson.project_version()

if get_option('buildtype') != 'release'
    git_command = find_program('git', required : false)

    if git_command.found()
        git_commit = run_command(
            [git_command, 'rev-parse', 'HEAD'],
            check : false
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
conf_data.set('PROJECT_ASSEMBLY_VERSION', meson.project_version() + '.0')

#===============================================================================
# Compiler Settings
#===============================================================================
cc = meson.get_compiler('c')

lite_includes = []
lite_cargs = [
    '-DPCRE2_STATIC',
    '-DLITE_PROJECT_VERSION_STR="@0@"'.format(version)
]
# On macos we need to use the SDL renderer to support retina displays
if get_option('renderer') or host_machine.system() == 'darwin'
    lite_cargs += '-DLITE_USE_SDL_RENDERER'
endif
if get_option('arch_tuple') != ''
    arch_tuple = get_option('arch_tuple')
else
    arch_tuple = '@0@-@1@'.format(target_machine.cpu_family(), target_machine.system())
endif
lite_cargs += '-DLITE_ARCH_TUPLE="@0@"'.format(arch_tuple)

#===============================================================================
# Linker Settings
#===============================================================================
lite_link_args = []
if host_machine.system() == 'darwin'
    lite_link_args += ['-framework', 'CoreServices', '-framework', 'Foundation']
endif
#===============================================================================
# Install Configuration
#===============================================================================
if get_option('portable') or host_machine.system() == 'windows'
    lite_bindir = '/'
    lite_docdir = '/doc'
    lite_datadir = '/data'
    lpm_userdir = 'data'
    lpm_install_dir = '/'
    configure_file(
        input: 'resources' / 'windows' / 'lite-xl.exe.manifest.in',
        output: 'lite-xl.exe.manifest',
        configuration: conf_data
    )
elif get_option('bundle') and host_machine.system() == 'darwin'
    lite_cargs += '-DMACOS_USE_BUNDLE'
    lite_bindir = 'Contents' / 'MacOS'
    lite_docdir = 'Contents' / 'Resources'
    lite_datadir = 'Contents' / 'Resources'
    lpm_userdir = 'Resources'
    lpm_install_dir = 'Contents'
    conf_data.set(
        'CURRENT_YEAR',
        run_command('date', '+%Y', capture: true).stdout().strip()
    )
    install_data('resources' / 'icons' / 'icon.icns', install_dir : 'Contents' / 'Resources')
    configure_file(
        input : 'resources' / 'macos' / 'Info.plist.in',
        output : 'Info.plist',
        configuration : conf_data,
        install : true,
        install_dir : 'Contents'
    )
else
    lite_bindir = 'bin'
    lite_docdir = get_option('datadir') / 'doc' / 'lite-xl'
    lite_datadir = get_option('datadir') / 'lite-xl'
    lpm_userdir = 'lite-xl'
    lpm_install_dir = get_option('datadir')
    if host_machine.system() == 'linux'
        git_command = find_program('git', required : false)

        if git_command.found()
            git_tags = run_command(
                [git_command, 'tag', '-l', '--sort=-version:refname', '--format=%(refname:strip=2) %(creatordate:short)'],
                check : false
            ).stdout().split('\n')

            releases = []

            foreach tag : git_tags
                taga = tag.split(' ')
                if taga.length() != 2
                    continue
                endif

                ref = taga[0]
                date = taga[1]
                if not ref.startswith('v') or ref.contains('-')
                    continue
                endif

                if ref.startswith('v1.0')
                    # releases 1.01 to 1.09 used an invalid versioning scheme so we ignore them
                    continue
                endif

                releases += '<release version="@0@" date="@1@" />'.format(ref, date)
            endforeach

            releases_tag = ''
            if releases.length() > 0
                releases_tag = '<releases>\n@0@\n</releases>'.format('\n'.join(releases))
            endif

            conf_data.set('METAINFO_RELEASES', releases_tag)
        else
            conf_data.set('METAINFO_RELEASES', '')
        endif

        install_data('resources' / 'icons' / 'lite-xl.svg',
            install_dir : get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
        )
        install_data('resources' / 'linux' / 'com.lite_xl.LiteXL.desktop',
            install_dir : get_option('datadir') / 'applications'
        )
        configure_file(
            input : 'resources' / 'linux' / 'com.lite_xl.LiteXL.metainfo.xml.in',
            output : 'com.lite_xl.LiteXL.metainfo.xml',
            configuration : conf_data,
            install : true,
            install_dir : 'share/metainfo'
        )
    endif
endif

install_data('licenses' / 'licenses.md', install_dir : lite_docdir)

install_subdir('docs' / 'api' , install_dir : lite_datadir, strip_directory: true)
install_subdir('data' / 'core' , install_dir : lite_datadir, exclude_files : 'start.lua')
foreach data_module : ['fonts', 'plugins', 'colors']
    install_subdir(join_paths('data', data_module), install_dir : lite_datadir)
endforeach

configure_file(
    input : 'data' / 'core' / 'start.lua',
    output : 'start.lua',
    configuration : conf_data,
    install_dir : join_paths(lite_datadir, 'core'),
)

if not get_option('source-only')
    subdir('src')
    subdir('scripts')
    subdir('data')
endif
