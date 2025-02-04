local core = require "core"
local command = require "core.command"
local config = require "core.config"
local ime = require "core.ime"
local keymap = {}

---@alias keymap.shortcut string
---@alias keymap.command string
---@alias keymap.modkey string
---@alias keymap.pressed boolean
---@alias keymap.map table<keymap.shortcut,keymap.command|keymap.command[]>
---@alias keymap.rmap table<keymap.command, keymap.shortcut|keymap.shortcut[]>

---Pressed status of mod keys.
---@type table<keymap.modkey, keymap.pressed>
keymap.modkeys = {}

---List of commands assigned to a shortcut been the key of the map the shortcut.
---@type keymap.map
keymap.map = {}

---List of shortcuts assigned to a command been the key of the map the command.
---@type keymap.rmap
keymap.reverse_map = {}

local macos = PLATFORM == "Mac OS X"

-- Thanks to mathewmariani, taken from his lite-macos github repository.
local modkeys_os = require("core.modkeys-" .. (macos and "macos" or "generic"))

---@type table<keymap.modkey, keymap.modkey>
local modkey_map = modkeys_os.map

---@type keymap.modkey[]
local modkeys = modkeys_os.keys


---Normalizes a stroke sequence to follow the modkeys table
---@param stroke string
---@return string
local function normalize_stroke(stroke)
  local stroke_table = {}
  for key in stroke:gmatch("[^+]+") do
    table.insert(stroke_table, key)
  end
  table.sort(stroke_table, function(a, b)
    if a == b then return false end
    for _, mod in ipairs(modkeys) do
      if a == mod or b == mod then
        return a == mod
      end
    end
    return a < b
  end)
  return table.concat(stroke_table, "+")
end


---Generates a stroke sequence including currently pressed mod keys.
---@param key string
---@return string
local function key_to_stroke(key)
  local keys = { key }
  for _, mk in ipairs(modkeys) do
    if keymap.modkeys[mk] then
      table.insert(keys, mk)
    end
  end
  return normalize_stroke(table.concat(keys, "+"))
end


---Remove the given value from an array associated to a key in a table.
---@param tbl table<string, string> The table containing the key
---@param k string The key containing the array
---@param v? string The value to remove from the array
local function remove_only(tbl, k, v)
  if tbl[k] then
    if v then
      local j = 0
      for i=1, #tbl[k] do
        while tbl[k][i + j] == v do
          j = j + 1
        end
        tbl[k][i] = tbl[k][i + j]
      end
    else
      tbl[k] = nil
    end
  end
end


---Removes from a keymap.map the bindings that are already registered.
---@param map keymap.map
local function remove_duplicates(map)
  for stroke, commands in pairs(map) do
    local normalized_stroke = normalize_stroke(stroke)
    if type(commands) == "string" or type(commands) == "function" then
      commands = { commands }
    end
    if keymap.map[normalized_stroke] then
      for _, registered_cmd in ipairs(keymap.map[normalized_stroke]) do
        local j = 0
        for i=1, #commands do
          while commands[i + j] == registered_cmd do
            j = j + 1
          end
          commands[i] = commands[i + j]
        end
      end
    end
    if #commands < 1 then
      map[stroke] = nil
    else
      map[stroke] = commands
    end
  end
end

---Add bindings by replacing commands that were previously assigned to a shortcut.
---@param map keymap.map
function keymap.add_direct(map)
  for stroke, commands in pairs(map) do
    stroke = normalize_stroke(stroke)

    if type(commands) == "string" or type(commands) == "function" then
      commands = { commands }
    end
    if keymap.map[stroke] then
      for _, cmd in ipairs(keymap.map[stroke]) do
        remove_only(keymap.reverse_map, cmd, stroke)
      end
    end
    keymap.map[stroke] = commands
    for _, cmd in ipairs(commands) do
      keymap.reverse_map[cmd] = keymap.reverse_map[cmd] or {}
      table.insert(keymap.reverse_map[cmd], stroke)
    end
  end
end


