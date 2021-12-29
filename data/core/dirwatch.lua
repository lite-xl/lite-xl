local dirwatch = {}

function dirwatch:__index(idx) 
  local value = rawget(self, idx)
  if value ~= nil then return value end`
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
-- experience across all platforms.
function dirwatch:watch(directory, bool)
  if bool == false then return self:unwatch(directory) end
  if not self.watched[directory] and not self.scanned[directory] then
    if PLATFORM == "Windows" then
      if not self.windows_watch_top or self.windows_watch_top:find(directory) == 1 then
        self.windows_watch_top = directory
        self.windows_watch_count = self.windows_watch_count + 1
        local value = self.monitor:watch(directory)
        if value and value < 0 then
          return self:scan(directory)
        end
        self.watched[directory] = true
      end
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

function dirwatch:unwatch(directory)
  if self.watched[directory] then
    if PLATFORM ~= "Windows" then
      self.monitor.unwatch(directory)
      self.reverse_watched[self.watched[directory]] = nil
    else
      self.windows_watch_count = self.windows_watch_count - 1
      if self.windows_watch_count == 0 then
        self.windows_watch_top = nil
        self.monitor.unwatch(directory)
      end
    end
    self.watched[directory] = nil
  elseif self.scanned[directory] then
    self.scanned[directory] = nil
  end
end

-- designed to be run inside a coroutine.
function dirwatch:check(change_callback, scan_time, wait_time)
  self.monitor:check(function(id)
    if PLATFORM == "Windows" then
      change_callback(id)
    elseif self.reverse_watched[id] then
      change_callback(self.reverse_watched[id])
    end
  end)
  local start_time = system.get_time()
  for directory, old_modified in pairs(self.scanned) do
    if old_modified then
      local new_modified = system.get_file_info(directory).modified
      if old_modified < new_modified then
        change_callback(directory)
        self.scanned[directory] = new_modified
      end
    end
    if system.get_time() - start_time > scan_time then
      coroutine.yield(wait_time)
      start_time = system.get_time()
    end
  end
end

return dirwatch
