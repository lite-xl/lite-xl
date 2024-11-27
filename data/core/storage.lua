local core = require "core"
local common = require "core.common"

local function module_key_to_path(module, key)
  return USERDIR .. PATHSEP .. "storage" .. (module and (PATHSEP .. module .. (key and (PATHSEP .. key:gsub("[\\/]", "-")) or "")) or "")
end


---Provides persistent storage between restarts of the application.
---@class storage
local storage = {}


---Loads data from a persistent storage file.
---
---@param module string The module under which the data is stored.
---@param key string The key under which the data is stored.
---@return string|table|number? data The stored data present for this module, at this key.
function storage.load(module, key)
  local path = module_key_to_path(module, key)
  if system.get_file_info(path) then
    local func, err = loadfile(path)
    if func then
      return func()
    else
      core.error("error loading storage file for %s[%s]: %s", module, key, err)
    end
  end
  return nil
end


---Saves data to a persistent storage file.
---
---@param module string The module under which the data is stored.
---@param key string The key under which the data is stored.
---@param value table|string|number The value to store.
function storage.save(module, key, value)
  local path = module_key_to_path(module, key)
  local dir = common.dirname(path)
  if not system.get_file_info(dir) then
    local status, err = common.mkdirp(dir)
    if not status then
      core.error("error creating storage directory for %s at %s: %s", module, dir, err)
    end
  end
  local f, err = io.open(path, "wb")
  if f then
    f:write("return " .. common.serialize(value))
    f:flush()
  else
    core.error("error opening storage file %s for writing: %s", path, err)
  end
end


---Gets the list of keys saved under a module.
---
---@param module string The module under which the data is stored.
---@return table A table of keys under which data is stored for this module.
function storage.keys(module)
  return system.list_dir(module_key_to_path(module)) or {}
end


---Clears data for a particular module and optionally key.
---
---@param module string The module under which the data is stored.
---@param key? string The key under which the data is stored. If omitted, will clear the entire store for this module.
function storage.clear(module, key)
  local path = module_key_to_path(module, key)
  if system.get_file_info(path) then
    common.rm(path, true)
  end
end


return storage
