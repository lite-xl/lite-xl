local common = require "core.common"
local core   = require "core"

local syntax = {}
syntax.items = {}

local plain_text_syntax = { name = "Plain Text", patterns = {}, symbols = {} }


---Checks whether the pattern / regex compiles correctly and matches something.
---A pattern / regex must not match an empty string.
---@param pattern_type "regex"|"pattern"
---@param pattern string
---@return boolean ok
---@return string? error
local function check_pattern(pattern_type, pattern)
  local ok, err, mstart, mend
  if pattern_type == "regex" then
    ok, err = regex.compile(pattern)
    if ok then
      mstart, mend = regex.find_offsets(ok, "")
      if mstart and mstart > mend then
        ok, err = false, "Regex matches an empty string"
      end
    end
  else
    ok, mstart, mend = pcall(string.ufind, "", pattern)
    if ok and mstart and mstart > mend then
      ok, err = false, "Pattern matches an empty string"
    elseif not ok then
      err = mstart --[[@as string]]
    end
  end
  return ok --[[@as boolean]], err
end

function syntax.add(t)
  if type(t.space_handling) ~= "boolean" then t.space_handling = true end

  if t.patterns then
    -- do a sanity check on the patterns / regex to make sure they are actually correct
    for i, pattern in ipairs(t.patterns) do
      local p, ok, err, name = pattern.pattern or pattern.regex, nil, nil, nil
      if type(p) == "table" then
        for j = 1, 2 do
          ok, err = check_pattern(pattern.pattern and "pattern" or "regex", p[j])
          if not ok then name = string.format("#%d:%d <%s>", i, j, p[j]) end
        end
      elseif type(p) == "string" then
        ok, err = check_pattern(pattern.pattern and "pattern" or "regex", p)
        if not ok then name = string.format("#%d <%s>", i, p) end
      else
        ok, err, name = false, "Missing pattern or regex", "#"..i
      end
      if not ok then
        pattern.disabled = true
        core.warn("Malformed pattern %s in %s language plugin: %s", name, t.name, err)
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
  local best_match = 0
  local best_syntax
  for i = #syntax.items, 1, -1 do
    local t = syntax.items[i]
    local s, e = common.match_pattern(string, t[field] or {})
    if s and e - s > best_match then
      best_match = e - s
      best_syntax = t
    end
  end
  return best_syntax
end

function syntax.get(filename, header)
  return (filename and find(filename, "files"))
      or (header and find(header, "headers"))
      or plain_text_syntax
end


return syntax
