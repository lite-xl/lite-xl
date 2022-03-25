local common = require "core.common"

local syntax = {}
syntax.items = {}

local plain_text_syntax = { name = "Plain Text", patterns = {}, symbols = {} }


function syntax.add(t)
  -- this rule gives us a performance gain for the tokenizer in lines with
  -- long amounts of consecutive spaces without affecting other patterns
  if t.patterns then
    table.insert(t.patterns, 1, { pattern = "%s+", type = "normal" })
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