---Adds bindings by appending commands to already registered shortcut or by
---replacing currently assigned commands if overwrite is specified.
---@param map keymap.map
---@param overwrite? boolean
function keymap.add(map, overwrite)
  remove_duplicates(map)
  for stroke, commands in pairs(map) do
    if macos then
      stroke = stroke:gsub("%f[%a]ctrl%f[%A]", "cmd")
    end
    stroke = normalize_stroke(stroke)
    if overwrite then
      if keymap.map[stroke] then
        for _, cmd in ipairs(keymap.map[stroke]) do
          remove_only(keymap.reverse_map, cmd, stroke)
        end
      end
      keymap.map[stroke] = commands
    else
      keymap.map[stroke] = keymap.map[stroke] or {}
      for i = #commands, 1, -1 do
        table.insert(keymap.map[stroke], 1, commands[i])
      end
    end
    for _, cmd in ipairs(commands) do
      keymap.reverse_map[cmd] = keymap.reverse_map[cmd] or {}
      table.insert(keymap.reverse_map[cmd], stroke)
    end
  end
end


---Unregisters the given shortcut and associated command.
---@param shortcut string
---@param cmd string
function keymap.unbind(shortcut, cmd)
  shortcut = normalize_stroke(shortcut)
  remove_only(keymap.map, shortcut, cmd)
  remove_only(keymap.reverse_map, cmd, shortcut)
end


---Returns all the shortcuts associated to a command unpacked for easy assignment.
---@param cmd string
---@return ...
function keymap.get_binding(cmd)
  return table.unpack(keymap.reverse_map[cmd] or {})
end


---Returns all the shortcuts associated to a command packed in a table.
---@param cmd string
---@return table<integer, string> | nil shortcuts
function keymap.get_bindings(cmd)
  return keymap.reverse_map[cmd]
end


--------------------------------------------------------------------------------
-- Events listening
--------------------------------------------------------------------------------
function keymap.on_key_pressed(k, ...)
  local mk = modkey_map[k]
  if mk then
    keymap.modkeys[mk] = true
    -- work-around for windows where `altgr` is treated as `ctrl+alt`
    if mk == "altgr" then
      keymap.modkeys["ctrl"] = false
    end
  else
    local stroke = key_to_stroke(k)
    local commands, performed = keymap.map[stroke], false
    if commands then
      for _, cmd in ipairs(commands) do
        if type(cmd) == "function" then
          local ok, res = core.try(cmd, ...)
          if ok then
            performed = not (res == false)
          else
            performed = true
          end
        else
          performed = command.perform(cmd, ...)
        end
        if performed then break end
      end
      return performed
    end
  end
  return false
end

function keymap.on_mouse_wheel(delta_y, delta_x, ...)
  local y_direction = delta_y > 0 and "up" or "down"
  local x_direction = delta_x > 0 and "left" or "right"
  -- Try sending a "cumulative" event for both scroll directions
  if delta_y ~= 0 and delta_x ~= 0 then
    local result = keymap.on_key_pressed("wheel" .. y_direction .. x_direction, delta_y, delta_x, ...)
    if not result then
      result = keymap.on_key_pressed("wheelyx", delta_y, delta_x, ...)
    end
    if result then return true end
  end
  -- Otherwise send each direction as its own separate event
  local y_result, x_result
  if delta_y ~= 0 then
    y_result = keymap.on_key_pressed("wheel" .. y_direction, delta_y, ...)
    if not y_result then
      y_result = keymap.on_key_pressed("wheel", delta_y, ...)
    end
  end
  if delta_x ~= 0 then
    x_result = keymap.on_key_pressed("wheel" .. x_direction, delta_x, ...)
    if not x_result then
      x_result = keymap.on_key_pressed("hwheel", delta_x, ...)
    end
  end
  return y_result or x_result
end

