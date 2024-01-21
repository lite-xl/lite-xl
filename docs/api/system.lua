---@meta

---
---Utilites for managing current window, files and more.
---@class system
system = {}

---@alias system.fileinfotype
---| "file"  # It is a file.
---| "dir"   # It is a directory.

---
---@class system.fileinfo
---@field public modified number A timestamp in seconds.
---@field public size number Size in bytes.
---@field public type system.fileinfotype Type of file
---@field public symlink boolean The directory is a symlink. This field is only set on Linux and on directories.

---
---Core function used to retrieve the current event been triggered by SDL.
---
---The following is a list of event types emitted by this function and
---the arguments for each of them if applicable.
---
---Window events:
--- * "quit"
--- * "resized" -> width, height (in points)
--- * "exposed"
--- * "minimized"
--- * "maximized"
--- * "restored"
--- * "focuslost"
---
---File events:
--- * "filedropped" -> filename, x, y
---
---Keyboard events:
--- * "keypressed" -> key_name
--- * "keyreleased" -> key_name
--- * "textinput" -> text
--- * "textediting" -> text, start, length
---
---Mouse events:
--- * "mousepressed" -> button_name, x, y, amount_of_clicks
--- * "mousereleased" -> button_name, x, y
--- * "mousemoved" -> x, y, relative_x, relative_y
--- * "mousewheel" -> y, x
---
---Touch events:
--- * "touchpressed" -> x, y, finger_id
--- * "touchreleased" -> x, y, finger_id
--- * "touchmoved" -> x, y, distance_x, distance_y, finger_id
---
---@return string type
---@return any? arg1
---@return any? arg2
---@return any? arg3
---@return any? arg4
function system.poll_event() end

---
---Wait until an event is triggered.
---
---@param timeout? number Amount of seconds, also supports fractions
---of a second, eg: 0.01. If not provided, waits forever.
---
---@return boolean status True on success or false if there was an error or if no event was received.
function system.wait_event(timeout) end

---
---Change the cursor type displayed on screen.
---
---@param type string | "arrow" | "ibeam" | "sizeh" | "sizev" | "hand"
function system.set_cursor(type) end

---
---Change the window title.
---
---@param title string
function system.set_window_title(title) end

---@alias system.windowmode
---| "normal"
---| "minimized"
---| "maximized"
---| "fullscreen"

---
---Change the window mode.
---
---@param mode system.windowmode
function system.set_window_mode(mode) end

---
---Retrieve the current window mode.
---
---@return system.windowmode mode
function system.get_window_mode() end

---
---Toggle between bordered and borderless.
---
---@param bordered boolean
function system.set_window_bordered(bordered) end

---
---When then window is run borderless (without system decorations), this
---function allows to set the size of the different regions that allow
---for custom window management.
---To disable custom window management, call this function without any
---arguments
---
---@param title_height? number Height of the window decoration
---@param controls_width? number Width of window controls (maximize,minimize and close buttons, etc).
---@param resize_border? number The amount of pixels reserved for resizing
function system.set_window_hit_test(title_height, controls_width, resize_border) end

---
---Get the size and coordinates of the window.
---
---@return number width
---@return number height
---@return number x
---@return number y
function system.get_window_size() end

---
---Sets the size and coordinates of the window.
---
---@param width number
---@param height number
---@param x number
---@param y number
function system.set_window_size(width, height, x, y) end

---
---Check if the window currently has focus.
---
---@return boolean
function system.window_has_focus() end

---
---Gets the mode of the window.
---
---@return system.windowmode
function system.get_window_mode() end

---
---Sets the position of the IME composition window.
---
---@param x number
---@param y number
---@param width number
---@param height number
function system.set_text_input_rect(x, y, width, height) end

---
---Clears any ongoing composition on the IME
function system.clear_ime() end

---
---Raise the main window and give it input focus.
---Note: may not always be obeyed by the users window manager.
function system.raise_window() end

---
---Opens a message box to display an error message.
---
---@param title string
---@param message string
function system.show_fatal_error(title, message) end

---
---Deletes an empty directory.
---
---@param path string
---@return boolean success True if the operation suceeded, false otherwise
---@return string? message An error message if the operation failed
function system.rmdir(path) end

---
---Change the current directory path which affects relative file operations.
---This function raises an error if the path doesn't exists.
---
---@param path string
function system.chdir(path) end

---
---Create a new directory, note that this function doesn't recursively
---creates the directories on the given path.
---
---@param directory_path string
---
---@return boolean created True on success or false on failure.
---@return string? message The error message if the operation failed.
function system.mkdir(directory_path) end

---
---Gets a list of files and directories for a given path.
---
---@param path string
---
---@return table|nil list List of directories or nil if empty or error.
---@return string? message Error message in case of error.
function system.list_dir(path) end

---
---Converts a relative path from current directory to the absolute one.
---
---@param path string
---
---@return string? abspath
function system.absolute_path(path) end

---
---Get details about a given file or path.
---
---@param path string Can be a file or a directory path
---
---@return system.fileinfo|nil info Path details or nil if empty or error.
---@return string? message Error message in case of error.
function system.get_file_info(path) end


---@alias system.fstype
---| "ext2/ext3"
---| "nfs"
---| "fuse"
---| "smb"
---| "smb2"
---| "reiserfs"
---| "tmpfs"
---| "ramfs"
---| "ntfs"

---
---Gets the filesystem type of a path.
---Note: This only works on Linux.
---
---@param path string Can be path to a directory or a file
---
---@return system.fstype
function system.get_fs_type(path) end


---
---Retrieve the text currently stored on the clipboard.
---
---@return string
function system.get_clipboard() end

---
---Set the content of the clipboard.
---
---@param text string
function system.set_clipboard(text) end

---
---Get the process id of lite-xl itself.
---
---@return integer
function system.get_process_id() end

---
---Get amount of iterations since the application was launched
---also known as SDL_GetPerformanceCounter() / SDL_GetPerformanceFrequency()
---
---@return number
function system.get_time() end

---
---Sleep for the given amount of seconds.
---
---@param seconds number Also supports fractions of a second, eg: 0.01
function system.sleep(seconds) end

---
---Similar to os.execute() but does not return the exit status of the
---executed command and executes the process in a non blocking way by
---forking it to the background.
---Note: Do not use this function, use the Process API instead.
---
---@deprecated
---@param command string The command to execute.
function system.exec(command) end

---
---Generates a matching score depending on how well the value of the
---given needle compares to that of the value in the haystack.
---
---@param haystack string
---@param needle string
---@param file boolean Reverse the algorithm to prioritize the end
---of the haystack, eg: with a haystack "/my/path/to/file" and a needle
---"file", will get better score than with this option not set to true.
---
---@return integer score
function system.fuzzy_match(haystack, needle, file) end

---
---Change the opacity (also known as transparency) of the window.
---
---@param opacity number A value from 0.0 to 1.0, the lower the value
---the less visible the window will be.
---@return boolean success True if the operation suceeded.
function system.set_window_opacity(opacity) end

---
---Loads a lua native module using the default Lua API or lite-xl native plugin API.
---Note: Never use this function directly.
---
---@param name string the name of the module
---@param path string the path to the shared library file
---@return number nargs the return value of the entrypoint
function system.load_native_plugin(name, path) end

---
---Compares two paths in the order used by TreeView.
---
---@param path1 string
---@param type1 system.fileinfotype
---@param path2 string
---@param type2 system.fileinfotype
---@return boolean compare_result True if path1 < path2
function system.path_compare(path1, type1, path2, type2) end


return system
