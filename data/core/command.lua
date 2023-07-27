local core = require "core"
local command = {}

---A predicate function accepts arguments from `command.perform()` and evaluates to a boolean. </br>
---If the function returns true, then the function associated with the command is executed.
---
---The predicate function can also return other values after the boolean, which will
---be passed into the function associated with the command.
---@alias core.command.predicate_function fun(...: any): boolean, ...

---A predicate is a string, an Object or a function, that is used to determine
---whether a command should be executed.
---
---If the predicate is a string, it is resolved into an `Object` via `require()`
---and checked against the active view with `Object:extends()`. </br>
---For example, `"core.docview"` will match any view that inherits from `DocView`. </br>
---A `!` can be appended to the predicate to strictly match the current view via `Object:is()`,
---instead of matching any view that inherits the predicate.
---
---If the predicate is a table, it is checked against the active view with `Object:extends()`.
---Strict matching via `Object:is()` is not available.
---
---If the predicate is a function, it must behave like a predicate function.
---@see core.command.predicate_function
---@alias core.command.predicate string|core.object|core.command.predicate_function

---A command is identified by a command name.
---The command name contains a category and the name itself, separated by a colon (':').
---
---All commands should be in lowercase and should not contain whitespaces; instead
---they should be replaced by a dash ('-').
---@alias core.command.command_name string

---The predicate and its associated function.
---@class core.command.command
---@field predicate core.command.predicate_function
---@field perform fun(...: any)

---@type { [string]: core.command.command }
command.map = {}

---@type core.command.predicate_function
local always_true = function() return true end


---This function takes in a predicate and produces a predicate function
---that is internally used to dispatch and execute commands.
---
---This function should not be called manually.
---@see core.command.predicate
---@param predicate core.command.predicate|nil If nil, the predicate always evaluates to true.
---@return core.command.predicate_function
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
      predicate = function(...) return core.active_view:extends(class), core.active_view, ... end
    else
      predicate = function(...) return core.active_view:is(class), core.active_view, ... end
    end
  end
  ---@cast predicate core.command.predicate_function
  return predicate
end


---Adds commands to the map.
---
---The function accepts a table containing a list of commands
---and their functions. </br>
---If a command already exists, it will be replaced.
---@see core.command.predicate
---@see core.command.command_name
---@param predicate core.command.predicate
---@param map { [core.command.command_name]: fun(...: any) }
function command.add(predicate, map)
  predicate = command.generate_predicate(predicate)
  for name, fn in pairs(map) do
    if command.map[name] then
      core.log_quiet("Replacing existing command \"%s\"", name)
    end
    command.map[name] = { predicate = predicate, perform = fn }
  end
end


local function capitalize_first(str)
  return str:sub(1, 1):upper() .. str:sub(2)
end

---Prettifies the command name.
---
---This function adds a space between the colon and the command name,
---replaces dashes with spaces and capitalizes the command appropriately.
---@see core.command.command_name
---@param name core.command.command_name
---@return string
function command.prettify_name(name)
  ---@diagnostic disable-next-line: redundant-return-value
  return name:gsub(":", ": "):gsub("-", " "):gsub("%S+", capitalize_first)
end


---Returns all the commands that can be executed (their predicates evaluate to true).
---@return core.command.command_name[]
function command.get_all_valid()
  local res = {}
  local memoized_predicates = {}
  for name, cmd in pairs(command.map) do
    if memoized_predicates[cmd.predicate] == nil then
      memoized_predicates[cmd.predicate] = cmd.predicate()
    end
    if memoized_predicates[cmd.predicate] then
      table.insert(res, name)
    end
  end
  return res
end

---Checks whether a command can be executed (its predicate evaluates to true).
---@param name core.command.command_name
---@param ... any
---@return boolean
function command.is_valid(name, ...)
  return command.map[name] and command.map[name].predicate(...)
end

local function perform(name, ...)
  local cmd = command.map[name]
  if not cmd then return false end
  local res = { cmd.predicate(...) }
  if table.remove(res, 1) then
    if #res > 0 then
      -- send values returned from predicate
      cmd.perform(table.unpack(res))
    else
      -- send original parameters
      cmd.perform(...)
    end
    return true
  end
  return false
end


---Performs a command.
---
---The arguments passed into this function are forwarded to the predicate function. </br>
---If the predicate function returns more than 1 value, the other values are passed
---to the command.
---
---Otherwise, the arguments passed into this function are passed directly
---to the command.
---@see core.command.predicate
---@see core.command.predicate_function
---@param name core.command.command_name
---@param ... any
---@return boolean # true if the command is performed successfully.
function command.perform(name, ...)
  local ok, res = core.try(perform, name, ...)
  return not ok or res
end


---Inserts the default commands for Lite XL into the map.
function command.add_defaults()
  local reg = {
    "core", "root", "command", "doc", "findreplace",
    "files", "dialog", "log", "statusbar"
  }
  for _, name in ipairs(reg) do
    require("core.commands." .. name)
  end
end


return command