function keymap.on_mouse_pressed(button, x, y, clicks)
  local click_number = (((clicks - 1) % config.max_clicks) + 1)
  return not (keymap.on_key_pressed(click_number  .. button:sub(1,1) .. "click", x, y, clicks) or
    keymap.on_key_pressed(button:sub(1,1) .. "click", x, y, clicks) or
    keymap.on_key_pressed(click_number .. "click", x, y, clicks) or
    keymap.on_key_pressed("click", x, y, clicks))
end

function keymap.on_key_released(k)
  local mk = modkey_map[k]
  if mk then
    keymap.modkeys[mk] = false
  end
end


--------------------------------------------------------------------------------
-- Register default bindings
--------------------------------------------------------------------------------
if macos then
  local keymap_macos = require("core.keymap-macos")
  keymap_macos(keymap)
  return keymap
end

keymap.add_direct {
  ["ctrl+shift+p"] = "core:find-command",
  ["ctrl+o"] = "core:open-file",
  ["ctrl+n"] = "core:new-doc",
  ["ctrl+shift+c"] = "core:change-project-folder",
  ["ctrl+shift+o"] = "core:open-project-folder",
  ["ctrl+alt+r"] = "core:restart",
  ["alt+return"] = "core:toggle-fullscreen",
  ["f11"] = "core:toggle-fullscreen",

  ["alt+shift+j"] = "root:split-left",
  ["alt+shift+l"] = "root:split-right",
  ["alt+shift+i"] = "root:split-up",
  ["alt+shift+k"] = "root:split-down",
  ["alt+j"] = "root:switch-to-left",
  ["alt+l"] = "root:switch-to-right",
  ["alt+i"] = "root:switch-to-up",
  ["alt+k"] = "root:switch-to-down",

  ["ctrl+w"] = "root:close",
  ["ctrl+tab"] = "root:switch-to-next-tab",
  ["ctrl+shift+tab"] = "root:switch-to-previous-tab",
  ["ctrl+pageup"] = "root:move-tab-left",
  ["ctrl+pagedown"] = "root:move-tab-right",
  ["alt+1"] = "root:switch-to-tab-1",
  ["alt+2"] = "root:switch-to-tab-2",
  ["alt+3"] = "root:switch-to-tab-3",
  ["alt+4"] = "root:switch-to-tab-4",
  ["alt+5"] = "root:switch-to-tab-5",
  ["alt+6"] = "root:switch-to-tab-6",
  ["alt+7"] = "root:switch-to-tab-7",
  ["alt+8"] = "root:switch-to-tab-8",
  ["alt+9"] = "root:switch-to-tab-9",
  ["wheel"] = "root:scroll",
  ["hwheel"] = "root:horizontal-scroll",
  ["shift+wheel"] = "root:horizontal-scroll",
  ["wheelup"] = "root:scroll-hovered-tabs-backward",
  ["wheeldown"] = "root:scroll-hovered-tabs-forward",

  ["ctrl+f"] = "find-replace:find",
  ["ctrl+r"] = "find-replace:replace",
  ["f3"] = "find-replace:repeat-find",
  ["shift+f3"] = "find-replace:previous-find",
  ["ctrl+i"] = "find-replace:toggle-sensitivity",
  ["ctrl+shift+i"] = "find-replace:toggle-regex",
  ["ctrl+g"] = "docview:go-to-line",
  ["ctrl+s"] = "doc:save",
  ["ctrl+shift+s"] = "doc:save-as",

  ["ctrl+z"] = "docview:undo",
  ["ctrl+y"] = "docview:redo",
  ["ctrl+x"] = "docview:cut",
  ["ctrl+c"] = "docview:copy",
  ["ctrl+v"] = "docview:paste",
  ["insert"] = "docview:toggle-overwrite",
  ["ctrl+insert"] = "docview:copy",
  ["shift+insert"] = "docview:paste",
  ["escape"] = { "command:escape", "docview:select-none", "dialog:select-no" },
  ["tab"] = { "command:complete", "docview:indent" },
  ["shift+tab"] = "docview:unindent",
  ["backspace"] = "docview:backspace",
  ["shift+backspace"] = "docview:backspace",
  ["ctrl+backspace"] = "docview:delete-to-previous-word-start",
  ["ctrl+shift+backspace"] = "docview:delete-to-previous-word-start",
  ["delete"] = "docview:delete",
  ["shift+delete"] = "docview:delete",
  ["ctrl+delete"] = "docview:delete-to-next-word-end",
  ["ctrl+shift+delete"] = "docview:delete-to-next-word-end",
  ["return"] = { "command:submit", "docview:newline", "dialog:select" },
  ["keypad enter"] = { "command:submit", "docview:newline", "dialog:select" },
  ["ctrl+return"] = "docview:newline-below",
  ["ctrl+shift+return"] = "docview:newline-above",
  ["ctrl+j"] = "docview:join-lines",
  ["ctrl+a"] = "docview:select-all",
  ["ctrl+d"] = { "find-replace:select-add-next", "docview:select-word" },
  ["ctrl+f3"] = "find-replace:select-next",
  ["ctrl+shift+f3"] = "find-replace:select-previous",
  ["ctrl+l"] = "docview:select-lines",
  ["ctrl+shift+l"] = { "find-replace:select-add-all", "docview:select-word" },
  ["ctrl+/"] = "docview:toggle-line-comments",
  ["ctrl+shift+/"] = "docview:toggle-block-comments",
  ["ctrl+up"] = "docview:move-lines-up",
  ["ctrl+down"] = "docview:move-lines-down",
  ["ctrl+shift+d"] = "docview:duplicate-lines",
  ["ctrl+shift+k"] = "docview:delete-lines",

  ["left"] = { "docview:move-to-previous-char", "dialog:previous-entry" },
  ["right"] = { "docview:move-to-next-char", "dialog:next-entry"},
  ["up"] = { "command:select-previous", "docview:move-to-previous-line" },
  ["down"] = { "command:select-next", "docview:move-to-next-line" },
  ["ctrl+left"] = "docview:move-to-previous-word-start",
  ["ctrl+right"] = "docview:move-to-next-word-end",
  ["ctrl+["] = "docview:move-to-previous-block-start",
  ["ctrl+]"] = "docview:move-to-next-block-end",
  ["home"] = "docview:move-to-start-of-indentation",
  ["end"] = "docview:move-to-end-of-line",
  ["ctrl+home"] = "docview:move-to-start-of-doc",
  ["ctrl+end"] = "docview:move-to-end-of-doc",
  ["pageup"] = "docview:move-to-previous-page",
  ["pagedown"] = "docview:move-to-next-page",

  ["shift+1lclick"] = "docview:select-to-cursor",
  ["ctrl+1lclick"] = "docview:split-cursor",
  ["1lclick"] = "docview:set-cursor",
  ["2lclick"] = { "docview:set-cursor-word", "emptyview:new-doc", "tabbar:new-doc" },
  ["3lclick"] = "docview:set-cursor-line",
  ["mclick"] = "docview:paste-primary-selection",
  ["shift+left"] = "docview:select-to-previous-char",
  ["shift+right"] = "docview:select-to-next-char",
  ["shift+up"] = "docview:select-to-previous-line",
  ["shift+down"] = "docview:select-to-next-line",
  ["ctrl+shift+left"] = "docview:select-to-previous-word-start",
  ["ctrl+shift+right"] = "docview:select-to-next-word-end",
  ["ctrl+shift+["] = "docview:select-to-previous-block-start",
  ["ctrl+shift+]"] = "docview:select-to-next-block-end",
  ["shift+home"] = "docview:select-to-start-of-indentation",
  ["shift+end"] = "docview:select-to-end-of-line",
  ["ctrl+shift+home"] = "docview:select-to-start-of-doc",
  ["ctrl+shift+end"] = "docview:select-to-end-of-doc",
  ["shift+pageup"] = "docview:select-to-previous-page",
  ["shift+pagedown"] = "docview:select-to-next-page",
  ["ctrl+shift+up"] = "docview:create-cursor-previous-line",
  ["ctrl+shift+down"] = "docview:create-cursor-next-line"
}

return keymap
