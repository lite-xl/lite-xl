local command = require "core.command"
local keymap = {}

keymap.modkeys = {}
keymap.map = {}
keymap.reverse_map = {}

local macos = PLATFORM == "Mac OS X"

-- Thanks to mathewmariani, taken from his lite-macos github repository.
local modkeys_os = require("core.modkeys-" .. (macos and "macos" or "generic"))
local modkey_map = modkeys_os.map
local modkeys = modkeys_os.keys

local function key_to_stroke(k)
  local stroke = ""
  for _, mk in ipairs(modkeys) do
    if keymap.modkeys[mk] then
      stroke = stroke .. mk .. "+"
    end
  end
  return stroke .. k
end


function keymap.add_direct(map)
  for stroke, commands in pairs(map) do
    if type(commands) == "string" then
      commands = { commands }
    end
    keymap.map[stroke] = commands
    for _, cmd in ipairs(commands) do
      keymap.reverse_map[cmd] = stroke
    end
  end
end

function keymap.add(map, overwrite)
  for stroke, commands in pairs(map) do
    if macos then
      stroke = stroke:gsub("%f[%a]ctrl%f[%A]", "cmd")
    end
    if type(commands) == "string" then
      commands = { commands }
    end
    if overwrite then
      keymap.map[stroke] = commands
    else
      keymap.map[stroke] = keymap.map[stroke] or {}
      for i = #commands, 1, -1 do
        table.insert(keymap.map[stroke], 1, commands[i])
      end
    end
    for _, cmd in ipairs(commands) do
      keymap.reverse_map[cmd] = stroke
    end
  end
end


function keymap.get_binding(cmd)
  return keymap.reverse_map[cmd]
end


function keymap.on_key_pressed(k)
  local mk = modkey_map[k]
  if mk then
    keymap.modkeys[mk] = true
    -- work-around for windows where `altgr` is treated as `ctrl+alt`
    if mk == "altgr" then
      keymap.modkeys["ctrl"] = false
    end
  else
    local stroke = key_to_stroke(k)
    local commands = keymap.map[stroke]
    if commands then
      for _, cmd in ipairs(commands) do
        local performed = command.perform(cmd)
        if performed then break end
      end
      return true
    end
  end
  return false
end


function keymap.on_key_released(k)
  local mk = modkey_map[k]
  if mk then
    keymap.modkeys[mk] = false
  end
end


if macos then
  local keymap_macos = require("core.keymap-macos")
  keymap_macos(keymap)
  return keymap
end

keymap.add_direct {
  ["ctrl+shift+p"] = "core:find-command",
  ["ctrl+p"] = "core:find-file",
  ["ctrl+o"] = "core:open-file",
  ["ctrl+n"] = "core:new-doc",
  ["ctrl+shift+c"] = "core:change-project-folder",
  ["ctrl+shift+o"] = "core:open-project-folder",
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
