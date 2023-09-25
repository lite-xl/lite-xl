-- mod-version:3 -- priority:1
local core = require "core"
local config = require "core.config"
local common = require "core.common"
local command = require "core.command"

local function parse_value(value)
  if value == "true" then return true end
  if value == "false" then return false end
  if value:find("^%d+$") then return tonumber(value) end
  return value
end

while true do
  local setting = common.grab_arg('config')
  if not setting then break end
  local s,e = setting:find('=')
  if not s then error("can't find value for --config setting") end
  local name, value = setting:sub(1, s-1), setting:sub(s+1)
  local location, remainder = config, name
  while true do
    s = remainder:find('%.')
    if not s then location[remainder] = parse_value(value) break end
    location, remainder = location[remainder:sub(1, s-1)], remainder:sub(s+1)
  end
end
while true do
  local cmd = common.grab_arg('command')
  if not cmd then break end
  core.add_thread(function() command.perform(cmd) end)
end

local old_run = core.run
core.run = function()
  local t = {}
  for i,v in ipairs(ARGS) do
    if i > 1 and v:find("^%-%-") then core.error("unrecognized flag " .. v) else table.insert(t, v) end
  end
  ARGS = t
  old_run()
end


