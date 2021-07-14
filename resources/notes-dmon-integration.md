`core.scan_project_folder`:
    scan a single folder, without recursion. Used when too many files.


`core.add_project_directory`:
    Add a new top-level folder to the project.

`core.set_project_dir`:
    Set the initial project directory.



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

