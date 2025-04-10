local common = require "core.common"
local config = require "core.config"

-- functions for translating a Doc position to another position these functions
-- can be passed to Doc:move_to|select_to|delete_to()

local translate = {}


local function is_non_word(char)
  return config.non_word_chars:find(char, nil, true)
end


local function is_word(char)
  return not config.non_word_chars:find(char, nil, true)
end


local function is_symbol(char)
  return config.symbol_chars:find(char, nil, true)
end


local function is_space(char)
  return config.space_chars:find(char, nil, true)
end


function translate.previous_char(doc, line, col)
  repeat
    line, col = doc:position_offset(line, col, -1)
  until not common.is_utf8_cont(doc:get_char(line, col))
  return line, col
end


function translate.next_char(doc, line, col)
  repeat
    line, col = doc:position_offset(line, col, 1)
  until not common.is_utf8_cont(doc:get_char(line, col))
  return line, col
end


function translate.previous_word_start(doc, line, col)
  local prev
  while line > 1 or col > 1 do
    local l, c = doc:position_offset(line, col, -1)
    local char = doc:get_char(l, c)
    if prev and prev ~= char or not is_non_word(char) then
      break
    end
    prev, line, col = char, l, c
  end
  return translate.start_of_word(doc, line, col)
end


function translate.next_word_end(doc, line, col)
  local prev
  local end_line, end_col = translate.end_of_doc(doc, line, col)
  while line < end_line or col < end_col do
    local char = doc:get_char(line, col)
    if prev and prev ~= char or not is_non_word(char) then
      break
    end
    line, col = doc:position_offset(line, col, 1)
    prev = char
  end
  return translate.end_of_word(doc, line, col)
end


function translate.skip_chars_left(doc, line, col, skip_fn)
  while true do
    local lnext, cnext = doc:position_offset(line, col, -1)
    local char = doc:get_char(lnext, cnext)
    -- if not on char or at start of doc
    if not skip_fn(char) or (line == lnext and col == cnext) then
      break
    end
    line, col = lnext, cnext
  end
  return line, col
end


function translate.skip_chars_right(doc, line, col, skip_fn)
  while true do
    local lnext, cnext = doc:position_offset(line, col, 1)
    local char = doc:get_char(line, col) -- start at currrent position
    -- if not on char or at end of doc
    if not skip_fn(char) or (line == lnext and col == cnext) then
      break
    end
    line, col = lnext, cnext
  end
  return line, col
end


function translate.word_left(doc, line, col)
  local lnext, cnext = doc:position_offset(line, col, -1)
  local char = doc:get_char(lnext, cnext)

  if col > 1 then -- linewise only
    if not is_space(char) then
      return translate.skip_chars_left(doc, lnext, cnext, is_word(char) and is_word or is_symbol)
    end
    -- try again skipping one space
    lnext, cnext = doc:position_offset(lnext, cnext, -1)
    char = doc:get_char(lnext, cnext)
    if not is_space(char) then
      return translate.skip_chars_left(doc, lnext, cnext, is_word(char) and is_word or is_symbol)
    end
  end

  return translate.skip_chars_left(doc, lnext, cnext, is_space)
end


function translate.word_right(doc, line, col)
  local char = doc:get_char(line, col)
  local lnext, cnext = doc:position_offset(line, col, 1)

  if cnext > 1 then -- linewise only
    if not is_space(char) then
      return translate.skip_chars_right(doc, line, col, is_word(char) and is_word or is_symbol)
    end
    -- try again skipping one space
    char = doc:get_char(lnext, cnext)
    if not is_space(char) then
      return translate.skip_chars_right(doc, lnext, cnext, is_word(char) and is_word or is_symbol)
    end
  end

  return translate.skip_chars_right(doc, lnext, cnext, is_space)
end


function translate.start_of_word(doc, line, col)
  while true do
    local line2, col2 = doc:position_offset(line, col, -1)
    local char = doc:get_char(line2, col2)
    if is_non_word(char)
    or line == line2 and col == col2 then
      break
    end
    line, col = line2, col2
  end
  return line, col
end


function translate.end_of_word(doc, line, col)
  while true do
    local line2, col2 = doc:position_offset(line, col, 1)
    local char = doc:get_char(line, col)
    if is_non_word(char)
    or line == line2 and col == col2 then
      break
    end
    line, col = line2, col2
  end
  return line, col
end


function translate.previous_block_start(doc, line, col)
  while true do
    line = line - 1
    if line <= 1 then
      return 1, 1
    end
    if doc.lines[line-1]:find("^%s*$")
    and not doc.lines[line]:find("^%s*$") then
      return line, (doc.lines[line]:find("%S"))
    end
  end
end


function translate.next_block_end(doc, line, col)
  while true do
    if line >= #doc.lines then
      return #doc.lines, 1
    end
    if doc.lines[line+1]:find("^%s*$")
    and not doc.lines[line]:find("^%s*$") then
      return line+1, #doc.lines[line+1]
    end
    line = line + 1
  end
end


function translate.start_of_line(doc, line, col)
  return line, 1
end

function translate.start_of_indentation(doc, line, col)
  local s, e = doc.lines[line]:find("^%s*")
  return line, col > e + 1 and e + 1 or 1
end

function translate.end_of_line(doc, line, col)
  return line, math.huge
end


function translate.start_of_doc(doc, line, col)
  return 1, 1
end


function translate.end_of_doc(doc, line, col)
  return #doc.lines, #doc.lines[#doc.lines]
end


return translate
