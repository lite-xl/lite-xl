local core = require "core"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local keymap = require "core.keymap"
local translate = require "core.doc.translate"
local Doc = require "core.doc"
local ime = require "core.ime"
local View = require "core.view"

---@class core.docview : core.view
---@field super core.view
local DocView = View:extend()

function DocView:__tostring() return "DocView" end

DocView.context = "session"

local function move_to_line_offset(dv, line, col, offset)
  local vline, vcol = dv:get_vline(line, col)
  local xo = dv.last_x_offset
  if xo.line ~= vline or xo.col ~= vcol then
    xo.x, xo.y = dv:get_line_screen_position(line, col)
  end
  xo.line, xo.col = dv:get_dline(math.max(vline + offset, 1), vcol)
  return xo.line, xo.col
end

local function get_vline_text(self, vline)
  local t = {}
  for _, text in self.dv:each_vline_token(vline) do
    table.insert(t, text)
  end
  return table.concat(t)
end

DocView.translate = {}
function DocView.translate.previous_page(self, line, col)
  local min, max = self:get_visible_virtual_line_range()
  return move_to_line_offset(self, line, col, (min - max))
end

function DocView.translate.next_page(self, line, col)
  local min, max = self:get_visible_virtual_line_range()
  return move_to_line_offset(self, line, col, (max - min))
end

function DocView.translate.previous_line(self, line, col)
  return move_to_line_offset(self, line, col, -1)
end

function DocView.translate.next_line(self, line, col)
  return move_to_line_offset(self, line, col, 1)
end
  
function DocView.translate.start_of_line(self, line, col)
  local vline = self:get_vline(line, 1)
  return self:get_dline(vline, 1)
end

function DocView.translate.start_of_indentation(self, line, col)
  local vline = self:get_vline(line, col)
  local s, e = self.vlines[vline]:find("^%s*")
  return self:get_dline(vline, col > e + 1 and e + 1 or 1, "prev")
end

function DocView.translate.end_of_line(self, line, col)
  local vline = self:get_vline(line, col)
  return self:get_dline(vline, self:get_vline_length(vline) + 1, "next")
end


function DocView.translate.next_char(self, line, col)
  local vline, vcol = self:get_vline(line, col)
  vcol = vcol + 1
  if vcol > self:get_vline_length(vline) then
    vline = vline + 1
    vcol = 1
  end
  return self:get_dline(vline, vcol, "next")
end

function DocView.translate.previous_char(self, line, col)
  local vline, vcol = self:get_vline(line, col)
  vcol = vcol - 1
  if vcol <= 0 then
    vline = vline - 1
    vcol = self:get_vline_length(vline) - 1
  end
  return self:get_dline(vline, vcol, "prev")
end

function DocView:new(doc)
  DocView.super.new(self)
  self.cursor = "ibeam"
  self.scrollable = true
  self.doc = assert(doc)
  self.font = "code_font"
  self.last_x_offset = {}
  self.ime_selection = { from = 0, size = 0 }
  self.ime_status = false
  self.hovering_gutter = false
  self.read_only = false
  self.vlines = setmetatable({ dv = self }, { __index = get_vline_text })
  self.lines = doc.lines
  self:invalidate_cache()
  self.selections = { 1, 1, 1, 1 }
  self.last_selection = 1
  self.v_scrollbar:set_forced_status(config.force_scrollbar_status)
  self.h_scrollbar:set_forced_status(config.force_scrollbar_status)
  table.insert(doc.listeners, self)
end

function DocView:get_char(line, col)
  line, col = self.doc:sanitize_position(line, col)
  return self.doc.lines[line]:usub(col, col)
end

function DocView:sanitize_position(line, col)
  return self.doc:sanitize_position(line, col)
end

function DocView:get_virtual_line_offset(vline, vcol)
  local lh = self:get_line_height()
  local x, y = self:get_content_offset()
  local gw = self:get_gutter_width()
  local vx, vy = self:get_vline_position(vline, vcol or 1)
  return x + gw + vx, y + vy
end

function DocView:get_vline_position(vline, vcol) 
  local y = (vline-1) * self:get_line_height()
  local default_font = self:get_font()
  local _, indent_size = self.doc:get_indent_info()
  default_font:set_tab_size(indent_size)
  local column = 1
  local xoffset = 0
  for _, text, style, type in self:each_vline_token(vline) do
    local font = style.font or default_font
    if font ~= default_font then font:set_tab_size(indent_size) end
    local length = text:ulen() or #text
    if type == "doc" then
      if column + length < vcol then
        xoffset = xoffset + font:get_width(text)
        column = column + length
      else
        for char in common.utf8_chars(text) do
          if column >= vcol then
            return xoffset, y
          end
          xoffset = xoffset + font:get_width(char)
          column = column + 1
        end
      end
    else
      xoffset = xoffset + font:get_width(text)
      column = column + length
    end
  end
  return xoffset, y
end

function DocView:get_line_position(line, col)
  local vline, vcol = self:get_vline(line, col)
  return self:get_vline_position(vline, vcol)
end

function DocView:get_line_screen_position(line, col)
  local ox, oy = self:get_content_offset()
  local gw = self:get_gutter_width()
  local x, y = self:get_line_position(line, col)
  return x + ox + gw, oy + y
end

function DocView:get_vline_screen_position(vline, vcol)
  local ox, oy = self:get_content_offset()
  local gw = self:get_gutter_width()
  local x, y = self:get_vline_position(vline, vcol)
  return x + ox + gw, oy + y
end

-- compatibility function
DocView.get_col_x_offset = DocView.get_line_position


function DocView:resolve_screen_position(x, y)
  local ox, oy = self:get_virtual_line_offset(1)
  local vline = math.floor((y - oy) / self:get_line_height()) + 1

  local xoffset, last_i, i = ox, 1, 1
  local default_font = self:get_font()
  local _, indent_size = self.doc:get_indent_info()
  default_font:set_tab_size(indent_size)
  local line = self:retrieve_tokens(vline)
  if not line then return #self.doc.lines, self.doc.lines[#self.doc.lines]:ulen() end
  for _, text, style, type, dline, offset in self:each_vline_token(vline) do
    local len = text:ulen() or #text
    local font = style.font or default_font
    if font ~= default_font then font:set_tab_size(indent_size) end
    local width = font:get_width(text)
    -- Don't take the shortcut if the width matches x,
    -- because we need last_i which should be calculated using utf-8.
    if xoffset + width < x then
      xoffset = xoffset + width
      i = i + len
    else
      for char in common.utf8_chars(text) do
        local w = font:get_width(char)
        if xoffset >= x then
          return self:get_dline(vline, (xoffset - x > w / 2) and last_i or i)
        end
        xoffset = xoffset + w
        last_i = i
        i = i + 1
      end
    end
  end
  return self:get_dline(vline, i)
