#!/usr/bin/env lua
local dkjson = require "dkjson"


local function load_keymap(target, target_map, macos)
  _G.MACOS = macos
  package.loaded["core.keymap"] = nil
  local keymap = require "core.keymap"

  if target then
    keymap.map = {}
    require(target)
  end

  target_map = target_map or {}
  -- keymap.reverse_map does not do this?
  for key, actions in pairs(keymap.map) do
    for _, action in ipairs(actions) do
      target_map[action] = target_map[action] or {}
      table.insert(target_map[action], key)
    end
  end

  return target_map
end


local function normalize(map)
  local result = {}
  for action, keys in pairs(map) do
    local uniq = {}
    local r = { combination = {}, action = action }
    for _, v in ipairs(keys) do
      if not uniq[v] then
        uniq[v] = true
        r.combination[#r.combination+1] = v
      end
    end
    result[#result+1] = r
  end
  table.sort(result, function(a, b) return a.action < b.action end)
  return result
end


local function process_module(mod, filename)
  local map = {}
  load_keymap(mod, map)
  load_keymap(mod, map, true)
  map = normalize(map)
  local f = assert(io.open(filename, "wb"))
  f:write(dkjson.encode(map, { indent = true }))
  f:close()
end


print("Warning: this is not guaranteed to work outside lite-xl's own keymap. Proceed with caution")
local LITE_ROOT = arg[1]
if not LITE_ROOT then
  error("LITE_ROOT is not given")
end
package.path = package.path .. ";" .. LITE_ROOT .. "/?.lua;" .. LITE_ROOT .. "/?/init.lua"

-- fix core.command (because we don't want load the entire thing)
package.loaded["core.command"] = {}

if #arg > 1 then
  for i = 2, #arg do
    process_module(arg[i], arg[i] .. ".json")
    print(string.format("Exported keymap in %q.", arg[i]))
  end
else
  process_module(nil, "core.keymap.json")
  print("Exported the default keymap.")
end
