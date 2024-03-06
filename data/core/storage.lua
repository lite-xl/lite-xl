-- Provides persistent storage between restarts of the application.
local common = require "core.common"
local storage = {}

local function module_key_to_path(module, key)
  return USERDIR .. PATHSEP .. "storage" .. (module and (PATHSEP .. module .. (key and (PATHSEP .. key:gsub("[\\/]", "-")) or "")) or "")
end

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

function storage.save(module, key, t)
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
    f:write("return " .. common.serialize(t))
    f:flush()
  else
    core.error("error opening storage file %s for writing: %s", path, err)
  end
end

function storage.keys(module)
  return system.list_dir(module_key_to_path(module))
end

function storage.clear(module, key)
  local path = module_key_to_path(module, key)
  if system.get_file_info(path) then
    common.rm(path, true)
  end
end

return storage
