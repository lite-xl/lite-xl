lite_pluginsdir = join_paths(lite_datadir, 'plugins')

#===============================================================================
# thread plugin
#===============================================================================
shared_module(
    'thread',
    ['thread/thread.c', 'thread/channel.c'],
    name_prefix: '',
    include_directories: lite_includes + [include_directories('thread')],
    dependencies: lite_deps,
    c_args: lite_cargs,
    objc_args: lite_cargs,
    link_args: lite_link_args,
    install: true,
    install_dir: lite_pluginsdir
)
