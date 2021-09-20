## from core/init.lua

- scan_project_folder set the watch_id recursively or not
  * called from core.add_project_directory

## from treeview.lua

TreeView:on_mouse_pressed
  * calls core.scan_project_subdir only in files_limit mode
  * calls core.project_subdir_set_show
