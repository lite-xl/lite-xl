-- lite-xl 1.16

local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"

-- Takes the following pattern: /pattern/replace/
-- Capture groupings can be replaced using \1 through \9
local function regex_replace_file(pattern)
  local doc = core.active_view.doc
  
  local start_pattern = 2;
  local end_pattern = 2
  repeat 
    end_pattern = string.find(pattern, "/", end_pattern)
  until end_pattern == nil or pattern[end_pattern-1] ~= "\\"
  if end_pattern == nil then
    core.log("Can't find end to pattern.")
    return
  end
  end_pattern = end_pattern - 1
  local start_replacement = end_pattern+2;
  local end_replacement = end_pattern+2;
  repeat
    end_replacement = string.find(pattern, "/", end_replacement)
  until end_replacement == nil or pattern[end_replacement-1] ~= "\\"
  if end_replacement == nil then
    core.log("Can't find end to replacement.")
    return
  end
  end_replacement = end_replacement - 1
  
  local re = regex.compile(pattern:sub(start_pattern, end_pattern))
  local replacement = pattern:sub(start_replacement, end_replacement)
  for i=1,#doc.lines do
      local old_length = #doc.lines[i]
      local old_text = doc:get_text(i, 1, i, old_length)
      local new_text = regex.gsub(re, old_text, replacement)
      if old_text ~= new_text then
        doc:insert(i, old_length, new_text)
        doc:remove(i, 1, i, old_length)
      end
  end
end

local initial_regex_replace = "/"
command.add("core.docview", {
  ["regex:find-replace"] = function()
    core.command_view:set_text(initial_regex_replace)
    core.command_view:enter("Regex Replace (enter pattern as /old/new/)", function(pattern)
    regex_replace_file(pattern)
    initial_regex_replace = pattern
  end) end
})


keymap.add { ["ctrl+shift+r"] = "regex:find-replace" }
