local common = require "core.common"
local config = require "core.config"
local dirwatch = {}

function dirwatch:__index(idx)
  local value = rawget(self, idx)
  if value ~= nil then return value end
  return dirwatch[idx]
end

---A directory watcher.
---
---It can be used to watch changes in files and directories.
---The user repeatedly calls dirwatch:check() with a callback inside a coroutine.
---If a file or directory had changed, the callback is called with the corresponding file.
---@class core.dirwatch
---@field scanned { [string]: number } Stores the last modified time of paths.
---@field watched { [string]: boolean|number } Stores the paths that are being watched, and their unique fd.
---@field reverse_watched { [number]: string } Stores the paths mapped by their unique fd.
---@field monitor dirmonitor The dirmonitor instance associated with this watcher.
---@field single_watch_top string The first file that is being watched.
---@field single_watch_count number Number of files that are being watched.

---Creates a directory monitor.
---@return core.dirwatch
function dirwatch.new()
  local t = {
    scanned = {},
    watched = {},
    reverse_watched = {},
    monitor = dirmonitor.new(),
    single_watch_top = nil,
    single_watch_count = 0
  }
  setmetatable(t, dirwatch)
  return t
end


---Schedules a path for scanning.
---If a path points to a file, it is watched directly.
---Otherwise, the contents of the path are watched (non-recursively).
---@param path string
---@param  unwatch? boolean If true, remove this directory from the watch list.
function dirwatch:scan(path, unwatch)
  if unwatch == false then return self:unwatch(path) end
  self.scanned[path] = system.get_file_info(path).modified
end


---Watches a path.
---
---It is recommended to call this function on every subdirectory if the given path
---points to a directory. This is not required for Windows, but should be done to ensure
---cross-platform compatibility.
---
---Using this function on individual files is possible, but discouraged as it can cause
---system resource exhaustion.
---@param path string The path to watch. This should be an absolute path.
---@param unwatch? boolean If true, the path is removed from the watch list.
function dirwatch:watch(path, unwatch)
  if unwatch == false then return self:unwatch(path) end
  local info = system.get_file_info(path)
  if not info then return end
  if not self.watched[path] and not self.scanned[path] then
    if self.monitor:mode() == "single" then
      if info.type ~= "dir" then return self:scan(path) end
      if not self.single_watch_top or path:find(self.single_watch_top, 1, true) ~= 1 then
        -- Get the highest level of directory that is common to this directory, and the original.
        local target = path
        while self.single_watch_top and self.single_watch_top:find(target, 1, true) ~= 1 do
          target = common.dirname(target)
        end
        if target ~= self.single_watch_top then
          local value = self.monitor:watch(target)
          if value and value < 0 then
            return self:scan(path)
          end
          self.single_watch_top = target
        end
      end
      self.single_watch_count = self.single_watch_count + 1
      self.watched[path] = true
    else
      local value = self.monitor:watch(path)
      -- If for whatever reason, we can't watch this directory, revert back to scanning.
      -- Don't bother trying to find out why, for now.
      if value and value < 0 then
        return self:scan(path)
      end
      self.watched[path] = value
      self.reverse_watched[value] = path
    end
  end
end

---Removes a path from the watch list.
---@param directory string The path to remove. This should be an absolute path.
function dirwatch:unwatch(directory)
  if self.watched[directory] then
    if self.monitor:mode() == "multiple" then
      self.monitor:unwatch(self.watched[directory])
      self.reverse_watched[directory] = nil
    else
      self.single_watch_count = self.single_watch_count - 1
      if self.single_watch_count == 0 then
        self.single_watch_top = nil
        self.monitor:unwatch(directory)
      end
    end
    self.watched[directory] = nil
  elseif self.scanned[directory] then
    self.scanned[directory] = nil
  end
end

---Checks each watched paths for changes.
---This function must be called in a coroutine, e.g. inside a thread created with `core.add_thread()`.
---@param change_callback fun(path: string)
---@param scan_time? number Maximum amount of time, in seconds, before the function yields execution.
---@param wait_time? number The duration to yield execution (in seconds).
---@return boolean # If true, a path had changed.
function dirwatch:check(change_callback, scan_time, wait_time)
  local had_change = false
  self.monitor:check(function(id)
    had_change = true
    if self.monitor:mode() == "single" then
      local path = common.dirname(id)
      if not string.match(id, "^/") and not string.match(id, "^%a:[/\\]") then
        path = common.dirname(self.single_watch_top .. PATHSEP .. id)
      end
      change_callback(path)
    elseif self.reverse_watched[id] then
      change_callback(self.reverse_watched[id])
    end
  end)
  local start_time = system.get_time()
  for directory, old_modified in pairs(self.scanned) do
    if old_modified then
      local info = system.get_file_info(directory)
      local new_modified = info and info.modified
      if old_modified ~= new_modified then
        change_callback(directory)
        had_change = true
        self.scanned[directory] = new_modified
      end
    end
    if system.get_time() - start_time > (scan_time or 0.01) then
      coroutine.yield(wait_time or 0.01)
      start_time = system.get_time()
    end
  end
  return had_change
