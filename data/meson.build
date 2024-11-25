if get_option('bundle_plugins').length() > 0
    lpm_exe = find_program('lpm')
    plugin_bundle = custom_target(
        'lpm_plugins',
        input: 'meson.build',
        output: [lpm_userdir, 'lpm_cache'],
        command: [
            lpm_exe,
            '--datadir', meson.project_source_root() / 'data',
            '--userdir', '@OUTPUT0@',
            '--cachedir', '@OUTPUT1@',
            '--assume-yes',
            'install',
            get_option('bundle_plugins'),
        ],
        install: true,
        install_dir: [lpm_install_dir, false],
        build_by_default: true,
    )
endif
