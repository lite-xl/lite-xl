local common = require "core.common"
local config = require "core.config"

-- functions for translating a Doc position to another position these functions
-- can be passed to Doc:move_to|select_to|delete_to()

local translate = {}


local function is_non_word(char)
  return config.non_word_chars:find(char, nil, true)
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


function translate.up_to_word(doc, line, col)
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
  return line, col
end


function translate.next_word_end(doc, line, col)
  line, col = translate.up_to_word(doc, line, col)
  return translate.end_of_word(doc, line, col)
end


function translate.next_word_begin(doc, line, col)
  line, col = translate.end_of_word(doc, line, col)
  return translate.up_to_word(doc, line, col)
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


function translate.start_of_line_content(doc, line, col)
  return translate.up_to_word(doc, line, 1)
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


function translate.inside_delimiters(doc, line, col, delims, outer)
  print('translate.inside_delimiters', delims[2], outer)
  local line1, col1 = line, col
  while true do
    local lineb, colb = doc:position_offset(line1, col1, -1)
    local char = doc:get_char(lineb, colb)
    if char == delims[1]
    or line1 == lineb and col1 == colb then
      break
    end
    line1, col1 = lineb, colb
  end

  if outer then
    line1, col1 = doc:position_offset(line1, col1, -1)
  end

  local line2, col2 = line, col
  while true do
    local linef, colf = doc:position_offset(line2, col2, 1)
    local char = doc:get_char(line2, col2)
    if char == delims[2]
    or linef == line2 and colf == col2 then
      break
    end
    line2, col2 = linef, colf
  end

  if outer then
    line2, col2 = doc:position_offset(line2, col2, 1)
    while doc:get_char(line2, col2) == ' ' do
      local nline2, ncol2 = doc:position_offset(line2, col2, 1)
      if nline2 == line2 and ncol2 == col2 then break end
      line2, col2 = nline2, ncol2
    end
  end

  return line1, col1, line2, col2
end


return translate
