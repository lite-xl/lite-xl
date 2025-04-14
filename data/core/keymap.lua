local core = require "core"
local command = require "core.command"
local config = require "core.config"
local ime = require "core.ime"
local keymap = {}

---@alias keymap.shortcut string | string[]
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

---Current multi-stroke state.
---@type string[] | nil
keymap.current_strokes = nil


local macos = PLATFORM == "Mac OS X"

-- Thanks to mathewmariani, taken from his lite-macos github repository.
local modkeys_os = require("core.modkeys-" .. (macos and "macos" or "generic"))

---@type table<keymap.modkey, keymap.modkey>
local modkey_map = modkeys_os.map

---@type keymap.modkey[]
local modkeys = modkeys_os.keys


---Normalizes a single stroke sequence to follow the modkeys table.
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


---Normalizes one or multiple strokes as per the modkey table.
---@param strokes string | string[]
---@return string[]
local function normalize_strokes(strokes)
  if type(strokes) == "string" then return { normalize_stroke(strokes) } end
  local ret = {}
  for _, stroke in ipairs(strokes) do
    table.insert(ret, normalize_stroke(stroke))
  end
  return ret
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


---Returns the value at `tbl[keys[1]]...[keys[#keys]]`.
---@param tbl table<any, any> Base table
---@param keys any[] Keys
---@return any? # `tbl[keys[1]]...[keys[#keys]]`
local function get_nested(tbl, keys)
  local r = tbl
  for _, key in ipairs(keys) do
    r = type(r) == "table" and r[key] or nil
    if not r then break end
  end
  return r
end


