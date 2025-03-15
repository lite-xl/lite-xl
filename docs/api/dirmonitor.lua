---@meta

---
---Functionality that allows to monitor a directory or file for changes
---using the native facilities provided by the current operating system
---for better efficiency and performance.
---@class dirmonitor
dirmonitor = {}

---@alias dirmonitor.callback fun(fd_or_path:integer|string)

---
---Creates a new dirmonitor object.
---
---@return dirmonitor
function dirmonitor.new() end

---
---Monitors a directory or file for changes.
---
---In "multiple" mode you will need to call this method more than once to
---recursively monitor directories and files.
---
---In "single" mode you will only need to call this method for the parent
---directory and every sub directory and files will get automatically monitored.
---
---@param path string
---
---@return integer fd The file descriptor id assigned to the monitored path when
---the mode is "multiple", in "single" mode: 1 for success or -1 on failure.
function dirmonitor:watch(path) end

---
---Stops monitoring a file descriptor in "multiple" mode
---or in "single" mode a directory path.
---
---@param fd_or_path integer | string A file descriptor or path.
function dirmonitor:unwatch(fd_or_path) end

---
---Verify if the resources registered for monitoring have changed, should
---be called periodically to check for changes.
---
---The callback will be called for each file or directory that was:
---edited, removed or added. A file descriptor will be passed to the
---callback in "multiple" mode or a path in "single" mode.
---
---If an error occurred during the callback execution, the error callback will be called with the error object.
---This callback should not manipulate coroutines to avoid deadlocks.
---
---@param callback dirmonitor.callback
---@param error_callback fun(error: any): nil
---
---@return boolean? changes True when changes were detected.
function dirmonitor:check(callback, error_callback) end

---
---Get the working mode for the current file system monitoring backend.
---
---"multiple": various file descriptors are needed to recursively monitor a
---directory contents, backends: inotify and kqueue.
---
---"single": a single process takes care of monitoring a path recursively
---so no individual file descriptors are used, backends: win32 and fsevents.
---
---@return "single" | "multiple"
function dirmonitor:mode() end


return dirmonitor
