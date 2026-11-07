local common = require "core.common"
local core   = require "core"

local syntax = {}
syntax.items = {}

syntax.plain_text_syntax = { name = "Plain Text", patterns = {}, symbols = {} }


-- Turn one delimiter of a pattern entry into the form the tokenizer executes:
-- a leading '^' (the "match only at the start of the line" marker) is split
-- off into `whole_line` and stripped from the body, and a regex body is
-- compiled once here rather than on every match. `err` is set, and left for
-- the caller to report, if the delimiter does not compile or matches "".
---@param is_regex boolean
---@param raw string
local function compile_delimiter(is_regex, raw)
  local whole_line = raw:umatch("^%^") ~= nil
  local body = whole_line and raw:usub(2) or raw
  local d = { regex = is_regex, whole_line = whole_line }
  if is_regex then
    local rx, cerr = regex.compile(body)
    if not rx then d.err = cerr or "Malformed regex"; return d end
    d.rx = rx
    local mstart, mend = regex.find_offsets(rx, "")
    if mstart and mstart > mend then d.err = "Regex matches an empty string" end
  else
    d.lua = body
    d.lua_anchored = "^" .. body
    local ok, mstart, mend = pcall(string.ufind, "", body)
    if not ok then
      d.err = mstart --[[@as string]]
    elseif mstart and mstart > mend then
      d.err = "Pattern matches an empty string"
    end
  end
  return d
end

---Precompile a pattern entry into `entry._compiled` (idempotent):
---  { [1] = <delimiter>, [2] = <delimiter|nil>, esc_byte = <int|nil>,
---    err = <string|nil> }
---A malformed entry is also marked `disabled`, exactly as before. Exposed so
---the tokenizer can compile an entry a plugin injected after `syntax.add`.
---@param entry table
---@return table compiled
function syntax.precompile_pattern(entry)
  if entry._compiled then return entry._compiled end
  local raw = entry.pattern or entry.regex
  local is_regex = entry.regex ~= nil
  local c
  if type(raw) == "table" then
    if type(raw[1]) ~= "string" or type(raw[2]) ~= "string" then
      c = { err = "A delimited pattern needs a start and an end string" }
    else
      c = {
        compile_delimiter(is_regex, raw[1]),
        compile_delimiter(is_regex, raw[2]),
      }
      if type(raw[3]) == "string" and #raw[3] > 0 then c.esc_byte = raw[3]:byte() end
    end
  elseif type(raw) == "string" then
    c = { compile_delimiter(is_regex, raw) }
  else
    c = { err = "Missing pattern or regex" }
  end
  for j = 1, 2 do
    if c[j] and c[j].err then c.err = c.err or c[j].err end
  end
  if c.err then entry.disabled = true end
  entry._compiled = c
  return c
end

function syntax.add(t)
  if type(t.space_handling) ~= "boolean" then t.space_handling = true end

  if t.patterns then
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

    -- compile every pattern up front, so the tokenizer never rewrites an entry
    -- mid-scan, and report the malformed ones
    for i, pattern in ipairs(t.patterns) do
      local c = syntax.precompile_pattern(pattern)
      if c.err then
        core.warn("Malformed pattern #%d <%s> in %s language plugin: %s",
          i, tostring(pattern.pattern or pattern.regex), t.name or "?", c.err)
      end
    end
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
      or syntax.plain_text_syntax
end


return syntax
