local common = require "core.common"

local syntax = {}
syntax.items = {}

local plain_text_syntax = { name = "Plain Text", patterns = {}, symbols = {} }


function syntax.add(t)
  -- the rule %s+ gives us a performance gain for the tokenizer in lines with
  -- long amounts of consecutive spaces, to not affect other patterns we
  -- insert it after any rule that starts with spaces to prevent conflicts
  if t.patterns then
    local temp_patterns = {}
    ::pattern_remove_loop::
    for pos, pattern in ipairs(t.patterns) do
      local pattern_str = ""
      local ptype = pattern.pattern
        and "pattern" or (pattern.regex and "regex" or nil)
      if ptype then
        if type(pattern[ptype]) == "table" then
          pattern_str = pattern[ptype][1]
        else
          pattern_str = pattern[ptype]
        end
        if (ptype == "pattern" and(
            pattern_str:find("^%^?%%s")
            or
            pattern_str:find("^%^?%s")
          ))
          or
          (ptype == "regex" and (
            pattern_str:find("^%^?\\s")
            or
            pattern_str:find("^%^?%s")
          ))
        then
          table.insert(temp_patterns, table.remove(t.patterns, pos))
          -- since we are removing from iterated table we need to start
          -- from the beginning again to prevent any issues
          goto pattern_remove_loop
        end
      end
    end
    for pos, pattern in ipairs(temp_patterns) do
      table.insert(t.patterns, pos, pattern)
    end
    local pos = 1
    if #temp_patterns > 0 then pos = #temp_patterns+1 end
    table.insert(t.patterns, pos, { pattern = "%s+", type = "normal" })
  end

  table.insert(syntax.items, t)
end


local function find(string, field)
  for i = #syntax.items, 1, -1 do
    local t = syntax.items[i]
    if common.match_pattern(string, t[field] or {}) then
      return t
    end
  end
end

function syntax.get(filename, header)
  return find(filename, "files")
      or (header and find(header, "headers"))
      or plain_text_syntax
end


return syntax
