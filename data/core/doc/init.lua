local Object = require "core.object"
local Highlighter = require "core.doc.highlighter"
local syntax = require "core.syntax"
local config = require "core.config"
local common = require "core.common"


local Doc = Object:extend()


local function split_lines(text)
  local res = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    table.insert(res, line)
  end
  return res
end

function Doc:new(filename)
  self:reset()
  if filename then
    self:load(filename)
  end
end


function Doc:reset()
  self.lines = { "\n" }
  self.selections = { 1, 1, 1, 1 }
  self.cursor_clipboard = {}
  self.undo_stack = { idx = 1 }
  self.redo_stack = { idx = 1 }
  self.clean_change_id = 1
  self.highlighter = Highlighter(self)
  self:reset_syntax()
end


function Doc:reset_syntax()
  local header = self:get_text(1, 1, self:position_offset(1, 1, 128))
  local syn = syntax.get(self.filename or "", header)
  if self.syntax ~= syn then
    self.syntax = syn
    self.highlighter:reset()
  end
end


function Doc:set_filename(filename)
  self.filename = filename
  self.abs_filename = system.absolute_path(filename)
end


function Doc:load(filename)
  local fp = assert( io.open(filename, "rb") )
  self:reset()
  self:set_filename(filename)
  self.lines = {}
  for line in fp:lines() do
    if line:byte(-1) == 13 then
      line = line:sub(1, -2)
      self.crlf = true
    end
    table.insert(self.lines, line .. "\n")
  end
  if #self.lines == 0 then
    table.insert(self.lines, "\n")
  end
  fp:close()
  self:reset_syntax()
end


function Doc:save(filename)
  filename = filename or assert(self.filename, "no filename set to default to")
  local fp = assert( io.open(filename, "wb") )
  for _, line in ipairs(self.lines) do
    if self.crlf then line = line:gsub("\n", "\r\n") end
    fp:write(line)
  end
  fp:close()
  if filename then
    self:set_filename(filename)
  end
  self:reset_syntax()
  self:clean()
end


function Doc:get_name()
  return self.filename or "unsaved"
end


function Doc:is_dirty()
  return self.clean_change_id ~= self:get_change_id()
end


function Doc:clean()
  self.clean_change_id = self:get_change_id()
end


function Doc:get_change_id()
  return self.undo_stack.idx
end

function Doc:set_selections(idx, line1, col1, line2, col2, swap)
  assert(not line2 == not col2, "expected 3 or 5 arguments")
  if swap then line1, col1, line2, col2 = line2, col2, line1, col1 end
  line1, col1 = self:sanitize_position(line1, col1)
  line2, col2 = self:sanitize_position(line2 or line1, col2 or col1)
  common.splice(self.selections, (idx - 1)*4 + 1, 4, { line1, col1, line2, col2 })
end

function Doc:set_selection(line1, col1, line2, col2, swap)
  self.selections = {}
  self:set_selections(1, line1, col1, line2, col2, swap)
  self.cursor_clipboard = {}
end

