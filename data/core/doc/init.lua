local Object = require "core.object"
local translate = require ".translate"
local core = require "core"
local syntax = require "core.syntax"
local config = require "core.config"
local common = require "core.common"

---@class core.doc : core.object
local Doc = Object:extend()

function Doc:__tostring() return "Doc" end

local function split_lines(text)
  local res = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    table.insert(res, line)
  end
  return res
end


function Doc:new(filename, abs_filename, new_file)
  self.new_file = new_file
  self.listeners = setmetatable({}, { __mode = "v" })
  self:reset()
  if filename then
    self:set_filename(filename, abs_filename)
    if not new_file then
      self:load(abs_filename)
    end
  end
  if new_file then
    self.crlf = config.line_endings == "crlf"
  end
end

function Doc:reset()
  self.lines = { "\n" }
  self.undo_stack = { idx = 1 }
  self.redo_stack = { idx = 1 }
  self.clean_change_id = 1
  self.overwrite = false
  self:reset_syntax()
end

function Doc:reset_syntax()
  local header = self:get_text(1, 1, self:position_offset(1, 1, 128))
  local path = self.abs_filename
  if not path and self.filename then
    path = core.project_dir .. PATHSEP .. self.filename
  end
  if path then path = common.normalize_path(path) end
  self.syntax = syntax.get(path, header)
  for i,v in ipairs(self.listeners) do v:on_doc_change("reset") end
end

function Doc:set_filename(filename, abs_filename)
  if filename ~= self.filename or abs_filename ~= self.abs_filename then
    self.filename = filename
    self.abs_filename = abs_filename
    self:reset_syntax()
  end
end

function Doc:load(filename)
  local fp = assert(io.open(filename, "rb"))
  self:reset()
  self.lines = {}
  local i = 1
  for line in fp:lines() do
    if line:byte(-1) == 13 then
      line = line:sub(1, -2)
      self.crlf = true
    end
    table.insert(self.lines, line .. "\n")
    i = i + 1
  end
  if #self.lines == 0 then
    table.insert(self.lines, "\n")
  end
  fp:close()
  self:reset_syntax()
end

function Doc:reload()
  if self.filename then
    self:load(self.abs_filename)
    self:clean()
  end
end

function Doc:save(filename, abs_filename)
  if not filename then
    assert(self.filename, "no filename set to default to")
    filename = self.filename
    abs_filename = self.abs_filename
  else
    assert(self.filename or abs_filename, "calling save on unnamed doc without absolute path")
  end

  local fp
  if PLATFORM == "Windows" then
    -- On Windows, opening a hidden file with wb fails with a permission error.
    -- To get around this, we must open the file as r+b and truncate.
    -- Since r+b fails if file doesn't exist, fall back to wb.
    fp = io.open(abs_filename, "r+b")
    if fp then
      system.ftruncate(fp)
    else
      -- file probably doesn't exist, create one
      fp = assert (io.open(abs_filename, "wb"))
    end
  else
    fp = assert (io.open(abs_filename, "wb"))
  end

  for _, line in ipairs(self.lines) do
    if self.crlf then line = line:gsub("\n", "\r\n") end
    fp:write(line)
  end
  fp:close()
  self:set_filename(filename, abs_filename)
  self.new_file = false
  self:clean()
end

function Doc:get_name()
  return self.filename or "unsaved"
end

function Doc:is_dirty()
  if self.new_file then
    if self.filename then return true end
    return #self.lines > 1 or #self.lines[1] > 1
  else
    return self.clean_change_id ~= self:get_change_id()
  end
end

function Doc:clean()
  self.clean_change_id = self:get_change_id()
end

function Doc:get_indent_info()
  if not self.indent_info then return config.tab_type, config.indent_size, false end
  return self.indent_info.type or config.tab_type,
      self.indent_info.size or config.indent_size,
      self.indent_info.confirmed
end

function Doc:get_change_id()
  return self.undo_stack.idx
end

function Doc:sanitize_position(line, col)
  local nlines = #self.lines
  if line > nlines then
    return nlines, #self.lines[nlines]
  elseif line < 1 then
    return 1, 1
  end
  return line, common.clamp(col, 1, self.lines[line]:ulen())
