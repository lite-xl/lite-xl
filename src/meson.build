lite_sources = [
    'api/api.c',
    'api/dirmonitor.c',
    'api/renderer.c',
    'api/renwindow.c',
    'api/regex.c',
    'api/system.c',
    'api/process.c',
    'api/utf8.c',
    'arena_allocator.c',
    'renderer.c',
    'renwindow.c',
    'rencache.c',
    'main.c',
]

# dirmonitor backend
dirmonitor_backends = get_option('dirmonitor_backends')

if dirmonitor_backends.length() == 0
    if cc.has_function('inotify_init', prefix : '#include<sys/inotify.h>')
        dirmonitor_backends += 'inotify'
    endif
    if host_machine.system() == 'darwin' and cc.check_header('CoreServices/CoreServices.h')
        dirmonitor_backends += 'fsevents'
    endif

    if cc.has_function('kqueue', prefix : '#include<sys/event.h>')
        dirmonitor_backends += 'kqueue'
    endif

    if cc.has_function('create_inode_watcher', prefix : '#include<fcntl.h>')
        dirmonitor_backends += 'inodewatcher'
    endif

    if dependency('libkqueue', required : false).found()
        dirmonitor_backends += 'kqueue'
    endif

    if host_machine.system() == 'windows'
        dirmonitor_backends += 'win32'
    endif

    dirmonitor_backends += 'dummy'
endif

foreach backend : dirmonitor_backends
    if backend == 'inotify'
        lite_sources += 'api' / 'dirmonitor' / 'inotify.c'
        lite_cargs += '-DDIRMONITOR_INOTIFY'
    elif backend == 'fsevents'
        lite_sources += 'api' / 'dirmonitor' / 'fsevents.c'
        lite_cargs += '-DDIRMONITOR_FSEVENTS'
    elif backend == 'kqueue'
        lite_sources += 'api' / 'dirmonitor' / 'kqueue.c'
        libkqueue_dep = dependency('libkqueue', required : false)
        if libkqueue_dep.found()
            lite_deps += libkqueue_dep
        endif
        lite_cargs += '-DDIRMONITOR_KQUEUE'
    elif backend == 'inodewatcher'
        add_languages('cpp')
        lite_sources += 'api' / 'dirmonitor' / 'inodewatcher.cpp'
        lite_cargs += '-DDIRMONITOR_INODEWATCHER'
    elif backend == 'win32'
        lite_sources += 'api' / 'dirmonitor' / 'win32.c'
        lite_cargs += '-DDIRMONITOR_WIN32'
    elif backend == 'dummy'
        lite_sources += 'api' / 'dirmonitor' / 'dummy.c'
        lite_cargs += '-DDIRMONITOR_DUMMY'
    else
        error('Unknown dirmonitor backend @0@'.format(backend))
    endif
endforeach

summary('dirmonitor backends', dirmonitor_backends)

lite_rc = []
if host_machine.system() == 'windows'
    windows = import('windows')
    lite_rc += windows.compile_resources('..' / 'resources' / 'icons' / 'icon.rc')
    lite_rc += windows.compile_resources('..' / 'resources' / 'windows' / 'manifest.rc')
elif host_machine.system() == 'darwin'
    lite_sources += 'bundle_open.m'
endif

lite_includes += include_directories('.')

executable('lite-xl',
    lite_sources + lite_rc,
    include_directories: lite_includes,
    dependencies: lite_deps,
    c_args: lite_cargs,
    objc_args: lite_cargs,
    link_args: lite_link_args,
    install_dir: lite_bindir,
    install: true,
    win_subsystem: 'windows',
)