function Doc:merge_cursors(idx)
  for i = (idx or (#self.selections - 3)), (idx or 5), -4 do
    for j = 1, i - 4, 4 do
      if self.selections[i] == self.selections[j] and
        self.selections[i+1] == self.selections[j+1] then
          common.splice(self.selections, i, 4)
          break
      end
    end
  end
end

local function sort_positions(line1, col1, line2, col2)
  if line1 > line2 or line1 == line2 and col1 > col2 then
    return line2, col2, line1, col1
  end
  return line1, col1, line2, col2
end

function Doc:get_selection(sort)
  local idx, line1, col1, line2, col2 = self:get_selections(sort)(self.selections, 0)
  return line1, col1, line2, col2, sort
end

function Doc:get_selections(sort)
  return function(selections, idx)
    local target = idx*4 + 1
    if target >= #selections then return end
    if sort then
      return idx+1, sort_positions(unpack(selections, target, target+4))
    else
      return idx+1, unpack(selections, target, target+4)
    end
  end, self.selections, 0
end


function Doc:has_selection()
  local line1, col1, line2, col2 = self:get_selection(false)
  return line1 ~= line2 or col1 ~= col2
end


function Doc:sanitize_selection()
  for idx, line1, col1, line2, col2 in self:get_selections() do
    self:set_selections(idx, line1, col1, line2, col2)
  end
end


function Doc:sanitize_position(line, col)
  line = common.clamp(line, 1, #self.lines)
  col = common.clamp(col, 1, #self.lines[line])
  return line, col
end


local function position_offset_func(self, line, col, fn, ...)
  line, col = self:sanitize_position(line, col)
  return fn(self, line, col, ...)
end


local function position_offset_byte(self, line, col, offset)
  line, col = self:sanitize_position(line, col)
  col = col + offset
  while line > 1 and col < 1 do
    line = line - 1
    col = col + #self.lines[line]
  end
  while line < #self.lines and col > #self.lines[line] do
    col = col - #self.lines[line]
    line = line + 1
  end
  return self:sanitize_position(line, col)
end


local function position_offset_linecol(self, line, col, lineoffset, coloffset)
  return self:sanitize_position(line + lineoffset, col + coloffset)
end


function Doc:position_offset(line, col, ...)
  if type(...) ~= "number" then
    return position_offset_func(self, line, col, ...)
  elseif select("#", ...) == 1 then
    return position_offset_byte(self, line, col, ...)
  elseif select("#", ...) == 2 then
    return position_offset_linecol(self, line, col, ...)
  else
    error("bad number of arguments")
  end
end


function Doc:get_text(line1, col1, line2, col2)
  line1, col1 = self:sanitize_position(line1, col1)
  line2, col2 = self:sanitize_position(line2, col2)
  line1, col1, line2, col2 = sort_positions(line1, col1, line2, col2)
  if line1 == line2 then
    return self.lines[line1]:sub(col1, col2 - 1)
  end
  local lines = { self.lines[line1]:sub(col1) }
  for i = line1 + 1, line2 - 1 do
    table.insert(lines, self.lines[i])
  end
  table.insert(lines, self.lines[line2]:sub(1, col2 - 1))
  return table.concat(lines)
end


function Doc:get_char(line, col)
  line, col = self:sanitize_position(line, col)
  return self.lines[line]:sub(col, col)
end


local function push_undo(undo_stack, time, type, ...)
  undo_stack[undo_stack.idx] = { type = type, time = time, ... }
  undo_stack[undo_stack.idx - config.max_undos] = nil
  undo_stack.idx = undo_stack.idx + 1
end


local function pop_undo(self, undo_stack, redo_stack, modified)
  -- pop command
  local cmd = undo_stack[undo_stack.idx - 1]
  if not cmd then return end
  undo_stack.idx = undo_stack.idx - 1

  -- handle command
  if cmd.type == "insert" then
    local line, col, text = table.unpack(cmd)
    self:raw_insert(line, col, text, redo_stack, cmd.time)
  elseif cmd.type == "remove" then
    local line1, col1, line2, col2 = table.unpack(cmd)
    self:raw_remove(line1, col1, line2, col2, redo_stack, cmd.time)
  elseif cmd.type == "selection" then
    self.selections = { unpack(cmd) }
  end

  modified = modified or (cmd.type ~= "selection")

  -- if next undo command is within the merge timeout then treat as a single
  -- command and continue to execute it
  local next = undo_stack[undo_stack.idx - 1]
  if next and math.abs(cmd.time - next.time) < config.undo_merge_timeout then
    return pop_undo(self, undo_stack, redo_stack, modified)
  end

  if modified then
    self:on_text_change("undo")
  end
end


function Doc:raw_insert(line, col, text, undo_stack, time)
  -- split text into lines and merge with line at insertion point
  local lines = split_lines(text)
  local before = self.lines[line]:sub(1, col - 1)
  local after = self.lines[line]:sub(col)
  for i = 1, #lines - 1 do
    lines[i] = lines[i] .. "\n"
  end
  lines[1] = before .. lines[1]
  lines[#lines] = lines[#lines] .. after

  -- splice lines into line array
  common.splice(self.lines, line, 1, lines)

  -- push undo
  local line2, col2 = self:position_offset(line, col, #text)
  push_undo(undo_stack, time, "selection", unpack(self.selections))
  push_undo(undo_stack, time, "remove", line, col, line2, col2)

  -- update highlighter and assure selection is in bounds
  self.highlighter:invalidate(line)
  self:sanitize_selection()
end


function Doc:raw_remove(line1, col1, line2, col2, undo_stack, time)
  -- push undo
  local text = self:get_text(line1, col1, line2, col2)
  push_undo(undo_stack, time, "selection", unpack(self.selections))
  push_undo(undo_stack, time, "insert", line1, col1, text)

  -- get line content before/after removed text
  local before = self.lines[line1]:sub(1, col1 - 1)
  local after = self.lines[line2]:sub(col2)

  -- splice line into line array
  common.splice(self.lines, line1, line2 - line1 + 1, { before .. after })

  -- update highlighter and assure selection is in bounds
  self.highlighter:invalidate(line1)
  self:sanitize_selection()
end


function Doc:insert(line, col, text)
  self.redo_stack = { idx = 1 }
  line, col = self:sanitize_position(line, col)
  self:raw_insert(line, col, text, self.undo_stack, system.get_time())
  self:on_text_change("insert")
end


function Doc:remove(line1, col1, line2, col2)
  self.redo_stack = { idx = 1 }
  line1, col1 = self:sanitize_position(line1, col1)
  line2, col2 = self:sanitize_position(line2, col2)
  line1, col1, line2, col2 = sort_positions(line1, col1, line2, col2)
  self:raw_remove(line1, col1, line2, col2, self.undo_stack, system.get_time())
  self:on_text_change("remove")
end


function Doc:undo()
  pop_undo(self, self.undo_stack, self.redo_stack, false)
end


function Doc:redo()
  pop_undo(self, self.redo_stack, self.undo_stack, false)
end


function Doc:text_input(text, idx)
  for sidx, line1, col1, line2, col2 in self:get_selections(true) do
    if not idx or idx == sidx then
      if line1 ~= line2 or col1 ~= col2 then
        self:delete_to_cursor(sidx)
      end
      self:insert(line1, col1, text)
      self:move_to_cursor(sidx, #text)
    end
  end
end


function Doc:replace(fn)
  local line1, col1, line2, col2 = self:get_selection(true)
  if line1 == line2 and col1 == col2 then
    line1, col1, line2, col2 = 1, 1, #self.lines, #self.lines[#self.lines]
  end
  local old_text = self:get_text(line1, col1, line2, col2)
  local new_text, n = fn(old_text)
  if old_text ~= new_text then
    self:insert(line2, col2, new_text)
    self:remove(line1, col1, line2, col2)
    if line1 == line2 and col1 == col2 then
      line2, col2 = self:position_offset(line1, col1, #new_text)
      self:set_selection(line1, col1, line2, col2)
    end
  end
  return n
end


function Doc:delete_to_cursor(idx, ...)
  for sidx, line1, col1, line2, col2 in self:get_selections(true) do
    if not idx or sidx == idx then
      if line1 ~= line2 or col1 ~= col2 then
        self:remove(line1, col1, line2, col2)
      else
        local l2, c2 = self:position_offset(line1, col1, ...)
        self:remove(line1, col1, l2, c2)
        line1, col1 = sort_positions(line1, col1, l2, c2)
      end
      self:set_selections(sidx, line1, col1)
    end
  end
  self:merge_cursors(idx)
end
function Doc:delete_to(...) return self:delete_to(nil, ...) end

function Doc:move_to_cursor(idx, ...)
  for sidx, line, col in self:get_selections() do
    if not idx or sidx == idx then
      self:set_selections(sidx, self:position_offset(line, col, ...))
    end
  end
  self:merge_cursors(idx)
end
function Doc:move_to(...) return self:move_to_cursor(nil, ...) end


function Doc:select_to_cursor(idx, ...)
  for sidx, line, col, line2, col2 in self:get_selections() do
    if not idx or idx == sidx then
      line, col = self:position_offset(line, col, ...)
      self:set_selections(sidx, line, col, line2, col2)
    end
  end
  self:merge_cursors(idx)
end
function Doc:select_to(...) return self:select_to_cursor(nil, ...) end


local function get_indent_string()
  if config.tab_type == "hard" then
    return "\t"
  end
  return string.rep(" ", config.indent_size)
end

-- returns the size of the original indent, and the indent
-- in your config format, rounded either up or down
local function get_line_indent(line, rnd_up)
  local _, e = line:find("^[ \t]+")
  local soft_tab = string.rep(" ", config.indent_size)
  if config.tab_type == "hard" then
    local indent = e and line:sub(1, e):gsub(soft_tab, "\t") or ""
    return e, indent:gsub(" +", rnd_up and "\t" or "")
  else
    local indent = e and line:sub(1, e):gsub("\t", soft_tab) or ""
    local number = #indent / #soft_tab
    return e, indent:sub(1,
      (rnd_up and math.ceil(number) or math.floor(number))*#soft_tab)
  end
end

-- un/indents text; behaviour varies based on selection and un/indent.
-- * if there's a selection, it will stay static around the
--   text for both indenting and unindenting.
-- * if you are in the beginning whitespace of a line, and are indenting, the
--   cursor will insert the exactly appropriate amount of spaces, and jump the
--   cursor to the beginning of first non whitespace characters
-- * if you are not in the beginning whitespace of a line, and you indent, it
--   inserts the appropriate whitespace, as if you typed them normally.
-- * if you are unindenting, the cursor will jump to the start of the line,
--   and remove the appropriate amount of spaces (or a tab).
function Doc:indent_text(unindent, line1, col1, line2, col2)
  local text = get_indent_string()
  local _, se = self.lines[line1]:find("^[ \t]+")
  local in_beginning_whitespace = col1 == 1 or (se and col1 <= se + 1)
  local has_selection = line1 ~= line2 or col1 ~= col2
  if unindent or has_selection or in_beginning_whitespace then
    local l1d, l2d = #self.lines[line1], #self.lines[line2]
    for line = line1, line2 do
      local e, rnded = get_line_indent(self.lines[line], unindent)
      self:remove(line, 1, line, (e or 0) + 1)
      self:insert(line, 1,
        unindent and rnded:sub(1, #rnded - #text) or rnded .. text)
    end
    l1d, l2d = #self.lines[line1] - l1d, #self.lines[line2] - l2d
    if (unindent or in_beginning_whitespace) and not has_selection then
      local start_cursor = (se and se + 1 or 1) + l1d or #(self.lines[line1])
      return line1, start_cursor, line2, start_cursor
    end
    return line1, col1 + l1d, line2, col2 + l2d
  end
  self:insert(line1, col1, text)
  return line1, col1 + #text, line1, col1 + #text
end

-- For plugins to add custom actions of document change
function Doc:on_text_change(type)
end


return Doc
