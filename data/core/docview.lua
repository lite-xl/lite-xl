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

DocView.context = "session"

local function move_to_line_offset(dv, dline, dcol, offset)
  local vline, vcol = dv:get_closest_vline(dline, dcol)
  local xo = dv.last_x_offset
  if xo.line ~= vline or xo.col ~= vcol then
    xo.x, xo.y = dv:get_line_screen_position(dline, dcol)
  end
  xo.line, xo.col = dv:get_dline(math.max(vline + offset, 1), vcol)
  return xo.line, xo.col
end


DocView.translate = {
  ["previous_page"] = function(self, dline, col)
    local min, max = self:get_visible_virtual_line_range()
    return move_to_line_offset(self, dline, col, (min - max))
  end,

  ["next_page"] = function(self, dline, col)
    if dline == #self.doc.lines then
      return #self.doc.lines, #self.doc.lines[dline]
    end
    local min, max = self:get_visible_virtual_line_range()
    return move_to_line_offset(self, dline, col, (max - min))
  end,

  ["previous_line"] = function(self, dline, col)
    if dline == 1 then
      return 1, 1
    end
    return move_to_line_offset(self, dline, col, -1)
  end,

  ["next_line"] = function(self, dline, col)
    if dline == #self.doc.lines then
      return #self.doc.lines, math.huge
    end
    return move_to_line_offset(self, dline, col, 1)
  end,
}


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
  self.tokens = {}
  self.vcache = {}
  self.dcache = {}
  self.dtovcache = {}
  self.lines = doc.lines
  self.selections = { 1, 1, 1, 1 }
  self.last_selection = 1
  self.v_scrollbar:set_forced_status(config.force_scrollbar_status)
  self.h_scrollbar:set_forced_status(config.force_scrollbar_status)
  table.insert(doc.listeners, function(...) self:listener(...) end)
end

function DocView:get_char(line, col)
  line, col = self.doc:sanitize_position(line, col)
  return self.doc.lines[line]:sub(col, col)
end

function DocView:position_offset_byte(line, col, offset)
  local token_idx = self:get_dline_token_idx(line, col)
  if offset > 0 then
    if self.tokens[token_idx+1] ~= line or col < self.tokens[token_idx+2] then
      line, col = self.tokens[token_idx+1], self.tokens[token_idx+3]
    end
    local total_offset = (col + offset) - self.tokens[token_idx+2]
    for i = token_idx, #self.tokens, 5 do
      if self.tokens[i] == "doc" then
        local width = (self.tokens[i+3] - self.tokens[i+2]) + 1
        if total_offset < width then
          return self.tokens[i+1], self.tokens[i+2] + total_offset
        end
        total_offset = total_offset - width
      end
    end
    return #self.doc.lines, #self.doc.lines[#self.doc.lines]
  else
    if self.tokens[token_idx+1] ~= line or col < self.tokens[token_idx+2] then
      line, col = self.tokens[token_idx+1], self.tokens[token_idx+3]
    end
    local total_offset = self.tokens[token_idx+3] - (col + offset)
    for i = token_idx, 1, -5 do
      if self.tokens[i] == "doc" then
        local width = (self.tokens[i+3] - self.tokens[i+2]) + 1
        if total_offset < width then
          return self.tokens[i+1], self.tokens[i+3] - total_offset
        end
        total_offset = total_offset - width
      end
    end
  end
  return 1,1
end

function DocView:sanitize_position(line, col)
  return self.doc:sanitize_position(line, col)
end

DocView.position_offset_func = Doc.position_offset_func
DocView.position_offset = Doc.position_offset


function DocView:get_closest_vline(dline, dcol)
  local token_idx = self:retrieve_tokens(nil, dline)
  if not token_idx then
    return #self.vcache + 1, 1
  end
  if self.tokens[token_idx+1] ~= dline then return self.dtovcache[dline] end
  local total_line_length = 0
  local total_token_length = 0
  local vline = self.dtovcache[dline]
  if dcol and dcol > 1 then
    for _, text, _, type in self:each_dline_token(dline) do
      if type == "doc" then
        local length = text:ulen() or #text
        if dcol <= total_token_length + total_line_length + length then
          return vline, dcol - total_line_length
        end
        total_token_length = total_token_length + length
      end
      if text:find("\n$") then
        total_line_length = total_line_length + total_token_length
        vline = vline + 1
      end
    end
  end
  return vline, 1