end


---Prepare `config.ignore_files` into a list of patterns for matching.
local function compile_ignore_files()
  local ipatterns = config.ignore_files
  local compiled = {}
  -- config.ignore_files could be a simple string...
  if type(ipatterns) ~= "table" then ipatterns = {ipatterns} end
  for i, pattern in ipairs(ipatterns) do
    -- we ignore malformed pattern that raise an error
    if pcall(string.match, "a", pattern) then
      table.insert(compiled, {
        use_path = pattern:match("/[^/$]"), -- contains a slash but not at the end
        -- An '/' or '/$' at the end means we want to match a directory.
        match_dir = pattern:match(".+/%$?$"), -- to be used as a boolen value
        pattern = pattern -- get the actual pattern
      })
    end
  end
  return compiled
end


---Checks whether a file should be watched based on `config.file_size_limit`
---and `config.ignore_files`.
local function fileinfo_pass_filter(info, ignore_compiled)
  if info.size >= config.file_size_limit * 1e6 then return false end
  local basename = common.basename(info.filename)
  -- replace '\' with '/' for Windows where PATHSEP = '\'
  local fullname = "/" .. info.filename:gsub("\\", "/")
  for _, compiled in ipairs(ignore_compiled) do
    local test = compiled.use_path and fullname or basename
    if compiled.match_dir then
      if info.type == "dir" and string.match(test .. "/", compiled.pattern) then
        return false
      end
    else
      if string.match(test, compiled.pattern) then
        return false
      end
    end
  end
  return true
end


local function compare_file(a, b)
  return system.path_compare(a.filename, a.type, b.filename, b.type)
end


---Gets extended path information.
---If the file is filtered by `config.file_size_limit` or `config.ignore_files`,
---this function returns nil.
local function get_project_file_info(root, file, ignore_compiled)
  local info = system.get_file_info(root .. PATHSEP .. file)
  -- info can be not nil but info.type may be nil if is neither a file neither
  -- a directory, for example for /dev/* entries on linux.
  if info and info.type then
    info.filename = file
    return fileinfo_pass_filter(info, ignore_compiled) and info
  end
end


---A class containing information about a file.
---
---Aside from fields in `system.fileinfo`, it also includes the filename
---relative to a root directory.
---@class core.dirwatch.extended_fileinfo: system.fileinfo
---@field filename string The path to the file relative to a root directory, without starting and trailing slashes.

---Gets files recursively within a project directory.
---
---The function accepts a root path, and a sub-path within the root path.
---The root path must be an absolute path without trailing slashes,
---while the sub-path should not contain any slashes. It can be an empty string.
---
---This function also accepts a predicate function that'll be called on each subdirectory
---with the project directory object, the current path, the number of files
---and the time elapsed (in seconds) since the function first ran. </br>
---If the predicate returns true, the function recurses into the directory. </br>
---Otherwise, it moves on to the next subdirectory and repeats the check.
---@param dir table The project directory object.
---@param root string An absolute path to search, without trailing `/`.
---@param path string A sub-path within `root` without a trailing `/`, or an empty string.
---@param t core.dirwatch.extended_fileinfo[] A table to store the output of the function.
---@param entries_count number The number of entries in the table.
---@param recurse_pred fun(dir: table, path: string, entries_count: number, time_elapsed: number): boolean The predicate function.
---@return core.dirwatch.extended_fileinfo[]|nil # Table passed via `t`.
---@return boolean|nil # false if the indexing is interrupted by the predicate function.
---@return number|nil # Number of entries returned.
function dirwatch.get_directory_files(dir, root, path, t, entries_count, recurse_pred)
  local t0 = system.get_time()
  local t_elapsed = system.get_time() - t0
  local dirs, files = {}, {}
  local ignore_compiled = compile_ignore_files()


  local all = system.list_dir(root .. PATHSEP .. path)
  if not all then return nil end

  for _, file in ipairs(all or {}) do
    local info = get_project_file_info(root, (path ~= "" and (path .. PATHSEP) or "") .. file, ignore_compiled)
    if info then
      table.insert(info.type == "dir" and dirs or files, info)
      entries_count = entries_count + 1
    end
  end

  local recurse_complete = true
  table.sort(dirs, compare_file)
  for _, f in ipairs(dirs) do
    table.insert(t, f)
    if recurse_pred(dir, f.filename, entries_count, t_elapsed) then
      -- when recursing, root will stay the same while path changes
      local _, complete, n = dirwatch.get_directory_files(dir, root, f.filename, t, entries_count, recurse_pred)
      recurse_complete = recurse_complete and complete or false
      if n ~= nil then
        entries_count = n
      end
    else
      recurse_complete = false
    end
  end

  table.sort(files, compare_file)
  for _, f in ipairs(files) do
    table.insert(t, f)
  end

  return t, recurse_complete, entries_count
end


return dirwatch
