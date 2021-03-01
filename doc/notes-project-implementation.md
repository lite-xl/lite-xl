
`core.project_directories` => `core.project_entries`
- use a new `type` field to indicate it is a directory or a file


`core.{project_dir,project_files}` => removed
`core.set_project_dir` => removed

`core.on_enter_project` => decide what to do

No longer use `chdir` command.

## New functions

`core.add_project_file`

## Modified functions

- `core.add_project_directory`
- `project_files_iter` local function in `core/init.lua`

Function `remove_project_directory` is renamed to `remove_project_entry`.

## Broken

workspace plugin is not working for the moment.
Number of files show in statusview.

## To be done

- When using "core:find-file" do not display the full path of the file
- FIX the workspace plugin
- FIX number of files display in statusview
- Add a function to add a file into the project
- Add logic to do not show treeview if it contains only a single file
- Modify "core:open-file" to accept a directory
- Modify "core:open-file" to accept a non-existing file name (new file)

## Misc observations

When performing adding directory, pressing enter does not use the item => to be fixed.
The function `system.chdir` is no longer used and could be removed, in theory.