---Sets the value of `tbl[keys[1]]...[keys[#keys]]` to v.
---@param tbl table<any, any> Base table
---@param keys any[] Keys
---@param v any?
local function set_nested(tbl, keys, v)
  local dst = tbl
  for i = 1, #keys - 1 do
    local k = keys[i]
    dst[k] = type(dst[k]) == "table" and dst[k] or { }
    dst = dst[k]
  end
  dst[keys[#keys]] = v
end


---Checks two strokes for equality.
---@param s1 keymap.shortcut
---@param s2 keymap.shortcut
---@return boolean
local function stroke_equals(s1, s2)
  if type(s1) ~= "table" then
    return type(s2) ~= "table" and (s1 == s2) or (#s2 == 1 and s1 == s2[1])
  end
  local len = #s1
  if len ~= #s2 then return false end
  for i = 1, len do
    if s1[i] ~= s2[i] then
      return false
    end
  end
  return true
end


---Remove the given value from an array associated to a key in a table.
---@param tbl table<string, string  | string[]> The table containing the key
---@param k string The key containing the array
---@param v? string | string[] The value to remove from the array
local function remove_only(tbl, k, v)
  if tbl[k] then
    if v then
      local j = 0
      for i=1, #tbl[k] do
        while stroke_equals(tbl[k][i + j], v) do
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
    local strokes = normalize_strokes(stroke)
    if type(commands) == "string" or type(commands) == "function" then
      commands = { commands }
    end
    local registered_cmds = get_nested(keymap.map, strokes)
    if registered_cmds then
      for _, registered_cmd in ipairs(registered_cmds) do
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
    local strokes = normalize_strokes(stroke)
    if type(commands) == "string" or type(commands) == "function" then
      commands = { commands }
    end
    local cmds = get_nested(keymap.map, strokes)
    if cmds then
      for s, cmd in pairs(cmds) do
        if type(s) == "number" then
          remove_only(keymap.reverse_map, cmd, strokes)
        else
          commands[s] = cmd
        end
      end
    end
    set_nested(keymap.map, strokes, commands)
    for _, cmd in ipairs(commands) do
      keymap.reverse_map[cmd] = keymap.reverse_map[cmd] or {}
      table.insert(keymap.reverse_map[cmd], strokes)
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
    local strokes = normalize_strokes(stroke)
    if macos then
      for i, s in ipairs(strokes) do
        strokes[i] = s:gsub("%f[%a]ctrl%f[%A]", "cmd")
      end
    end
    if overwrite then
      local cmds = get_nested(keymap.map, strokes)
      if cmds then
        for s, cmd in pairs(cmds) do
          if type(s) == "number" then
            remove_only(keymap.reverse_map, cmd, strokes)
          else
            commands[s] = cmd
          end
        end
      end
      set_nested(keymap.map, strokes, commands)
    else
      local cmds = get_nested(keymap.map, strokes) or { }
      for i = #commands, 1, -1 do
        table.insert(cmds, 1, commands[i])
      end
      set_nested(keymap.map, strokes, cmds)
    end
    for _, cmd in ipairs(commands) do
      keymap.reverse_map[cmd] = keymap.reverse_map[cmd] or {}
      table.insert(keymap.reverse_map[cmd], strokes)
    end
  end
end


---Unregisters the given shortcut and associated command.
---@param shortcut string | string[]
---@param cmd string
function keymap.unbind(shortcut, cmd)
  local strokes = normalize_strokes(shortcut)
  remove_only(keymap.reverse_map, cmd, strokes)
  local last_sub = table.remove(strokes)
  remove_only(get_nested(keymap.map, strokes) or { }, last_sub, cmd)
  table.insert(strokes, last_sub)
  -- remove empty submaps to avoid entering multi stroke state if all commands
  -- prefixed with shortcut or a subsequence have been removed
  while #strokes > 0 do
    local submap = get_nested(keymap.map, strokes)
    if next(submap) then
      break
    end
    set_nested(keymap.map, strokes, nil)
    table.remove(strokes)
  end
end


---Returns all the shortcuts associated to a command unpacked for easy assignment.
---@param cmd string
---@return ...
function keymap.get_binding(cmd)
  return table.unpack(keymap.reverse_map[cmd] or {})
end


---Returns all the shortcuts associated to a command packed in a table.
---@param cmd string
---@return keymap.shortcut[] | nil shortcuts
function keymap.get_bindings(cmd)
  return keymap.reverse_map[cmd]
end

---Returns a string representation of a shortcut.
---@param shortcut? keymap.shortcut
---@return string
function keymap.binding_to_string(shortcut)
  if not shortcut then return "" end
  return type(shortcut) ~= "table" and shortcut or table.concat(shortcut, " ")
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
    keymap.current_strokes = keymap.current_strokes or {}
    table.insert(keymap.current_strokes, stroke)
    local commands, performed = get_nested(keymap.map, keymap.current_strokes), false
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
        if performed then
          keymap.current_strokes = nil
          return true
        end
      end
      -- mark the keypress as handled if we're in a valid multistroke prefix
      for k, substroke in pairs(commands) do
        if type(k) == "string" then
          return true
        end
      end
    end
    keymap.current_strokes = nil
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
  ["ctrl+g"] = "doc:go-to-line",
  ["ctrl+s"] = "doc:save",
  ["ctrl+shift+s"] = "doc:save-as",

  ["ctrl+z"] = "doc:undo",
  ["ctrl+y"] = "doc:redo",
  ["ctrl+x"] = "doc:cut",
  ["ctrl+c"] = "doc:copy",
  ["ctrl+v"] = "doc:paste",
  ["insert"] = "doc:toggle-overwrite",
  ["ctrl+insert"] = "doc:copy",
  ["shift+insert"] = "doc:paste",
  ["escape"] = { "command:escape", "doc:select-none", "dialog:select-no" },
  ["tab"] = { "command:complete", "doc:indent" },
  ["shift+tab"] = "doc:unindent",
  ["backspace"] = "doc:backspace",
  ["shift+backspace"] = "doc:backspace",
  ["ctrl+backspace"] = "doc:delete-to-previous-word-start",
  ["ctrl+shift+backspace"] = "doc:delete-to-previous-word-start",
  ["delete"] = "doc:delete",
  ["shift+delete"] = "doc:delete",
  ["ctrl+delete"] = "doc:delete-to-next-word-end",
  ["ctrl+shift+delete"] = "doc:delete-to-next-word-end",
  ["return"] = { "command:submit", "doc:newline", "dialog:select" },
  ["keypad enter"] = { "command:submit", "doc:newline", "dialog:select" },
  ["ctrl+return"] = "doc:newline-below",
  ["ctrl+shift+return"] = "doc:newline-above",
  ["ctrl+j"] = "doc:join-lines",
  ["ctrl+a"] = "doc:select-all",
  ["ctrl+d"] = { "find-replace:select-add-next", "doc:select-word" },
  ["ctrl+f3"] = "find-replace:select-next",
  ["ctrl+shift+f3"] = "find-replace:select-previous",
  ["ctrl+l"] = "doc:select-lines",
  ["ctrl+shift+l"] = { "find-replace:select-add-all", "doc:select-word" },
  ["ctrl+/"] = "doc:toggle-line-comments",
  ["ctrl+shift+/"] = "doc:toggle-block-comments",
  ["ctrl+up"] = "doc:move-lines-up",
  ["ctrl+down"] = "doc:move-lines-down",
  ["ctrl+shift+d"] = "doc:duplicate-lines",
  ["ctrl+shift+k"] = "doc:delete-lines",

  ["left"] = { "doc:move-to-previous-char", "dialog:previous-entry" },
  ["right"] = { "doc:move-to-next-char", "dialog:next-entry"},
  ["up"] = { "command:select-previous", "doc:move-to-previous-line" },
  ["down"] = { "command:select-next", "doc:move-to-next-line" },
  ["ctrl+left"] = "doc:move-to-previous-word-start",
  ["ctrl+right"] = "doc:move-to-next-word-end",
  ["ctrl+["] = "doc:move-to-previous-block-start",
  ["ctrl+]"] = "doc:move-to-next-block-end",
  ["home"] = "doc:move-to-start-of-indentation",
  ["end"] = "doc:move-to-end-of-line",
  ["ctrl+home"] = "doc:move-to-start-of-doc",
  ["ctrl+end"] = "doc:move-to-end-of-doc",
  ["pageup"] = "doc:move-to-previous-page",
  ["pagedown"] = "doc:move-to-next-page",

  ["shift+1lclick"] = "doc:select-to-cursor",
  ["ctrl+1lclick"] = "doc:split-cursor",
  ["1lclick"] = "doc:set-cursor",
  ["2lclick"] = { "doc:set-cursor-word", "emptyview:new-doc", "tabbar:new-doc" },
  ["3lclick"] = "doc:set-cursor-line",
  ["mclick"] = "doc:paste-primary-selection",
  ["shift+left"] = "doc:select-to-previous-char",
  ["shift+right"] = "doc:select-to-next-char",
  ["shift+up"] = "doc:select-to-previous-line",
  ["shift+down"] = "doc:select-to-next-line",
  ["ctrl+shift+left"] = "doc:select-to-previous-word-start",
  ["ctrl+shift+right"] = "doc:select-to-next-word-end",
  ["ctrl+shift+["] = "doc:select-to-previous-block-start",
  ["ctrl+shift+]"] = "doc:select-to-next-block-end",
  ["shift+home"] = "doc:select-to-start-of-indentation",
  ["shift+end"] = "doc:select-to-end-of-line",
  ["ctrl+shift+home"] = "doc:select-to-start-of-doc",
  ["ctrl+shift+end"] = "doc:select-to-end-of-doc",
  ["shift+pageup"] = "doc:select-to-previous-page",
  ["shift+pagedown"] = "doc:select-to-next-page",
  ["ctrl+shift+up"] = "doc:create-cursor-previous-line",
  ["ctrl+shift+down"] = "doc:create-cursor-next-line"
}

return keymap
