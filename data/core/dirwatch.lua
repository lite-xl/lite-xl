local common = require "core.common"
local config = require "core.config"
local dirwatch = {}

function dirwatch:__index(idx) 
  local value = rawget(self, idx)
  if value ~= nil then return value end
  return dirwatch[idx]
end

function dirwatch.new()
  local t = {
    scanned = {},
    watched = {},
    reverse_watched = {},
    monitor = dirmonitor.new(),
    windows_watch_top = nil,
    windows_watch_count = 0
  }
  setmetatable(t, dirwatch)
  return t
end


function dirwatch:scan(directory, bool)
  if bool == false then return self:unwatch(directory) end
  self.scanned[directory] = system.get_file_info(directory).modified
end

-- Should be called on every directory in a subdirectory.
-- In windows, this is a no-op for anything underneath a top-level directory,
-- but code should be called anyway, so we can ensure that we have a proper
-- experience across all platforms. Should be an absolute path.
-- Can also be called on individual files, though this should be used sparingly,
-- so as not to run into system limits (like in the autoreload plugin).
function dirwatch:watch(directory, bool)
  if bool == false then return self:unwatch(directory) end
  local info = system.get_file_info(directory)
  if not info then return end
  if not self.watched[directory] and not self.scanned[directory] then
    if PLATFORM == "Windows" then
      if info.type ~= "dir" then return self:scan(directory) end
      if not self.windows_watch_top or directory:find(self.windows_watch_top, 1, true) ~= 1 then
        -- Get the highest level of directory that is common to this directory, and the original.
        local target = directory
        while self.windows_watch_top and self.windows_watch_top:find(target, 1, true) ~= 1 do
          target = common.dirname(target)
        end
        if target ~= self.windows_watch_top then
          local value = self.monitor:watch(target)
          if value and value < 0 then
            return self:scan(directory)
          end
          self.windows_watch_top = target
        end
      end
      self.windows_watch_count = self.windows_watch_count + 1
      self.watched[directory] = true
    else
      local value = self.monitor:watch(directory)
      -- If for whatever reason, we can't watch this directory, revert back to scanning.
      -- Don't bother trying to find out why, for now.
      if value and value < 0 then
        return self:scan(directory)
      end
      self.watched[directory] = value
      self.reverse_watched[value] = directory
    end
  end
end

-- this should be an absolute path
function dirwatch:unwatch(directory)
  if self.watched[directory] then
    if PLATFORM ~= "Windows" then
      self.monitor:unwatch(self.watched[directory])
      self.reverse_watched[directory] = nil
    else
      self.windows_watch_count = self.windows_watch_count - 1
      if self.windows_watch_count == 0 then
        self.windows_watch_top = nil
        self.monitor:unwatch(directory)
      end
    end
    self.watched[directory] = nil
  elseif self.scanned[directory] then
    self.scanned[directory] = nil
  end
end

-- designed to be run inside a coroutine.
function dirwatch:check(change_callback, scan_time, wait_time)
  local had_change = false
  self.monitor:check(function(id)
    had_change = true
    if PLATFORM == "Windows" then
      change_callback(common.dirname(self.windows_watch_top .. PATHSEP .. id))
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
    if system.get_time() - start_time > scan_time then
      coroutine.yield(wait_time)
      start_time = system.get_time()
    end
  end
  return had_change
end


-- inspect config.ignore_files patterns and prepare ready to use entries.
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
  return a.filename < b.filename
end


-- compute a file's info entry completed with "filename" to be used
-- in project scan or falsy if it shouldn't appear in the list.
local function get_project_file_info(root, file, ignore_compiled)
  local info = system.get_file_info(root .. PATHSEP .. file)
  -- info can be not nil but info.type may be nil if is neither a file neither
  -- a directory, for example for /dev/* entries on linux.
  if info and info.type then
    info.filename = file
    return fileinfo_pass_filter(info, ignore_compiled) and info
  end
end


-- "root" will by an absolute path without trailing '/'
-- "path" will be a path starting without '/' and without trailing '/'
--    or the empty string.
--    It will identifies a sub-path within "root.
-- The current path location will therefore always be: root .. path.
-- When recursing "root" will always be the same, only "path" will change.
-- Returns a list of file "items". In each item the "filename" will be the
-- complete file path relative to "root" *without* the trailing '/', and without the starting '/'.
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
      local _, complete, n = dirwatch.get_directory_files(dir, root, f.filename, t, entries_count, recurse_pred)
      recurse_complete = recurse_complete and complete
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
