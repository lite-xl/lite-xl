local core = require "core"
local syntax = require "core.syntax"
local common = require "core.common"

local tokenizer = {}
local bad_patterns = {}

local function push_token(t, type, text)
  type = type or "normal"
  local prev_type = t[#t-1]
  local prev_text = t[#t]
  if prev_type and (prev_type == type or prev_text:ufind("^%s*$")) then
    t[#t-1] = type
    t[#t] = prev_text .. text
  else
    table.insert(t, type)
    table.insert(t, text)
  end
end


local function push_tokens(t, syn, pattern, full_text, find_results)
  if #find_results > 2 then
    -- We do some manipulation with find_results so that it's arranged
    -- like this:
    -- { start, end, i_1, i_2, i_3, …, i_last }
    -- Each position spans characters from i_n to ((i_n+1) - 1), to form
    -- consecutive spans of text.
    --
    -- If i_1 is not equal to start, start is automatically inserted at
    -- that index.
    if find_results[3] ~= find_results[1] then
      table.insert(find_results, 3, find_results[1])
    end
    -- Copy the ending index to the end of the table, so that an ending index
    -- always follows a starting index after position 3 in the table.
    table.insert(find_results, find_results[2] + 1)
    -- Then, we just iterate over our modified table.
    for i = 3, #find_results - 1 do
      local start = find_results[i]
      local fin = find_results[i + 1] - 1
      local type = pattern.type[i - 2]
        -- ↑ (i - 2) to convert from [3; n] to [1; n]
      local text = full_text:usub(start, fin)
      push_token(t, syn.symbols[text] or type, text)
    end
  else
    local start, fin = find_results[1], find_results[2]
    local text = full_text:usub(start, fin)
    push_token(t, syn.symbols[text] or pattern.type, text)
  end
end


-- State is a 32-bit number that is four separate bytes, illustrating how many
-- differnet delimiters we have open, and which subsyntaxes we have active.
-- At most, there are 3 subsyntaxes active at the same time. Beyond that,
-- does not support further highlighting.

-- You can think of it as a maximum 4 integer (0-255) stack. It always has
-- 1 integer in it. Calling `push_subsyntax` increases the stack depth. Calling
-- `pop_subsyntax` decreases it. The integers represent the index of a pattern
-- that we're following in the syntax. The top of the stack can be any valid
-- pattern index, any integer lower in the stack must represent a pattern that
-- specifies a subsyntax.

-- If you do not have subsyntaxes in your syntax, the three most
-- singificant numbers will always be 0, the stack will only ever be length 1
-- and the state variable will only ever range from 0-255.
local function retrieve_syntax_state(incoming_syntax, state)
  local current_syntax, subsyntax_info, current_pattern_idx, current_level =
    incoming_syntax, nil, state, 0
  if state > 0 and (state > 255 or current_syntax.patterns[state].syntax) then
    -- If we have higher bits, then decode them one at a time, and find which
    -- syntax we're using. Rather than walking the bytes, and calling into
    -- `syntax` each time, we could probably cache this in a single table.
    for i = 0, 2 do
      local target = bit32.extract(state, i*8, 8)
      if target ~= 0 then
        if current_syntax.patterns[target].syntax then
          subsyntax_info = current_syntax.patterns[target]
          current_syntax = type(subsyntax_info.syntax) == "table" and
            subsyntax_info.syntax or syntax.get(subsyntax_info.syntax)
          current_pattern_idx = 0
          current_level = i+1
        else
          current_pattern_idx = target
          break
        end
      else
        break
      end
    end
  end
  return current_syntax, subsyntax_info, current_pattern_idx, current_level
end

local function report_bad_pattern(log_fn, syntax, pattern_idx, msg, ...)
  if not bad_patterns[syntax] then
    bad_patterns[syntax] = { }
  end
  if bad_patterns[syntax][pattern_idx] then return end
  bad_patterns[syntax][pattern_idx] = true
  log_fn("Malformed pattern #%d in %s language plugin. " .. msg,
            pattern_idx, syntax.name or "unnamed", ...)
end

---@param incoming_syntax table
---@param text string
---@param state integer
function tokenizer.tokenize(incoming_syntax, text, state)
  local res = {}
  local i = 1

  if #incoming_syntax.patterns == 0 then
    return { "normal", text }
  end

  state = state or 0
  -- incoming_syntax    : the parent syntax of the file.
  -- state              : a 32-bit number representing syntax state (see above)

  -- current_syntax     : the syntax we're currently in.
  -- subsyntax_info     : info about the delimiters of this subsyntax.
  -- current_pattern_idx: the index of the pattern we're on for this syntax.
  -- current_level      : how many subsyntaxes deep we are.
  local current_syntax, subsyntax_info, current_pattern_idx, current_level =
    retrieve_syntax_state(incoming_syntax, state)

  -- Should be used to set the state variable. Don't modify it directly.
  local function set_subsyntax_pattern_idx(pattern_idx)
    current_pattern_idx = pattern_idx
    state = bit32.replace(state, pattern_idx, current_level*8, 8)
  end


  local function push_subsyntax(entering_syntax, pattern_idx)
    set_subsyntax_pattern_idx(pattern_idx)
    current_level = current_level + 1
    subsyntax_info = entering_syntax
    current_syntax = type(entering_syntax.syntax) == "table" and
      entering_syntax.syntax or syntax.get(entering_syntax.syntax)
    current_pattern_idx = 0
  end

  local function pop_subsyntax()
    set_subsyntax_pattern_idx(0)
    current_level = current_level - 1
    set_subsyntax_pattern_idx(0)
    current_syntax, subsyntax_info, current_pattern_idx, current_level =
      retrieve_syntax_state(incoming_syntax, state)
  end

  local function find_text(text, p, offset, at_start, close)
    local target, res = p.pattern or p.regex, { 1, offset - 1 }
    local p_idx = close and 2 or 1
    local code = type(target) == "table" and target[p_idx] or target

    if p.whole_line == nil then p.whole_line = { } end
    if p.whole_line[p_idx] == nil then
      -- Match patterns that start with '^'
      p.whole_line[p_idx] = code:umatch("^%^") and true or false
      if p.whole_line[p_idx] then
        -- Remove '^' from the beginning of the pattern
        if type(target) == "table" then
          target[p_idx] = code:usub(2)
        else
          p.pattern = p.pattern and code:usub(2)
          p.regex = p.regex and code:usub(2)
        end
      end
    end

    if p.regex and type(p.regex) ~= "table" then
      p._regex = p._regex or regex.compile(p.regex)
      code = p._regex
    end

    repeat
      local next = res[2] + 1
      -- If the pattern contained '^', allow matching only the whole line
      if p.whole_line[p_idx] and next > 1 then
        return
      end
      res = p.pattern and { text:ufind((at_start or p.whole_line[p_idx]) and "^" .. code or code, next) }
        or { regex.match(code, text, text:ucharpos(next), (at_start or p.whole_line[p_idx]) and regex.ANCHORED or 0) }
      if p.regex and #res > 0 then -- set correct utf8 len for regex result
        local char_pos_1 = string.ulen(text:sub(1, res[1]))
        local char_pos_2 = char_pos_1 + string.ulen(text:sub(res[1], res[2])) - 1
        -- `regex.match` returns group results as a series of `begin, end`
        -- we only want `begin`s
        if #res >= 3 then
          res[3] = char_pos_1 + string.ulen(text:sub(res[1], res[3])) - 1
        end
        for i=1,(#res-3) do
          local curr = i + 3
          local from = i * 2 + 3
          if from < #res then
            res[curr] = char_pos_1 + string.ulen(text:sub(res[1], res[from])) - 1
          else
            res[curr] = nil
          end
        end
        res[1] = char_pos_1
        res[2] = char_pos_2
      end
      if res[1] and target[3] then
        -- Check to see if the escaped character is there,
        -- and if it is not itself escaped.
        local count = 0
        for i = res[1] - 1, 1, -1 do
          if text:ubyte(i) ~= target[3]:ubyte() then break end
          count = count + 1
        end
        if count % 2 == 0 then
          -- The match is not escaped, so confirm it
          break
        elseif not close then
          -- The *open* match is escaped, so avoid it
          return
        end
      end
    until not res[1] or not close or not target[3]
    return table.unpack(res)
  end

  local text_len = text:ulen()
  while i <= text_len do
    -- continue trying to match the end pattern of a pair if we have a state set
    if current_pattern_idx > 0 then
      local p = current_syntax.patterns[current_pattern_idx]
      local s, e = find_text(text, p, i, false, true)

      local cont = true
      -- If we're in subsyntax mode, always check to see if we end our syntax
      -- first, before the found delimeter, as ending the subsyntax takes
      -- precedence over ending the delimiter in the subsyntax.
      if subsyntax_info then
        local ss, se = find_text(text, subsyntax_info, i, false, true)
        -- If we find that we end the subsyntax before the
        -- delimiter, push the token, and signal we shouldn't
        -- treat the bit after as a token to be normally parsed
        -- (as it's the syntax delimiter).
        if ss and (s == nil or ss < s) then
          push_token(res, p.type, text:usub(i, ss - 1))
          i = ss
          cont = false
        end
      end
      -- If we don't have any concerns about syntax delimiters,
      -- continue on as normal.
      if cont then
        if s then
          push_token(res, p.type, text:usub(i, e))
          set_subsyntax_pattern_idx(0)
          i = e + 1
        else
          push_token(res, p.type, text:usub(i))
          break
        end
      end
    end
    -- General end of syntax check. Applies in the case where
    -- we're ending early in the middle of a delimiter, or
    -- just normally, upon finding a token.
    if subsyntax_info then
      local s, e = find_text(text, subsyntax_info, i, true, true)
      if s then
        push_token(res, subsyntax_info.type, text:usub(i, e))
        -- On finding unescaped delimiter, pop it.
        pop_subsyntax()
        i = e + 1
      end
    end

    -- find matching pattern
    local matched = false
    for n, p in ipairs(current_syntax.patterns) do
      local find_results = { find_text(text, p, i, true, false) }
      if find_results[1] then
        local type_is_table = type(p.type) == "table"
        local n_types = type_is_table and #p.type or 1
        if #find_results == 2 and type_is_table then
          report_bad_pattern(core.warn, current_syntax, n,
            "Token type is a table, but a string was expected.")
          p.type = p.type[1]
        elseif #find_results - 1 > n_types then
          report_bad_pattern(core.error, current_syntax, n,
            "Not enough token types: got %d needed %d.", n_types, #find_results - 1)
        elseif #find_results - 1 < n_types then
          report_bad_pattern(core.warn, current_syntax, n,
            "Too many token types: got %d needed %d.", n_types, #find_results - 1)
        end
        -- matched pattern; make and add tokens
        push_tokens(res, current_syntax, p, text, find_results)
        -- update state if this was a start|end pattern pair
        if type(p.pattern or p.regex) == "table" then
          -- If we have a subsyntax, push that onto the subsyntax stack.
          if p.syntax then
            push_subsyntax(p, n)
          else
            set_subsyntax_pattern_idx(n)
          end
        end
        -- move cursor past this token
        i = find_results[2] + 1
        matched = true
        break
      end
    end

    -- consume character if we didn't match
    if not matched then
      push_token(res, "normal", text:usub(i, i))
      i = i + 1
    end
  end

  return res, state
end


local function iter(t, i)
  i = i + 2
  local type, text = t[i], t[i+1]
  if type then
    return i, type, text
  end
end

function tokenizer.each_token(t)
  return iter, t, -1
end


return tokenizer
