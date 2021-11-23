
`core.set_project_dir`:
    Reset project directories and set its directory.
    It chdir into the directory, empty the `core.project_directories` and add
    the given directory.
    `core.add_project_directory`:
        Add a new top-level directory to the project.
        Also called from modules and commands outside core.init.
        local function `scan_project_folder`:
            Scan all files for a given top-level project directory.
            Can emit a warning about file limit.
            Called only from within core.init module.

`core.scan_project_subdir`: (before was named `core.scan_project_folder`)
    scan a single folder, without recursion. Used when too many files.

Local function `scan_project_folder`:
    Populate the project folder top directory. Done only once when the directory
    is added to the project.

`core.add_project_directory`:
    Add a new top-level folder to the project.

`core.set_project_dir`:
    Set the initial project directory.

`core.dir_rescan_add_job`:
    Add a job to rescan after an elapsed time a project's subdirectory to fix for any
    changes.

Local function `rescan_project_subdir`:
    Rescan a project's subdirectory, compare to the current version and patch the list if
    a difference is found.


`core.project_scan_thread`:
    Should disappear now that we use dmon.


`core.project_scan_topdir`:
    New function to scan a top level project folder.


`config.project_scan_rate`:
`core.project_scan_thread_id`:
`core.reschedule_project_scan`:
`core.project_files_limit`:
    A eliminer.

`core.get_project_files`:
    To be fixed. Use `find_project_files_co` for a single directory

In TreeView remove usage of self.last to detect new scan that changed the files list.