end

function Doc:position_offset_func(line, col, fn, ...)
  line, col = self:sanitize_position(line, col)
  return fn(self, line, col, ...)
end


function Doc:position_offset_byte(line, col, offset)
  line, col = self:sanitize_position(line, col)
  col = col + offset
  while line > 1 and col < 1 do
    line = line - 1
    col = col + self.lines[line]:ulen()
  end
  while line < #self.lines and col > self.lines[line]:ulen() do
    col = col - self.lines[line]:ulen()
    line = line + 1
  end
  return self:sanitize_position(line, col)
end


function Doc:position_offset_linecol(line, col, lineoffset, coloffset)
  return self:sanitize_position(line + lineoffset, col + coloffset)
end


function Doc:position_offset(line, col, ...)
  if type(...) ~= "number" then
    return self:position_offset_func(line, col, ...)
  elseif select("#", ...) == 1 then
    return self:position_offset_byte(line, col, ...)
  elseif select("#", ...) == 2 then
    return self:position_offset_linecol(line, col, ...)
  else
    error("bad number of arguments")
  end
end

---Returns the content of the doc between two positions. </br>
---The positions will be sanitized and sorted. </br>
---The character at the "end" position is not included by default.
---@see core.doc.sanitize_position
---@param line1 integer
---@param col1 integer
---@param line2 integer
---@param col2 integer
---@param inclusive boolean? Whether or not to return the character at the last position
---@return string
function Doc:get_text(line1, col1, line2, col2, inclusive)
  line1, col1 = self:sanitize_position(line1, col1)
  line2, col2 = self:sanitize_position(line2, col2)
  local col2_offset = inclusive and 0 or 1
  line1, col1, line2, col2 = common.sort_positions(line1, col1, line2, col2)
  if line1 == line2 then
    return self.lines[line1]:usub(col1, col2 - col2_offset)
  end
  local lines = { self.lines[line1]:usub(col1) }
  for i = line1 + 1, line2 - 1 do
    table.insert(lines, self.lines[i])
  end
  table.insert(lines, self.lines[line2]:usub(1, col2 - col2_offset))
  return table.concat(lines)
end

function Doc:get_char(line, col)
  line, col = self:sanitize_position(line, col)
  return self.lines[line]:usub(col, col)
end


local function push_undo(undo_stack, time, type, ...)
  undo_stack[undo_stack.idx] = { type = type, time = time, ... }
  undo_stack[undo_stack.idx - config.max_undos] = nil
  undo_stack.idx = undo_stack.idx + 1
end