end

function DocView:get_dline(vline, vcol)
  local dline = self.tokens[self:retrieve_tokens(vline) + 1]
  local total_line_length = 0
  local current_line = self.dtovcache[dline]
  for _, text, _, type in self:each_dline_token(dline) do
    if current_line == vline then
      return dline, vcol + total_line_length
    end
    if type == "doc" then total_line_length = total_line_length + text:ulen() end
    if text:find("\n$") then
      current_line = current_line + 1
    end
  end
  return dline, vcol
end

function DocView:get_virtual_line_offset(vline)
  local lh = self:get_line_height()
  local x, y = self:get_content_offset()
  local gw = self:get_gutter_width()
  return x + gw, y + lh * (vline - 1)
end

function DocView:get_line_screen_position(line, col)
  local x, y = self:get_content_offset()
  local lh = self:get_line_height()
  local gw = self:get_gutter_width()
  local vline, vcol = self:get_closest_vline(line, col)
  y = y + (vline-1) * lh
  if col and self.vcache[vline] and self.tokens[self.vcache[vline]+1] == line then
    local default_font = self:get_font()
    local _, indent_size = self.doc:get_indent_info()
    default_font:set_tab_size(indent_size)
    local column = 1
    local xoffset = 0
    for _, text, style, type in self:each_vline_token(vline) do
      local font = style.font or default_font
      if font ~= default_font then font:set_tab_size(indent_size) end
      local length = text:ulen()
      if type == "doc" then
        if column + length < vcol then
          xoffset = xoffset + font:get_width(text)
          column = column + length
        else
          for char in common.utf8_chars(text) do
            if column >= vcol then
              return x + gw + xoffset, y
            end
            xoffset = xoffset + font:get_width(char)
            column = column + 1
          end
        end
      else
        xoffset = xoffset + font:get_width(text)
      end
    end
    return x + gw + xoffset, y
  else
    return x + gw, y
  end
end


function DocView:resolve_screen_position(x, y)
  local ox, oy = self:get_virtual_line_offset(1)
  local vline = math.floor((y - oy) / self:get_line_height()) + 1

  local xoffset, last_i, i = ox, 1, 1
  local default_font = self:get_font()
  local _, indent_size = self.doc:get_indent_info()
  default_font:set_tab_size(indent_size)
  local line = self.tokens[self.vcache[vline]+1]
  for _, text, style in self:each_vline_token(vline) do
    local font = style.font or default_font
    if font ~= default_font then font:set_tab_size(indent_size) end
    local width = font:get_width(text)
    -- Don't take the shortcut if the width matches x,
    -- because we need last_i which should be calculated using utf-8.
    if xoffset + width < x then
      xoffset = xoffset + width
      i = i + text:ulen()
    else
      for char in common.utf8_chars(text) do
        local w = font:get_width(char)
        if xoffset >= x then
          return line, (xoffset - x > w / 2) and last_i or i
        end
        xoffset = xoffset + w
        last_i = i
        i = i + 1
      end
    end
  end
  return line, i
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


local function vselection_iterator(invariant, idx)
  local target = invariant[3] and (idx * 4 - 7) or (idx * 4 + 1)
  if target > #invariant[1] or target <= 0 or (type(invariant[3]) == "number" and invariant[3] ~= idx - 1) then return end
  local line1, col1, line2, col2
  if invariant[2] then
    line1, col1, line2, col2 = common.sort_positions(table.unpack(invariant[1], target, target + 4))
  else
    line1, col1, line2, col2 = table.unpack(invariant[1], target, target + 4)
  end
  line1, col1 = invariant[4]:get_closest_vline(line1, col1)
  line2, col2 = invariant[4]:get_closest_vline(line2, col2)
  return idx + (invariant[3] and -1 or 1), line1, col1, line2, col2
