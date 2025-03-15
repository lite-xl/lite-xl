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
    single_watch_top = nil,
    single_watch_count = 0
  }
  setmetatable(t, dirwatch)
  return t
end


function dirwatch:scan(directory, bool)
  if bool == false then return self:unwatch(directory) end
  self.scanned[directory] = system.get_file_info(directory).modified
end

-- Should be called on every directory in a subdirectory.
-- On Windows, this is a no-op for anything underneath a top-level directory,
-- but code should be called anyway, so we can ensure that we have a proper
-- experience across all platforms. Should be an absolute path.
-- Can also be called on individual files, though this should be used sparingly,
-- so as not to run into system limits (like in the autoreload plugin).
function dirwatch:watch(directory, bool)
  if bool == false then return self:unwatch(directory) end
  local info = system.get_file_info(directory)
  if not info then return end
  if not self.watched[directory] and not self.scanned[directory] then
    if self.monitor:mode() == "single" then
      if info.type ~= "dir" then return self:scan(directory) end
      if not self.single_watch_top or directory:find(self.single_watch_top, 1, true) ~= 1 then
        -- Get the highest level of directory that is common to this directory, and the original.
        local target = directory
        while self.single_watch_top and self.single_watch_top:find(target, 1, true) ~= 1 do
          target = common.dirname(target)
        end
        if target ~= self.single_watch_top then
          local value = self.monitor:watch(target)
          if value and value < 0 then
            return self:scan(directory)
          end
          self.single_watch_top = target
        end
      end
      self.single_watch_count = self.single_watch_count + 1
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

-- designed to be run inside a coroutine.
function dirwatch:check(change_callback, scan_time, wait_time)
  local had_change = false
  local last_error
  self.monitor:check(function(id)
    had_change = true
    if self.monitor:mode() == "single" then
      local path = common.dirname(id)
      if not string.match(id, "^/") and not string.match(id, "^%a:[/\\]") then
        path = common.dirname(self.single_watch_top .. PATHSEP .. id)
      end
      change_callback(path)
    elseif self.reverse_watched[id] then
      local path = self.reverse_watched[id]
      change_callback(path)
      local info = system.get_file_info(path)
      if info and info.type == "file" then
        self:unwatch(path)
        self:watch(path)
      end
    end
  end, function(err)
    last_error = err
  end)
  if last_error ~= nil then error(last_error) end
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

return dirwatch
