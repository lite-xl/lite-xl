local core = require "core"
local command = {}

command.map = {}

local always_true = function() return true end


---Used iternally by command.add, statusview, and contextmenu to generate a
---function with a condition to evaluate returning the boolean result of this
---evaluation.
---
---If a string predicate is given it is treated as a require import that should
---return a valid object which is checked against the current active view,
---eg: "core.docview" will match any view that inherits from DocView. Appending
---a `!` at the end of the string means we want to match the given object
---from the import strcitly eg: "core.docview!" only DocView is matched.
---A function that returns a boolean can be used instead to perform a custom
---evaluation, setting to nil means always evaluates to true.
---
---@param predicate string | table | function
---@return function
function command.generate_predicate(predicate)
  predicate = predicate or always_true
  local strict = false
  if type(predicate) == "string" then
    if predicate:match("!$") then
      strict = true
      predicate = predicate:gsub("!$", "")
    end
    predicate = require(predicate)
  end
  if type(predicate) == "table" then
    local class = predicate
    if not strict then
      predicate = function() return core.active_view:extends(class) end
    else
      predicate = function() return core.active_view:is(class) end
    end
  end
  return predicate
end


function command.add(predicate, map)
  predicate = command.generate_predicate(predicate)
  for name, fn in pairs(map) do
    assert(not command.map[name], "command already exists: " .. name)
    command.map[name] = { predicate = predicate, perform = fn }
  end
end


local function capitalize_first(str)
  return str:sub(1, 1):upper() .. str:sub(2)
end

function command.prettify_name(name)
  return name:gsub(":", ": "):gsub("-", " "):gsub("%S+", capitalize_first)
end


function command.get_all_valid()
  local res = {}
  for name, cmd in pairs(command.map) do
    if cmd.predicate() then
      table.insert(res, name)
    end
  end
  return res
end

function command.is_valid(name, ...)
  return command.map[name] and command.map[name].predicate(...)
end

local function perform(name, ...)
  local cmd = command.map[name]
  if cmd and cmd.predicate(...) then
    cmd.perform(...)
    return true
  end
  return false
end


function command.perform(...)
  local ok, res = core.try(perform, ...)
  return not ok or res
end


function command.add_defaults()
  local reg = {
    "core", "root", "command", "doc", "findreplace",
    "files", "drawwhitespace", "dialog", "log", "statusbar"
  }
  for _, name in ipairs(reg) do
    require("core.commands." .. name)
  end
end


return command