function Doc:raw_insert(line, col, text, undo_stack, time, selections)
  -- split text into lines and merge with line at insertion point
  local lines = split_lines(text)
  local len = #lines[#lines]
  local before = self.lines[line]:usub(1, col - 1)
  local after = self.lines[line]:usub(col)
  for i = 1, #lines - 1 do
    lines[i] = lines[i] .. "\n"
  end
  lines[1] = before .. lines[1]
  lines[#lines] = lines[#lines] .. after

  -- splice lines into line array
  common.splice(self.lines, line, 1, lines)

  -- push undo
  local line2, col2 = self:position_offset(line, col, #text)
  if selections then push_undo(undo_stack, time, "selection", table.unpack(selections)) end
  push_undo(undo_stack, time, "remove", line, col, line2, col2)

  for i,v in ipairs(self.listeners) do v:on_doc_change("insert", text, line, col, line, col) end
end

function Doc:raw_remove(line1, col1, line2, col2, undo_stack, time, selections)
  -- push undo
  local text = self:get_text(line1, col1, line2, col2)
  if selections then push_undo(undo_stack, time, "selection", table.unpack(selections)) end
  push_undo(undo_stack, time, "insert", line1, col1, text)

  -- get line content before/after removed text
  local before = self.lines[line1]:usub(1, col1 - 1)
  local after = self.lines[line2]:usub(col2)

  local line_removal = line2 - line1
  local col_removal = col2 - col1

  -- splice line into line array
  common.splice(self.lines, line1, line_removal + 1, { before .. after })

  local merge = false

  for i,v in ipairs(self.listeners) do v:on_doc_change("remove", "", line1, col1, line2, col2) end
end


function Doc:insert(line, col, text, selections)
  self.redo_stack = { idx = 1 }
  -- Reset the clean id when we're pushing something new before it
  if self:get_change_id() < self.clean_change_id then
    self.clean_change_id = -1
  end
  line, col = self:sanitize_position(line, col)
  self:raw_insert(line, col, text, self.undo_stack, system.get_time(), selections)
end

function Doc:remove(line1, col1, line2, col2, selections)
  self.redo_stack = { idx = 1 }
  line1, col1 = self:sanitize_position(line1, col1)
  line2, col2 = self:sanitize_position(line2, col2)
  line1, col1, line2, col2 = common.sort_positions(line1, col1, line2, col2)
  self:raw_remove(line1, col1, line2, col2, self.undo_stack, system.get_time(), selections)
end




function Doc:get_indent_string()
  local indent_type, indent_size = self:get_indent_info()
  if indent_type == "hard" then
    return "\t"
  end
  return string.rep(" ", indent_size)
end



function Doc:line_comment(comment, line1, col1, line2, col2)
  local start_comment = (type(comment) == 'table' and comment[1] or comment) .. " "
  local end_comment = (type(comment) == 'table' and " " .. comment[2])
  local uncomment = true
  local start_offset = math.huge
  for line = line1, line2 do
    local text = self.lines[line]
    local s = text:find("%S")
    if s then
      local cs, ce = text:find(start_comment, s, true)
      if cs ~= s then
        uncomment = false
      end
      start_offset = math.min(start_offset, s)
    end
  end

  local end_line = col2 == #self.lines[line2]
  for line = line1, line2 do
    local text = self.lines[line]
    local s = text:find("%S")
    if s and uncomment then
      if end_comment and text:sub(#text - #end_comment, #text - 1) == end_comment then
        self:remove(line, #text - #end_comment, line, #text)
      end
      local cs, ce = text:find(start_comment, s, true)
      if ce then
        self:remove(line, cs, line, ce + 1)
      end
    elseif s then
      self:insert(line, start_offset, start_comment)
      if end_comment then
        self:insert(line, #doc().lines[line], " " .. comment[2])
      end
    end
  end
  col1 = col1 + (col1 > start_offset and #start_comment or 0) * (uncomment and -1 or 1)
  col2 = col2 + (col2 > start_offset and #start_comment or 0) * (uncomment and -1 or 1)
  if end_comment and end_line then
    col2 = col2 + #end_comment * (uncomment and -1 or 1)
  end
  return line1, col1, line2, col2
end


function Doc:block_comment(comment, line1, col1, line2, col2)
  -- automatically skip spaces
  local word_start = self:get_text(line1, col1, line1, math.huge):find("%S")
  local word_end = self:get_text(line2, 1, line2, col2):find("%s*$")
  col1 = col1 + (word_start and (word_start - 1) or 0)
  col2 = word_end and word_end or col2

  local block_start = self:get_text(line1, col1, line1, col1 + #comment[1])
  local block_end = self:get_text(line2, col2 - #comment[2], line2, col2)

  if block_start == comment[1] and block_end == comment[2] then
    -- remove up to 1 whitespace after the comment
    local start_len, stop_len = #comment[1], #comment[2]
    if self:get_text(line1, col1 + #comment[1], line1, col1 + #comment[1] + 1):find("%s$") then
      start_len = start_len + 1
    end
    if self:get_text(line2, col2 - #comment[2] - 1, line2, col2):find("^%s") then
      stop_len = stop_len + 1
    end

    self:remove(line1, col1, line1, col1 + start_len)
    col2 = col2 - (line1 == line2 and start_len or 0)
    self:remove(line2, col2 - stop_len, line2, col2)

    return line1, col1, line2, col2 - stop_len
  else
    self:insert(line1, col1, comment[1] .. " ")
    col2 = col2 + (line1 == line2 and (#comment[1] + 1) or 0)
    self:insert(line2, col2, " " .. comment[2])

    return line1, col1, line2, col2 + #comment[2] + 1
  end
end

-- For plugins to get notified when a document is closed
function Doc:on_close()
  core.log_quiet("Closed doc \"%s\"", self:get_name())
end

return Doc