end


-- Cursor section. Cursor indices are *only* valid during a get_selections() call.
-- Cursors will always be iterated in order from top to bottom. Through normal operation
-- curors can never swap positions; only merge or split, or change their position in cursor
-- order.
function DocView:get_selection(sort)
  local line1, col1, line2, col2, swap = self:get_selection_idx(self.last_selection, sort)
  if not line1 then
    line1, col1, line2, col2, swap = self:get_selection_idx(1, sort)
  end
  return line1, col1, line2, col2, swap
end

---Get the selection specified by `idx`
---@param idx integer @the index of the selection to retrieve
---@param sort? boolean @whether to sort the selection returned
---@return integer,integer,integer,integer,boolean? @line1, col1, line2, col2, was the selection sorted
function DocView:get_selection_idx(idx, sort)
  local line1, col1, line2, col2 = self.selections[idx * 4 - 3], self.selections[idx * 4 - 2],
      self.selections[idx * 4 - 1],
      self.selections[idx * 4]
  if line1 and sort then
    return common.sort_positions(line1, col1, line2, col2)
  else
    return line1, col1, line2, col2
  end
end

function DocView:get_selection_text(limit)
  limit = limit or math.huge
  local result = {}
  for idx, line1, col1, line2, col2 in self:get_selections() do
    if idx > limit then break end
    if line1 ~= line2 or col1 ~= col2 then
      local text = self:get_text(line1, col1, line2, col2)
      if text ~= "" then result[#result + 1] = text end
    end
  end
  return table.concat(result, "\n")
end

function DocView:has_selection()
  local line1, col1, line2, col2 = self:get_selection(false)
  return line1 ~= line2 or col1 ~= col2
end

function DocView:has_any_selection()
  for idx, line1, col1, line2, col2 in self:get_selections() do
    if line1 ~= line2 or col1 ~= col2 then return true end
  end
  return false
end


function DocView:set_selections(idx, line1, col1, line2, col2, swap, rm)
  assert(not line2 == not col2, "expected 3 or 5 arguments")
  if swap then line1, col1, line2, col2 = line2, col2, line1, col1 end
  line1, col1 = self.doc:sanitize_position(line1, col1)
  line2, col2 = self.doc:sanitize_position(line2 or line1, col2 or col1)
  common.splice(self.selections, (idx - 1) * 4 + 1, rm == nil and 4 or rm, { line1, col1, line2, col2 })
  self.vselections = nil
end

function DocView:add_selection(line1, col1, line2, col2, swap)
  local l1, c1 = common.sort_positions(line1, col1, line2 or line1, col2 or col1)
  local target = #self.selections / 4 + 1
  for idx, tl1, tc1 in self:get_selections(true) do
    if l1 < tl1 or l1 == tl1 and c1 < tc1 then
      target = idx
      break
    end
  end
  self:set_selections(target, line1, col1, line2, col2, swap, 0)
  self.last_selection = target
end

function DocView:remove_selection(idx)
  if self.last_selection >= idx then
    self.last_selection = self.last_selection - 1
  end
  common.splice(self.selections, (idx - 1) * 4 + 1, 4)
end

function DocView:set_selection(line1, col1, line2, col2, swap)
  self.selections = {}
  self:set_selections(1, line1, col1, line2, col2, swap)
  self.last_selection = 1
end

function DocView:merge_cursors(idx)
  for i = (idx or (#self.selections - 3)), (idx or 5), -4 do
    for j = 1, i - 4, 4 do
      if self.selections[i] == self.selections[j] and
          self.selections[i + 1] == self.selections[j + 1] then
        common.splice(self.selections, i, 4)
        if self.last_selection >= (i + 3) / 4 then
          self.last_selection = self.last_selection - 1
        end
        break
      end
    end
  end
end

local function selection_iterator(invariant, idx)
  local target = invariant[3] and (idx * 4 - 7) or (idx * 4 + 1)
  if target > #invariant[1] or target <= 0 or (type(invariant[3]) == "number" and invariant[3] ~= idx - 1) then return end
  if invariant[2] then
    return idx + (invariant[3] and -1 or 1), common.sort_positions(table.unpack(invariant[1], target, target + 4))
  else
    return idx + (invariant[3] and -1 or 1), table.unpack(invariant[1], target, target + 4)
  end
end

-- If idx_reverse is true, it'll reverse iterate. If nil, or false, regular iterate.
-- If a number, runs for exactly that iteration.
function DocView:get_selections(sort_intra, idx_reverse)
  return selection_iterator, { self.selections, sort_intra, idx_reverse, self },
      idx_reverse == true and ((#self.selections / 4) + 1) or ((idx_reverse or -1) + 1)
end

-- End of cursor seciton.

function DocView:sanitize_selection()
  for idx, line1, col1, line2, col2 in self:get_selections() do
    self:set_selections(idx, line1, col1, line2, col2)
  end
end

function DocView:text_input(text, idx)
  for sidx, line1, col1, line2, col2 in self:get_selections(true, idx or true) do
    local had_selection = false
    if line1 ~= line2 or col1 ~= col2 then
      self:delete_to_cursor(sidx)
      had_selection = true
    end

    if self.overwrite
    and not had_selection
    and col1 < #self.lines[line1]
    and text:ulen() == 1 then
      local line2, col2 = translate.next_char(self, line1, col1)
      self.doc:remove(line1, col1, line2, col2, self.selections)
    end

    self.doc:insert(line1, col1, text, self.selections)
    self:move_to_cursor(sidx, #text)
  end
end

function DocView:on_doc_change(type, text, line1, col1, line2, col2)
  if type == "reset" then self:invalidate_cache() end
  local invalid_line1, invalid_line2 = line1, line2
  local lines = 1
  if type == "insert" and text:find("\n") then 
    invalid_line2 = nil 
    local _, newlines = text:gsub("\n", "")
    lines = newlines + 1
  end
  -- keep cursors where they should be on insertion
  if type == "remove" then invalid_line2 = nil end
  if type == "insert" then
    self:invalidate_cache(invalid_line1, invalid_line2)
    for idx, cline1, ccol1, cline2, ccol2 in self:get_selections(true, true) do
      if cline1 < line1 then break end
      local line_addition = (line1 < cline1 or col1 < ccol1) and lines - 1 or 0
      local column_addition = line1 == cline1 and ccol1 > col1 and #text or 0
      self:set_selections(idx, cline1 + line_addition, ccol1 + column_addition, cline2 + line_addition, ccol2 + column_addition)
    end
  end
  -- keep selections in correct positions on removal: each pair (line, col)
  -- * remains unchanged if before the deleted text
  -- * is set to (line1, col1) if in the deleted text
  -- * is set to (line1, col - col_removal) if on line2 but out of the deleted text
  -- * is set to (line - line_removal, col) if after line2
  if type == "remove" then
    local line_removal = line2 - line1
    local col_removal = col2 - col1
    self:invalidate_cache(invalid_line1, invalid_line2)
    local merge = false
    for idx, cline1, ccol1, cline2, ccol2 in self:get_selections(true, true) do
      if cline2 < line1 then break end
      local l1, c1, l2, c2 = cline1, ccol1, cline2, ccol2

      if cline1 > line1 or (cline1 == line1 and ccol1 > col1) then
        if cline1 > line2 then
          l1 = l1 - line_removal
        else
          l1 = line1
          c1 = (cline1 == line2 and ccol1 > col2) and c1 - col_removal or col1
        end
      end

      if cline2 > line1 or (cline2 == line1 and ccol2 > col1) then
        if cline2 > line2 then
          l2 = l2 - line_removal
        else
          l2 = line1
          c2 = (cline2 == line2 and ccol2 > col2) and c2 - col_removal or col1
        end
      end

      if l1 == line1 and c1 == col1 then merge = true end
      self:set_selections(idx, l1, c1, l2, c2)
    end
    if merge then
      self:merge_cursors()
    end
  end
end

function DocView:try_close(do_close)
  if self.doc:is_dirty()
  and #core.get_views_referencing_doc(self.doc) == 1 then
    core.command_view:enter("Unsaved Changes; Confirm Close", {
      submit = function(_, item)
        if item.text:match("^[cC]") then
          do_close()
        elseif item.text:match("^[sS]") then
          self.doc:save()
          do_close()
        end
      end,
      suggest = function(text)
        local items = {}
        if not text:find("^[^cC]") then table.insert(items, "Close Without Saving") end
        if not text:find("^[^sS]") then table.insert(items, "Save And Close") end
        return items
      end
    })
  else
    do_close()
  end
end



function DocView:ime_text_editing(text, start, length, idx)
  for sidx, line1, col1, line2, col2 in self:get_selections(true, idx or true) do
    if line1 ~= line2 or col1 ~= col2 then
      self:delete_to_cursor(sidx)
    end
    self.doc:insert(line1, col1, text, self.selections)
    self:set_selections(sidx, line1, col1 + #text, line1, col1)
  end
end

function DocView:replace_cursor(idx, line1, col1, line2, col2, fn)
  local old_text = self.doc:get_text(line1, col1, line2, col2)
  local new_text, res = fn(old_text)
  if old_text ~= new_text then
    self.doc:insert(line2, col2, new_text, self.selections)
    self.doc:remove(line1, col1, line2, col2, self.selections)
    if line1 == line2 and col1 == col2 then
      line2, col2 = self:position_offset(line1, col1, #new_text)
      self:set_selections(idx, line1, col1, line2, col2)
    end
  end
  return res
end

function DocView:replace(fn)
  local has_selection, results = false, {}
  for idx, line1, col1, line2, col2 in self:get_selections(true) do
    if line1 ~= line2 or col1 ~= col2 then
      results[idx] = self:replace_cursor(idx, line1, col1, line2, col2, fn)
      has_selection = true
    end
  end
  if not has_selection then
    self:set_selection(table.unpack(self.selections))
    results[1] = self:replace_cursor(1, 1, 1, #self.lines, #self.lines[#self.lines], fn)
  end
  return results
end

function DocView:delete_to_cursor(idx, ...)
  for sidx, line1, col1, line2, col2 in self:get_selections(true, idx) do
    if line1 ~= line2 or col1 ~= col2 then
      self.doc:remove(line1, col1, line2, col2, self.selections)
    else
      local l2, c2 = self:position_offset(line1, col1, ...)
      self.doc:remove(line1, col1, l2, c2, self.selections)
      line1, col1 = common.sort_positions(line1, col1, l2, c2)
    end
    self:set_selections(sidx, line1, col1)
  end
  self:merge_cursors(idx)
end

function DocView:delete_to(...) return self:delete_to_cursor(nil, ...) end

function DocView:move_to_cursor(idx, ...)
  for sidx, line, col in self:get_selections(false, idx) do
    self:set_selections(sidx, self:position_offset(line, col, ...))
  end
  self:merge_cursors(idx)
end

function DocView:move_to(...) return self:move_to_cursor(nil, ...) end

function DocView:select_to_cursor(idx, ...)
  for sidx, line, col, line2, col2 in self:get_selections(false, idx) do
    line, col = self:position_offset(line, col, ...)
    self:set_selections(sidx, line, col, line2, col2)
  end
  self:merge_cursors(idx)
end

function DocView:select_to(...) return self:select_to_cursor(nil, ...) end

-- returns the size of the original indent, and the indent
-- in your config format, rounded either up or down
function DocView:get_line_indent(line, rnd_up)
  local _, e = line:find("^[ \t]+")
  local indent_type, indent_size = self.doc:get_indent_info()
  local soft_tab = string.rep(" ", indent_size)
  if indent_type == "hard" then
    local indent = e and line:sub(1, e):gsub(soft_tab, "\t") or ""
    return e, indent:gsub(" +", rnd_up and "\t" or "")
  else
    local indent = e and line:sub(1, e):gsub("\t", soft_tab) or ""
    local number = #indent / #soft_tab
    return e, indent:sub(1,
      (rnd_up and math.ceil(number) or math.floor(number)) * #soft_tab)
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
function DocView:indent_text(unindent, line1, col1, line2, col2)
  local text = self.doc:get_indent_string()
  local _, se = self.doc.lines[line1]:find("^[ \t]+")
  local in_beginning_whitespace = col1 == 1 or (se and col1 <= se + 1)
  local has_selection = line1 ~= line2 or col1 ~= col2
  if unindent or has_selection or in_beginning_whitespace then
    local l1d, l2d = #self.doc.lines[line1], #self.doc.lines[line2]
    for line = line1, line2 do
      if not has_selection or #self.doc.lines[line] > 1 then -- don't indent empty lines in a selection
        local e, rnded = self:get_line_indent(self.doc.lines[line], unindent)
        self.doc:remove(line, 1, line, (e or 0) + 1, self.selections)
        self.doc:insert(line, 1,
          unindent and rnded:sub(1, #rnded - #text) or rnded .. text, self.selections)
      end
    end
    l1d, l2d = #self.doc.lines[line1] - l1d, #self.doc.lines[line2] - l2d
    if (unindent or in_beginning_whitespace) and not has_selection then
      local start_cursor = (se and se + 1 or 1) + l1d or #(self.lines[line1])
      return line1, start_cursor, line2, start_cursor
    end
    return line1, col1 + l1d, line2, col2 + l2d
  end
  self.doc:insert(line1, col1, text, self.selections)
  return line1, col1 + #text, line1, col1 + #text
end


function DocView:get_name()
  local post = self.doc:is_dirty() and "*" or ""
  local name = self.doc:get_name()
  return name:match("[^/%\\]*$") .. post
end


function DocView:get_filename()
  if self.doc.abs_filename then
    local post = self.doc:is_dirty() and "*" or ""
    return common.home_encode(self.doc.abs_filename) .. post
  end
  return self:get_name()
end


function DocView:get_scrollable_size()
  local max_lines = math.max(#self.doc.lines, self:get_total_vlines())
  if not config.scroll_past_end then
    local _, _, _, h_scroll = self.h_scrollbar:get_track_rect()
    return self:get_line_height() * (#self.doc.lines) + style.padding.y * 2 + h_scroll
  end
  return self:get_line_height() * (#self.doc.lines - 1) + self.size.y
end

function DocView:get_h_scrollable_size()
  return math.huge
end


function DocView:get_font()
  return style[self.font]
end


function DocView:get_line_height()
  return math.floor(self:get_font():get_height() * config.line_height)
end


function DocView:get_gutter_width()
  local padding = style.padding.x * 2
  return self:get_font():get_width(#self.doc.lines) + padding, padding
end

function DocView:get_line_text_y_offset()
  local lh = self:get_line_height()
  local th = self:get_font():get_height()
  return (lh - th) / 2
end


function DocView:get_visible_virtual_line_range()
  local x1, y1, x2, y2 = self:get_content_bounds()
  local lh = self:get_line_height()
  local minline = math.max(1, math.floor((y1 - style.padding.y) / lh) + 1)
  local maxline = math.max(math.floor((y2 - style.padding.y) / lh), 0) + 1
  return minline, maxline
end

function DocView:get_visible_line_range()
  local minline, maxline = self:get_visible_virtual_line_range()
  local line1 = self:get_dline(minline)
  local line2 = self:get_dline(maxline)
  return line1, line2
end


function DocView:scroll_to_line(line, ignore_if_visible, instant, col)
  local min, max = self:get_visible_virtual_line_range()
  if not (ignore_if_visible and line > min and line < max) then
    self:retrieve_tokens(nil, line)
    local x, y = self:get_line_screen_position(line, col)
    local ox, oy = self:get_content_offset()
    local _, _, _, scroll_h = self.h_scrollbar:get_track_rect()
    self.scroll.to.y = math.max(0, y - oy - (self.size.y - scroll_h) / 2)
    if instant then
      self.scroll.y = self.scroll.to.y
    end
  end
end


function DocView:supports_text_input()
  return not self.read_only
end


function DocView:scroll_to_make_visible(line, col)
  local ox, oy = self:get_content_offset()
  self:retrieve_tokens(nil, line)
  local lx, ly = self:get_line_screen_position(line, col)
  local lh = self:get_line_height()
  local _, _, _, scroll_h = self.h_scrollbar:get_track_rect()
  self.scroll.to.y = common.clamp(self.scroll.to.y, ly - oy - self.size.y + scroll_h + lh * 2, ly - oy - lh)
  local xmargin = 3 * self:get_font():get_width(' ')
  local xsup = lx + self:get_gutter_width() + xmargin - ox
  local xinf = lx - self:get_gutter_width() - xmargin - ox
  local _, _, scroll_w = self.v_scrollbar:get_track_rect()
  local size_x = math.max(0, self.size.x - scroll_w)
  if xsup > self.scroll.x + size_x then
    self.scroll.to.x = xsup - size_x
  elseif xinf < self.scroll.x then
    self.scroll.to.x = math.max(0, xinf)
  end
end

function DocView:on_mouse_moved(x, y, ...)
  DocView.super.on_mouse_moved(self, x, y, ...)

  self.hovering_gutter = false
  local gw = self:get_gutter_width()

  if self:scrollbar_hovering() or self:scrollbar_dragging() then
    self.cursor = "arrow"
  elseif gw > 0 and x >= self.position.x and x <= (self.position.x + gw) then
    self.cursor = "arrow"
    self.hovering_gutter = true
  else
    self.cursor = "ibeam"
  end

  if self.mouse_selecting then
    local l1, c1 = self:resolve_screen_position(x, y)
    local l2, c2, snap_type = table.unpack(self.mouse_selecting)
    if keymap.modkeys["ctrl"] then
      if l1 > l2 then l1, l2 = l2, l1 end
      self.doc.selections = { }
      for i = l1, l2 do
        self:set_selections(i - l1 + 1, i, math.min(c1, #self.doc.lines[i]), i, math.min(c2, #self.doc.lines[i]))
      end
    else
      if snap_type then
        l1, c1, l2, c2 = self:mouse_selection(self.doc, snap_type, l1, c1, l2, c2)
      end
      self:set_selection(l1, c1, l2, c2)
    end
  end
end


function DocView:mouse_selection(doc, snap_type, line1, col1, line2, col2)
  local swap = line2 < line1 or line2 == line1 and col2 <= col1
  if swap then
    line1, col1, line2, col2 = line2, col2, line1, col1
  end
  if snap_type == "word" then
    line1, col1 = translate.start_of_word(self, line1, col1)
    line2, col2 = translate.end_of_word(self, line2, col2)
  elseif snap_type == "lines" then
    col1, col2, line2 = 1, 1, line2 + 1
  end
  if swap then
    return line2, col2, line1, col1
  end
  return line1, col1, line2, col2
end


function DocView:on_mouse_pressed(button, x, y, clicks)
  if button ~= "left" or not self.hovering_gutter then
    return DocView.super.on_mouse_pressed(self, button, x, y, clicks)
  end
  local line = self:resolve_screen_position(x, y)
  if keymap.modkeys["shift"] then
    local sline, scol, sline2, scol2 = self:get_selection(true)
    if line > sline then
      self:set_selection(sline, 1, line,  #self.doc.lines[line])
    else
      self:set_selection(line, 1, sline2, #self.doc.lines[sline2])
    end
  else
    if clicks == 1 then
      self:set_selection(line, 1, line, 1)
    elseif clicks == 2 then
      self:set_selection(line, 1, line, #self.doc.lines[line])
    end
  end
  return true
end


function DocView:on_mouse_released(...)
  DocView.super.on_mouse_released(self, ...)
  self.mouse_selecting = nil
end


function DocView:on_text_input(text)
  self:text_input(text)
end

function DocView:on_ime_text_editing(text, start, length)
  self:ime_text_editing(text, start, length)
  self.ime_status = #text > 0
  self.ime_selection.from = start
  self.ime_selection.size = length

  -- Set the composition bounding box that the system IME
  -- will consider when drawing its interface
  local line1, col1, line2, col2 = self:get_selection(true)
  local col = math.min(col1, col2)
  self:update_ime_location()
  self:scroll_to_make_visible(line1, col + start)
end

---Update the composition bounding box that the system IME
---will consider when drawing its interface
function DocView:update_ime_location()
  if not self.ime_status then return end

  local line1, col1, line2, col2 = self:get_selection(true)
  local x, y = self:get_line_screen_position(line1)
  local h = self:get_line_height()
  local col = math.min(col1, col2)

  local x1, x2 = 0, 0

  if self.ime_selection.size > 0 then
    -- focus on a part of the text
    local from = col + self.ime_selection.from
    local to = from + self.ime_selection.size
    x1 = self:get_col_x_offset(line1, from)
    x2 = self:get_col_x_offset(line1, to)
  else
    -- focus the whole text
    x1 = self:get_col_x_offset(line1, col1)
    x2 = self:get_col_x_offset(line2, col2)
  end

  ime.set_location(x + x1, y, x2 - x1, h)
end

function DocView:update()
  -- scroll to make caret visible and reset blink timer if it moved
  local line1, col1, line2, col2 = self:get_selection()
  if (line1 ~= self.last_line1 or col1 ~= self.last_col1 or
      line2 ~= self.last_line2 or col2 ~= self.last_col2) and self.size.x > 0 then
    if core.active_view == self and not ime.editing then
      self:scroll_to_make_visible(line1, col1)
    end
    core.blink_reset()
    self.last_line1, self.last_col1 = line1, col1
    self.last_line2, self.last_col2 = line2, col2
  end

  -- update blink timer
  if self == core.active_view and not self.mouse_selecting then
    local T, t0 = config.blink_period, core.blink_start
    local ta, tb = core.blink_timer, system.get_time()
    if ((tb - t0) % T < T / 2) ~= ((ta - t0) % T < T / 2) then
      core.redraw = true
    end
    core.blink_timer = tb
  end

  self:update_ime_location()

  DocView.super.update(self)
end


function DocView:draw_line_highlight(x, y)
  local lh = self:get_line_height()
  renderer.draw_rect(x, y, self.size.x, lh, style.line_highlight)
end


local default_color = { common.color "#FFFFFF" }
function DocView:draw_line_text(vline, x, y)
  local default_font = self:get_font()
  local tx, ty = x, y + self:get_line_text_y_offset()

  for _, text, style in self:each_vline_token(vline) do
    tx = renderer.draw_text(style.font or default_font, text:gsub("\n$", ""), tx, ty, style.color or default_color)
  end
  return self:get_line_height()
end


function DocView:draw_overwrite_caret(x, y, width)
  local lh = self:get_line_height()
  renderer.draw_rect(x, y + lh - style.caret_width, width, style.caret_width, style.caret)
end


function DocView:draw_caret(x, y)
  local lh = self:get_line_height()
  renderer.draw_rect(x, y, style.caret_width, lh, style.caret)
end

function DocView:draw_line(vline, x, y)
  local gw, gpad = self:get_gutter_width()
  core.push_clip_rect(self.position.x + gw, self.position.y, self.size.x - gw, self.size.y)
  self:draw_line_body(vline, x + gw - self.scroll.x, y)
  core.pop_clip_rect()
  self:draw_line_gutter(vline, x, y, gpad and gw - gpad or gw)
  return self:get_line_height()
end

function DocView:draw_line_body(vline, x, y)
  -- draw highlight if any selection ends on this line
  local draw_highlight = false
  local hcl = config.highlight_current_line
  if hcl ~= false then
    for lidx, line1, col1, line2, col2 in self:get_vselections(false) do
      if line1 == vline then
        if hcl == "no_selection" then
          if (line1 ~= line2) or (col1 ~= col2) then
            draw_highlight = false
            break
          end
        end
        draw_highlight = true
        break
      end
    end
  end
  if draw_highlight and core.active_view == self then
    self:draw_line_highlight(x + self.scroll.x, y)
  end
  
  -- draw selection if it overlaps this line
  local lh = self:get_line_height()
  for lidx, vline1, vcol1, vline2, vcol2 in self:get_vselections(true) do
    if vline >= vline1 and vline <= vline2 then
      if vline1 ~= vline then vcol1 = 1 end
      if vline2 ~= vline then vcol2 = self:get_vline_length(vline) end
      if vcol1 ~= vcol2 then
        local rx1, ry = self:get_vline_screen_position(vline, vcol1)
        local rx2 = self:get_vline_screen_position(vline, vcol2)
        renderer.draw_rect(rx1, ry, rx2 - rx1, lh, style.selection)
      end
    end
  end
  -- draw line's text
  self:draw_line_text(vline, x, y)
end


function DocView:draw_line_gutter(vline, x, y, width)
  local color = style.line_number
  for _, line1, _, line2 in self:get_vselections(true) do
    if vline >= line1 and vline <= line2 then
      color = style.line_number2
      break
    end
  end
  local dline, dcol = self:get_dline(vline, 1)
  local lh = self:get_line_height()
  if dcol == 1 then
    x = x + style.padding.x
    common.draw_text(self:get_font(), color, dline, "right", x, y, width, lh)
  end
  return lh
end


function DocView:draw_ime_decoration(line1, col1, line2, col2)
  local x, y = self:get_line_screen_position(line1)
  local line_size = math.max(1, SCALE)
  local lh = self:get_line_height()

  -- Draw IME underline
  local x1 = self:get_col_x_offset(line1, col1)
  local x2 = self:get_col_x_offset(line2, col2)
  renderer.draw_rect(x + math.min(x1, x2), y + lh - line_size, math.abs(x1 - x2), line_size, style.text)

  -- Draw IME selection
  local col = math.min(col1, col2)
  local from = col + self.ime_selection.from
  local to = from + self.ime_selection.size
  x1 = self:get_col_x_offset(line1, from)
  if from ~= to then
    x2 = self:get_col_x_offset(line1, to)
    line_size = style.caret_width
    renderer.draw_rect(x + math.min(x1, x2), y + lh - line_size, math.abs(x1 - x2), line_size, style.caret)
  end
  self:draw_caret(x + x1, y)
end

function DocView:draw_overlay()
  if core.active_view == self then
    -- draw caret if it overlaps this line
    local T = config.blink_period
    for _, line1, col1, line2, col2 in self:get_selections() do
      if system.window_has_focus(core.window) then
        if ime.editing then
          self:draw_ime_decoration(line1, col1, line2, col2)
        else
          if config.disable_blink
          or (core.blink_timer - core.blink_start) % T < T / 2 then
            local x, y = self:get_line_screen_position(line1, col1)
            if self.overwrite then
              self:draw_overwrite_caret(x, y, self:get_font():get_width(self.doc:get_char(line1, col1)))
            else
              self:draw_caret(x, y)
            end
          end
        end
      end
    end
  end
end

function DocView:draw()
  self:draw_background(style.background)
  local _, indent_size = self.doc:get_indent_info()
  self:get_font():set_tab_size(indent_size)

  local minline, maxline = self:ensure_cache(self:get_visible_virtual_line_range())
  
  local lh = self:get_line_height()
  local _, y = self:get_virtual_line_offset(minline)


  for i = minline, math.min(maxline, self:get_total_vlines()) do
    y = y + (self:draw_line(i, self.position.x, y) or lh)
  end
  self:draw_overlay()
  self:draw_scrollbar()
end

-- Plugins hook this to return a line/col list from `doc`, or provide a virtual line.
-- `{ "doc", line, 1, #self.doc.lines[line], style }`
-- `{ "virtual", line, text, false, style }
function DocView:tokenize(line)
  if line <= 0 or line > #self.doc.lines then return {} end
  return { "doc", line, 1, #self.doc.lines[line], { } }
end


local function pop_undo(self, undo_stack, redo_stack, modified)
  -- pop command
  local cmd = undo_stack[undo_stack.idx - 1]
  if not cmd then return end
  undo_stack.idx = undo_stack.idx - 1

  -- handle command
  if cmd.type == "insert" then
    local line, col, text = table.unpack(cmd)
    self.doc:raw_insert(line, col, text, redo_stack, cmd.time, self.selections)
  elseif cmd.type == "remove" then
    local line1, col1, line2, col2 = table.unpack(cmd)
    self.doc:raw_remove(line1, col1, line2, col2, redo_stack, cmd.time, self.selections)
  elseif cmd.type == "selection" then
    self.selections = { table.unpack(cmd) }
    self:sanitize_selection()
  end

  modified = modified or (cmd.type ~= "selection")

  -- if next undo command is within the merge timeout then treat as a single
  -- command and continue to execute it
  local next = undo_stack[undo_stack.idx - 1]
  if next and math.abs(cmd.time - next.time) < config.undo_merge_timeout then
    return pop_undo(self, undo_stack, redo_stack, modified)
  end
  
  if modified then for i,v in ipairs(self.doc.listeners) do v:on_doc_change("undo") end end
end

function DocView:undo()
  pop_undo(self, self.doc.undo_stack, self.doc.redo_stack, false)
end

function DocView:redo()
  pop_undo(self, self.doc.redo_stack, self.doc.undo_stack, false)
end



--[[
Virtual Lines Section

self.dcache holds a table of tokens for the relevant line.
self.vcache holds a reference to the doc line that's relevant for this vline, and offset into this table for this number.
self.dtovcache maps the doc line number onto the earliest relevant virtual line number.
Each token can contain *at most* one new line, at the end of it.
]]

local function mkvoffset(line, offset) return ((line << 32) | offset) end
local function getvoffset(number) if not number then return nil end return number >> 32, number & 0xFFFFFFFF end

local function tokenize_line(self, vlines, line, start_new_vline)
  local tokens = self:tokenize(line)
  local new_vlines = 0
  if #tokens > 0 and start_new_vline then
    table.insert(vlines, mkvoffset(line, 1))
  end
  for j = 1, #tokens, 5 do
    local text = self:get_token_text(tokens[j], tokens[j+1], tokens[j+2], tokens[j+3])
    if text:find("\n$") then
      new_vlines = new_vlines + 1
      if j < #tokens - 5 then
        table.insert(vlines, mkvoffset(line, j + 5))
      end
    end
  end
  return tokens, new_vlines
end

function DocView:previous_tokens_end_in_newline(line)
  local prev_dcache
  if line > 1 and line <= #self.dcache then
    local vline = self.dtovcache[line]
    for i = getvoffset(self.vcache[vline]), #self.dcache do
      if #self.dcache[i] > 0 then
        local nvline = getvoffset(self.dtovcache[vline])
        if not nvline or nvline > vline then break end
        prev_dcache = self.dcache[i]
      end
    end
  end
  return not prev_dcache or self:get_token_text(prev_dcache[#prev_dcache - 4], prev_dcache[#prev_dcache - 3], prev_dcache[#prev_dcache - 2], prev_dcache[#prev_dcache - 1]):find("\n$")
end

function DocView:dump_virtual_lines()
  for i = 1, #self.dcache do
    print("V", i, self.dcache[i])
  end
end

function DocView:tokens_end_in_newline(line)
  if line <= 0 or line > #self.dcache then return true end
  local dline = self.dcache[line]
  return #dline >= 5 and self:get_token_text(dline[#dline - 4], dline[#dline - 3], dline[#dline - 2], dline[#dline - 1]):find("\n$")
end

-- returns the doc line and token offset associated with this line/vline.
function DocView:retrieve_tokens(vline, line)
  -- tokenize up until we have the tokens required for the specified line or vline
  while ((vline and vline > #self.vcache) or (line and line > #self.dcache)) and #self.dcache < #self.doc.lines do
    local vlines = {}
    local prev_newline = self:previous_tokens_end_in_newline(#self.dcache)
    local current_vline = prev_newline and #self.vcache + 1 or #self.vcache
    repeat
      local tokens, new_vlines = tokenize_line(self, vlines, #self.dcache + 1, prev_newline)
      table.insert(self.dcache, tokens)
      self.dtovcache[#self.dcache] = current_vline
      current_vline = current_vline + new_vlines
      prev_newline = new_vlines > 0
      if new_vlines > 0 then break end
    until #self.dcache >= #self.doc.lines - 1
    table.move(vlines, 1, #vlines, #self.vcache + 1, self.vcache)
  end
  -- if we have the tokens,return them
  if vline and self.vcache[vline] then return getvoffset(self.vcache[vline]) end
  if line and self.dcache[line] then return line, 1 end
  -- If we're here, it means we need to tokenize a block of lines in the middle of the document. Start from the beginning up until the relevant line.
  if (vline and vline < #self.vcache) or (line and line < #self.dcache) then    
    local start_line, end_line
    if vline then
      local invalid_line = vline
      while not self.vcache[invalid_line - 1] and invalid_line > 1 do
        invalid_line = invalid_line - 1
      end
      if invalid_line > 1 then
        local l, offset = getvoffset(self.vcache[invalid_line - 1])
        start_line = l + 1
        while self.dcache[start_line] do
          start_line = start_line + 1
        end
        vline = invalid_line
      else
        start_line = 1
        vline = 1
      end
      while self.vcache[invalid_line + 1] == false do
        invalid_line = invalid_line + 1
      end
      local l, offset = getvoffset(self.vcache[invalid_line + 1])
      end_line = l - 1
    else
      end_line = line
      start_line = line
      while self.dcache[start_line - 1] == false and start_line > 1 do
        start_line = start_line - 1
      end
      if start_line > 1 then
        vline = self.dtovcache[start_line - 1] + self:get_vlines(start_line - 1)
      else
        vline = 1
      end
    end

    -- From start to end of the block, compute all new tokens, and insert them appropriately.
    local total_vlines = {}
    local start_vline = vline
    local total_free_vlines = 0
    for i = start_vline, #self.vcache do
      if self.vcache[i] then break end
      total_free_vlines = total_free_vlines + 1
    end
    local start_new_vline = self:tokens_end_in_newline(start_line - 1) 
    for i = start_line, end_line do
      self.dtovcache[i] = vline
      local tokens, new_vlines = tokenize_line(self, total_vlines, i, start_new_vline)
      start_new_vline = new_vlines > 0
      self.dcache[i] = tokens
      vline = vline + new_vlines
    end
    -- Adjust the vcache as necessary to ensure that we have enough space.
    local differential = #total_vlines - total_free_vlines
    if differential ~= 0 then
      table.move(self.vcache, start_vline + total_free_vlines, #self.vcache, start_vline + #total_vlines)
      if differential < 0 then
        for i = 1, -differential do table.remove(self.vcache) end
      end
      for i = end_line + 1, #self.dtovcache do
        self.dtovcache[i] = self.dtovcache[i] + differential
      end
    end
    table.move(total_vlines, 1, #total_vlines, start_vline, self.vcache)
    return end_line, 1
  end
  return #self.doc.lines, #self.dcache[#self.doc.lines] - 4
end


-- This function is very important, and is always potentially more destructive
-- than indicated with its parameters. It will invalidate *at least* as much as
-- you specify, but may invalidate more.
function DocView:invalidate_cache(start_doc_line, end_doc_line)
  if not start_doc_line and not end_doc_line then self.vcache, self.dcache, self.dtovcache = {}, {}, {} return end
  if not start_doc_line then start_doc_line = 1 end
  if not end_doc_line then end_doc_line = #self.dcache end
  if end_doc_line >= #self.dcache then
    while #self.dcache >= start_doc_line or (not self.dcache[#self.dcache] and #self.dcache > 0) do table.remove(self.dcache) end
    while self.vcache[#self.vcache] ~= nil do
      local line, offset = getvoffset(self.vcache[#self.vcache])
      if line and line < start_doc_line then break end
      table.remove(self.vcache)
    end
  else
    for line = start_doc_line, end_doc_line do
      if self.dcache[line] then
        self.dcache[line] = false
        for vline = self.dtovcache[line], #self.vcache do
          local l, offset = getvoffset(self.vcache[vline])
          if l ~= line then break end
          self.vcache[vline] = false
        end
      end
    end
  end
end
function DocView:ensure_cache(start_vline, end_vline) 
  for i = end_vline, start_vline, -1 do self:retrieve_tokens(i) end
  return start_vline, end_vline
end

function DocView:get_token_text(type, doc_line, col_start, col_end)
  return type == "doc" and self.doc.lines[doc_line]:usub(col_start, col_end) or col_start
end


function DocView:has_tokens(line)
  local line, offset = self:retrieve_tokens(nil, line)
  return line <= #self.dcache and #self.dcache[line] > 0
end


local function vline_iter(state, position)
  local self, line2, offset2 = table.unpack(state)
  local line, offset = getvoffset(position)
  if line <= 0 or line > line2 or (line == line2 and offset >= offset2) then return nil end
  -- specifically for vlines, we do not include the newline character, as it is implied
  local text = self:get_token_text(self.dcache[line][offset], self.dcache[line][offset+1], self.dcache[line][offset+2], self.dcache[line][offset+3])
  if offset + 5 > #self.dcache[line] then
    -- skip over all empty lines
    local newline = line
    repeat
      newline = newline + 1
    until newline >= #self.dcache or self.dcache[newline] == false or #self.dcache[newline] > 0
    position = mkvoffset(newline, 1)
  else
    position = mkvoffset(line, offset + 5)
  end
  return position, text, self.dcache[line][offset+4], self.dcache[line][offset], line, offset
end


local function token_iter(state, idx)
  local self, tokens = table.unpack(state)
  if idx > #tokens then return nil end
  return idx + 5, tokens[idx], tokens[idx+1], tokens[idx+2], tokens[idx+3], tokens[idx+4]
end

local function dline_iter(state, idx)
  local self, line = table.unpack(state)
  local tokens = self.dcache[line]
  if not idx or idx > #tokens then return nil end
  local text = self:get_token_text(tokens[idx], tokens[idx+1], tokens[idx+2], tokens[idx+3])
  return idx + 5, text, tokens[idx+4], tokens[idx]
end


function DocView:each_vline_token(vline)
  local line1, offset1 = self:retrieve_tokens(vline)
  local line2, offset2 = self:retrieve_tokens(vline + 1)
  if vline == #self.vcache then
    return vline_iter, { self, line2 + 1, 1 }, mkvoffset(line1, offset1)
  end
  return vline_iter, { self, line2, offset2 }, mkvoffset(line1, offset1)
end
function DocView:each_line_token(line)
  local l = self:retrieve_tokens(nil, line)
  return dline_iter, { self, line }, l and 1
end
function DocView:each_token(tokens, idx) return token_iter, { self, tokens }, (((idx or 1) - 1) * 5) + 1 end
-- utility function designed to be used in plugins
-- accumulates all tokens, but calls `func(output(input, merge_style), text, style)` for the `doc` tokens
-- if input matches text over the course of the function call, will treat these as `doc` tokens, otherwise `virtual` tokens
function DocView:accumulate_tokens(tokens, func, options)
  local t = {}
  options = options or {}
  for i = 1, #tokens, 5 do
    if tokens[i] == "doc" or options.virtual then
      local type, doc_line, col_start, col_end, token_style = tokens[i], tokens[i + 1], tokens[i + 2], tokens[i + 3], tokens[i + 4]
      local token_text = self:get_token_text(type, doc_line, col_start, col_end)
      local offset = 1
      func(function(part_text, part_style)
        if token_text:find(part_text, offset, true) == offset then
          table.insert(t, "doc")
          table.insert(t, doc_line)
          table.insert(t, offset + col_start - 1)
          table.insert(t, offset + col_start + #part_text - 2)
          offset = offset + #part_text
        else
          table.insert(t, "virtual")
          table.insert(t, doc_line)
          table.insert(t, part_text)
          table.insert(t, false)
        end
        table.insert(t, part_style and common.merge(token_style, part_style) or token_style)
      end, token_text, token_style)
    else
      table.move(tokens, i, i + 4, #t + 1, t)
    end
  end
  return t
end
function DocView:get_vline_width(vline)
  local width = 0
  for _, text, style, type in self:each_vline_token(vline) do
    width = width + (style.font or self:get_font()):get_width(text)
  end
  return width
end
function DocView:get_vline_length(vline)
  local length = 0
  for _, text, style, type in self:each_vline_token(vline) do
    length = length + text:ulen()
  end
  return length
end
function DocView:get_total_vlines() return #self.vcache end
function DocView:get_vlines(line)
  local vlines = 0
  for i = self.dtovcache[line], #self.vcache do
    local l, offset = getvoffset(self.vcache[i])
    if l ~= line then break end
    vlines = vlines + 1
  end
  return vlines
end

function DocView:get_vline(line, col, rounding)
  if not line then line = 1 end
  if not col then col = 1 end
  if not rounding then rounding = "next" end
  line = self:retrieve_tokens(nil, line)
  if not line then return #self.vcache + 1, 1 end
  local vline, vcol = self.dtovcache[line], 1
  local offset = 1
  while vline <= #self.vcache do
    for _, text, style, type, dline, offset in self:each_vline_token(vline) do
      local width = (text:ulen() or #text)
      if type == "doc" then
        -- if we've gone too far, vomit out the start of the token
        if dline > line or (dline == line and col < self.dcache[dline][offset+2]) then
          return vline, vcol
        elseif dline == line and col >= self.dcache[dline][offset+2] and col <= self.dcache[dline][offset+3] then
          return vline, vcol + (col - self.dcache[dline][offset+2]) 
        end
      end
      vcol = vcol + width
    end
    vline = vline + 1
    vcol = 1
  end
  return vline, 1
end

-- if we are translating from virtual to doc space, and there is ambiguity about which
-- `rounding` should be either "prev" or "next".
function DocView:get_dline(vline, vcol, rounding)
  if vline <= 0 then return 1, 1 end
  if not vcol then vcol = 1 end
  if not rounding then rounding = "next" end
  local total_line_length = 0
  local last_dline = #self.doc.lines
  local last_doc_token_line, last_doc_token_offset
  for _, text, _, type, dline, offset in self:each_vline_token(vline) do
    local length = text:ulen() or #text
    if total_line_length + length >= vcol then
      if type == "doc" then
        return dline, (vcol - total_line_length) + self.dcache[dline][offset+2] - 1
      elseif rounding == "prev" then
        return last_doc_token_line, self.dcache[dline][last_doc_token_offset+3]
      end
    end
    if type == "doc" then
      last_doc_token_line, last_doc_token_offset = dline, offset
    end
    total_line_length = total_line_length + length
    last_dline = dline
  end
  return last_dline, self.doc.lines[last_dline]:ulen() or #self.doc.lines[last_dline] - 1
end

function DocView:get_vselections(sort_intra, idx_reverse)
  if not self.vselections or not self.vselections[sort_intra] then
    local vselections = {}
    for lidx, line1, col1, line2, col2 in self:get_selections(sort_intra) do
      local vline1, vcol1 = self:get_vline(line1, col1)
      local vline2, vcol2 = self:get_vline(line2, col2)
      table.insert(vselections, vline1)
      table.insert(vselections, vcol1)
      table.insert(vselections, vline2)
      table.insert(vselections, vcol2)
    end
    if not self.vselections then self.vselections = {} end
    self.vselections[sort_intra] = vselections
  end
  return selection_iterator, { self.vselections[sort_intra], false, idx_reverse, self },
      idx_reverse == true and ((#vselections / 4) + 1) or ((idx_reverse or -1) + 1)
end

DocView.position_offset_func = Doc.position_offset_func
DocView.position_offset = Doc.position_offset
DocView.position_offset_linecol = Doc.position_offset_linecol
function DocView:position_offset_byte(line, col, offset)
  local pos
  line, pos = self:retrieve_tokens(nil, line)
  if offset > 0 then
    local remaining_characters
    while line do
      local tokens = self.dcache[line]
      for i = pos, #tokens, 5 do
        if tokens[i] == "doc" then
          local length = tokens[i+3] - tokens[i+2] + 1
          if not remaining_characters and col >= tokens[i+2] then
            remaining_characters = col - tokens[i+2] + offset
          end
          if remaining_characters then
            if remaining_characters < length then
              return line, tokens[i + 2] + remaining_characters
            end
            remaining_characters = remaining_characters - length
          end
        end
      end
      if line == #self.doc.lines then break end
      line = self:retrieve_tokens(nil, line + 1)
      pos = 1
    end
    return #self.doc.lines, self.doc.lines[#self.doc.lines]:ulen()
  else
    local from_token_end
    while line and line > 0 do
      local tokens = self.dcache[line]
      for i = pos, 1, -5 do
        if tokens[i] == "doc" then
          local width = tokens[i+3] - tokens[i+2] + 1
          if not from_token_end then
            if col >= tokens[i+2] then
              from_token_end = tokens[i+3] - col - offset
            end
          end
          if from_token_end then
            if from_token_end < width then
              return line, tokens[i+3] - from_token_end
            end
            from_token_end = from_token_end - width
          end
        end
      end
      if line <= 1 then break end
      line = self:retrieve_tokens(nil, line - 1)
      pos = line and (#self.dcache[line] - 4)
    end
    return 1,1
  end
end


return DocView