end


function DocView:get_vselections(...)
  return vselection_iterator, select(2, self:get_selections(...))
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
      self.doc:remove(line1, col1, translate.next_char(self, line1, col1))
    end

    self.doc:insert(line1, col1, text)
    self:move_to_cursor(sidx, #text)
  end
end

function DocView:listener(type, text, line1, col1, line2, col2)
  self:invalidate_cache(line1, line2)
  -- keep cursors where they should be on insertion
  -- for idx, cline1, ccol1, cline2, ccol2 in self:get_selections(true, true) do
  --   if cline1 < line then break end
  --   local line_addition = (line < cline1 or col < ccol1) and #lines - 1 or 0
  --   local column_addition = line == cline1 and ccol1 > col and len or 0
  --   self:set_selections(idx, cline1 + line_addition, ccol1 + column_addition, cline2 + line_addition,
  --     ccol2 + column_addition)
  -- end


  -- keep selections in correct positions on removal: each pair (line, col)
  -- * remains unchanged if before the deleted text
  -- * is set to (line1, col1) if in the deleted text
  -- * is set to (line1, col - col_removal) if on line2 but out of the deleted text
  -- * is set to (line - line_removal, col) if after line2
  -- for idx, cline1, ccol1, cline2, ccol2 in self:get_selections(true, true) do
  --   if cline2 < line1 then break end
  --   local l1, c1, l2, c2 = cline1, ccol1, cline2, ccol2

  --   if cline1 > line1 or (cline1 == line1 and ccol1 > col1) then
  --     if cline1 > line2 then
  --       l1 = l1 - line_removal
  --     else
  --       l1 = line1
  --       c1 = (cline1 == line2 and ccol1 > col2) and c1 - col_removal or col1
  --     end
  --   end

  --   if cline2 > line1 or (cline2 == line1 and ccol2 > col1) then
  --     if cline2 > line2 then
  --       l2 = l2 - line_removal
  --     else
  --       l2 = line1
  --       c2 = (cline2 == line2 and ccol2 > col2) and c2 - col_removal or col1
  --     end
  --   end

  --   if l1 == line1 and c1 == col1 then merge = true end
  --   self:set_selections(idx, l1, c1, l2, c2)
  -- end

  -- if merge then
  --   self:merge_cursors()
  -- end
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
    self:insert(line1, col1, text)
    self:set_selections(sidx, line1, col1 + #text, line1, col1)
  end
end

function DocView:replace_cursor(idx, line1, col1, line2, col2, fn)
  local old_text = self.doc:get_text(line1, col1, line2, col2)
  local new_text, res = fn(old_text)
  if old_text ~= new_text then
    self:insert(line2, col2, new_text)
    self:remove(line1, col1, line2, col2)
    if line1 == line2 and col1 == col2 then
      line2, col2 = self.doc:position_offset(line1, col1, #new_text)
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
      self.doc:remove(line1, col1, line2, col2)
    else
      local l2, c2 = self:position_offset(line1, col1, ...)
      self.doc:remove(line1, col1, l2, c2)
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
        self.doc:remove(line, 1, line, (e or 0) + 1)
        self.doc:insert(line, 1,
          unindent and rnded:sub(1, #rnded - #text) or rnded .. text)
      end
    end
    l1d, l2d = #self.doc.lines[line1] - l1d, #self.doc.lines[line2] - l2d
    if (unindent or in_beginning_whitespace) and not has_selection then
      local start_cursor = (se and se + 1 or 1) + l1d or #(self.lines[line1])
      return line1, start_cursor, line2, start_cursor
    end
    return line1, col1 + l1d, line2, col2 + l2d
  end
  self.doc:insert(line1, col1, text)
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
  local max_lines = math.max(#self.doc.lines, #self.vcache)
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
  local maxline = math.floor((y2 - style.padding.y) / lh) + 1
  return minline, maxline
end


function DocView:get_visible_line_range()
  local minline, maxline = self:get_visible_virtual_line_range()
  return self.vcache[self:retrieve_tokens(minline) + 1], self.vcache[self:retrieve_tokens(maxline) + 1]
end


function DocView:scroll_to_line(line, ignore_if_visible, instant, col)
  local min, max = self:get_visible_virtual_line_range()
  if not (ignore_if_visible and line > min and line < max) then
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
  return true
end


function DocView:scroll_to_make_visible(line, col)
  local ox, oy = self:get_content_offset()
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
  self.doc:ime_text_editing(text, start, length)
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
function DocView:draw_line_text(line, x, y)
  local default_font = self:get_font()
  local tx, ty = x, y + self:get_line_text_y_offset()
  local otx = tx
  local lines = 0
  for tidx, text, style in self:each_dline_token(line) do
    local font = style.font or default_font
    tx = renderer.draw_text(font, text, tx, ty, style.color or default_color)
    if tx > self.position.x + self.size.x then break end
    if text:find("\n$") then
      tx = otx
      lines = lines + 1
    end
  end
  return self:get_line_height() * lines
end


function DocView:draw_overwrite_caret(x, y, width)
  local lh = self:get_line_height()
  renderer.draw_rect(x, y + lh - style.caret_width, width, style.caret_width, style.caret)
end


function DocView:draw_caret(x, y)
  local lh = self:get_line_height()
  renderer.draw_rect(x, y, style.caret_width, lh, style.caret)
end

function DocView:draw_line(line, x, y)
  local gw, gpad = self:get_gutter_width()
  self:draw_line_gutter(line, x, y, gpad and gw - gpad or gw)
  core.push_clip_rect(self.position.x + gw, self.position.y, self.size.x - gw, self.size.y)
  local lh = self:draw_line_body(line, x + gw, y)
  core.pop_clip_rect()
  return lh
end

function DocView:draw_line_body(line, x, y)
  -- draw highlight if any selection ends on this line
  local draw_highlight = false
  local hcl = config.highlight_current_line
  if hcl ~= false then
    for lidx, line1, col1, line2, col2 in self:get_vselections(false) do
      if line1 == line then
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
  for lidx, line1, col1, line2, col2 in self:get_selections(true) do
    if line >= line1 and line <= line2 then
      local text = self.doc.lines[line]
      if line1 ~= line then col1 = 1 end
      if line2 ~= line then col2 = #text + 1 end
      local _, x1 = x + self:get_line_screen_position(line1, col1)
      local _, x2 = x + self:get_line_screen_position(line2, col2)
      if x1 ~= x2 then
        renderer.draw_rect(x1, y, x2 - x1, lh, style.selection)
      end
    end
  end

  -- draw line's text
  return self:draw_line_text(line, x, y)
end


function DocView:draw_line_gutter(line, x, y, width)
  local color = style.line_number
  for _, line1, _, line2 in self:get_vselections(true) do
    if line >= line1 and line <= line2 then
      color = style.line_number2
      break
    end
  end
  x = x + style.padding.x
  local lh = self:get_line_height()
  common.draw_text(self:get_font(), color, line, "right", x, y, width, lh)
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
      if system.window_has_focus() then
        if ime.editing then
          self:draw_ime_decoration(line1, col1, line2, col2)
        else
          if config.disable_blink
          or (core.blink_timer - core.blink_start) % T < T / 2 then
            local x, y = self:get_line_screen_position(line1, col1)
            if self.doc.overwrite then
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

  local minline, maxline = self:get_visible_virtual_line_range()
  local gw, gpad = self:get_gutter_width()
  local lh = self:get_line_height()
  local x, y = self:get_virtual_line_offset(minline)
  for i = minline, maxline do
    y = y + self:draw_line(i, x - gw, y) or lh
  end
  self:draw_overlay()

  self:draw_scrollbar()
end


-- Selections are in document space.
-- Tokenize function for lines from the doc.
-- Plugins hook this to return a line/col list from `doc`, or provide a virtual line.
-- `{ "doc", doc_line, 1, #self.doc.lines[doc_line], style }`
-- `{ "virtual", doc_line, text, false, style }
function DocView:tokenize(doc_line)
  return { "doc", doc_line, 1, #self.doc.lines[doc_line], { } }
end

--[[
self.vcache maps virtual line numbers to the point in the self.tokens array where that line starts. It is always guaranteed to be correct, up until the point where it's invalid.
self.dcache maps doc line number sto the point in the self.tokens array where that line starts. It is always guaranteed to be correct, up until the point where it's invalid.
self.dtovcache maps the doc line number onto the earliest relevant virtual line number.
self.tokens contains the stream of transformed tokens.
Each token can contain *at most* one new line, at the end of it.
]]

function DocView:is_first_line_of_block(vline)
  local token_idx = self.vcache[vline]
  return token_idx == self.dcache[self.tokens[token_idx + 1]]
end

function DocView:invalidate_cache(start_doc_line)
  if not start_doc_line then start_doc_line = 1 end
  while #self.tokens >= self.dcache[start_doc_line] do table.remove(self.tokens) end
  while #self.dcache >= start_doc_line do table.remove(self.dcache) end
  while (self.vcache[#self.vcache] or 0) > #self.tokens do table.remove(self.vcache) end
end

function DocView:get_token_text(type, doc_line, col_start, col_end)
  return type == "doc" and self.doc.lines[doc_line]:sub(col_start, col_end) or col_start
end


function DocView:has_tokens(vline)
  local token_idx = self:retrieve_tokens(vline)
  return token_idx and token_idx < #self.tokens and token_idx ~= self:retrieve_tokens(vline + 1)
end


local function vline_iter(state, idx)
  local self, line = table.unpack(state)
  if not idx or not self.tokens[idx] or (self.vcache[line + 1] and idx >= self.vcache[line + 1]) then return nil end
  local text = self:get_token_text(self.tokens[idx], self.tokens[idx+1], self.tokens[idx+2], self.tokens[idx+3])
  return idx + 5, text, self.tokens[idx+4], self.tokens[idx]
end


local function token_iter(state, idx)
  local self, tokens = table.unpack(state)
  if idx > #tokens then return nil end
  return idx + 5, tokens[idx], tokens[idx+1], tokens[idx+2], tokens[idx+3], tokens[idx+4]
end

local function dline_iter(state, idx)
  local self, line = table.unpack(state)
  if not idx or not self.tokens[idx] or self.tokens[idx+1] ~= line then return nil end
  local text = self:get_token_text(self.tokens[idx], self.tokens[idx+1], self.tokens[idx+2], self.tokens[idx+3])
  return idx + 5, text, self.tokens[idx+4], self.tokens[idx]
end


function DocView:retrieve_tokens(vline, dline)
  while ((vline and vline > #self.vcache) or (dline and dline > #self.dcache)) and #self.dcache < #self.doc.lines do
    local tokens = self:tokenize(#self.dcache + 1)
    local bundles = #tokens / 5
    table.insert(self.dcache, #self.tokens + 1)
    if #tokens > 0 then
      table.insert(self.vcache, #self.tokens + 1)
    end
    self.dtovcache[#self.dcache] = #self.vcache
    for j = 1, #tokens, 5 do
      local text = self:get_token_text(tokens[j], tokens[j+1], tokens[j+2], tokens[j+3])
      table.move(tokens, j, j+4, #self.tokens + 1, self.tokens)
      if text:find("\n$") and j < #tokens - 5 then
        table.insert(self.vcache, #self.tokens + 1)
      end
    end
  end
  if vline then return self.vcache[vline] end
  return self.dcache[dline]
end

function DocView:each_vline_token(vline) return vline_iter, { self, vline }, self:retrieve_tokens(vline) end
function DocView:each_token(tokens, line) return token_iter, { self, tokens }, (((line or 1) - 1) * 5) + 1 end
function DocView:each_dline_token(line) return dline_iter, { self, line }, self:retrieve_tokens(nil, line) end

function DocView:get_dline_token_idx(dline, dcol)
  for i = self:retrieve_tokens(nil, dline), #self.tokens, 5 do
    if self.tokens[i] == "doc" and (self.tokens[i+1] ~= dline or dcol >= self.tokens[i+2]) then
      return i
    end
  end
  return 1
end

return DocView
