local common = require "core.common"

local syntax = {}
syntax.items = {}

local plain_text_syntax = { name = "Plain Text", patterns = {}, symbols = {} }

-- Return true on any access
local catch_all = {}
function catch_all.__index()
  return true
end

function syntax.add(t)
  if type(t.space_handling) ~= "boolean" then t.space_handling = true end

  if t.patterns then
    -- Transform `one_of` tables from arrays to hash maps
    -- This allows searching directly without having to scan the entire array
    for _,p in pairs(t.patterns) do
      if p.one_of then
        local compiled_parts = { }
        for _,part in pairs(p.one_of) do
          local compiled_values = { }
          if #part == 0 then
            -- Match with anything
            setmetatable(compiled_values, catch_all)
          else
            for _,value in pairs(part) do
              compiled_values[value] = true
            end
          end
          table.insert(compiled_parts, compiled_values)
        end
        p.one_of = compiled_parts
      end
    end
  
    -- the rule %s+ gives us a performance gain for the tokenizer in lines with
    -- long amounts of consecutive spaces, can be disabled by plugins where it
    -- causes conflicts by declaring the table property: space_handling = false
    if t.space_handling then
      table.insert(t.patterns, { pattern = "%s+", type = "normal" })
    end

    -- this rule gives us additional performance gain by matching every word
    -- that was not matched by the syntax patterns as a single token, preventing
    -- the tokenizer from iterating over each character individually which is a
    -- lot slower since iteration occurs in lua instead of C and adding to that
    -- it will also try to match every pattern to a single char (same as spaces)
    table.insert(t.patterns, { pattern = "%w+%f[%s]", type = "normal" })
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
