-- mod-version:2 -- lite-xl 2.0
local core = require "core"
local common = require "core.common"
local DocView = require "core.docview"
local Doc = require "core.doc"
local style = require "core.style"
local config = require "core.config"
local command = require "core.command"
local translate = require "core.doc.translate"

local LineWrapping = { mode = "letter", width_override = 150 }

-- 
function LineWrapping:compute_line_breaks(doc, default_font, line, width, mode)
  width = self.width_override or width
  local xoffset, last_i, i = 0, 1, 1
  local splits = { 1 }
  for _, type, text in doc.highlighter:each_token(line) do
    local font = style.syntax_fonts[type] or default_font
    local w = font:get_width(text)
    if xoffset + w > width then
      for char in common.utf8_chars(text) do
        w = font:get_width(char)
        xoffset = xoffset + w
        if xoffset > width then
          table.insert(splits, i)
          xoffset = w
        end
        i = i + #char
      end
    else
      xoffset = xoffset + w
      i = i + #text
    end
  end
  return splits
end

-- breaks are held in a single table that contains n*2 elements, where n is the amount of line breaks.
-- each element represents line and column of the break. line_offset will check from the specified line
-- if the first line has not changed breaks, it will stop there.
function LineWrapping:reconstruct_breaks(doc, default_font, width, line_offset)
  -- list of line/columns
  doc.wrapped_lines = { }
  for i = line_offset or 1, #doc.lines do
    for k, col in ipairs(self:compute_line_breaks(doc, default_font, i, width)) do
      table.insert(doc.wrapped_lines, i)
      table.insert(doc.wrapped_lines, col)
    end
  end
  -- list of indices for wrapped_lines, that are based on original line number
  -- holds the index to the first in the wrapped_lines list
  doc.wrapped_line_to_idx = { }
  local last_wrap = nil
  for i = 1, #doc.wrapped_lines, 2 do
    if not last_wrap or last_wrap ~= doc.wrapped_lines[i] then
      table.insert(doc.wrapped_line_to_idx, (i + 1) / 2)
      last_wrap = doc.wrapped_lines[i]
    end
  end
end

function LineWrapping:get_idx_line_col(doc, idx)
  if not doc.wrapped_lines then 
    if idx > #doc.lines then return #doc.lines, #doc.lines[#doc.lines] + 1 end
    return idx, 1 
  end
  local offset = (idx - 1) * 2 + 1
  if offset > #doc.wrapped_lines then return #doc.lines, #doc.lines[#doc.lines] + 1 end
  return doc.wrapped_lines[offset], doc.wrapped_lines[offset + 1]
end

function LineWrapping:get_idx_line_length(doc, idx)
  if not doc.wrapped_lines then 
    if idx > #doc.lines then return #doc.lines[#doc.lines] + 1 end
    return #doc.lines[idx]
  end
  local offset = (idx - 1) * 2 + 1
  local start = doc.wrapped_lines[offset + 1]
  if doc.wrapped_lines[offset + 2] and doc.wrapped_lines[offset + 2] == doc.wrapped_lines[offset] then
    return doc.wrapped_lines[offset + 3] - doc.wrapped_lines[offset + 1]
  else
    return #doc.lines[doc.wrapped_lines[offset]] - doc.wrapped_lines[offset + 1] + 1
  end
end

-- If line end, gives the end of an index line, rather than the first character of the next line.
function LineWrapping:get_line_idx_col_count(doc, line, col, line_end)
  if not doc.wrapped_lines then return common.clamp(line, 1, #doc.lines), col, 1, 1 end
  if line > #doc.lines then return self:get_line_idx_col_count(doc, #doc.lines, #doc.lines[#doc.lines] + 1) end
  line = math.max(line, 1)
  local idx = doc.wrapped_line_to_idx[line]
  local ncol, scol = 1, 1
  if col then
    local i = idx + 1
    while line == doc.wrapped_lines[(i - 1) * 2 + 1] and col >= doc.wrapped_lines[(i - 1) * 2 + 2] do
      local nscol = doc.wrapped_lines[(i - 1) * 2 + 2]
      if line_end and col == nscol then
        break
      end
      scol = nscol
      i = i + 1
      idx = idx + 1
    end
    ncol = (col - scol) + 1
  end
  local count = (doc.wrapped_line_to_idx[line + 1] or (self:get_total_wrapped_lines(doc) + 1)) - doc.wrapped_line_to_idx[line]
  return idx, ncol, count, scol
end

function LineWrapping:get_total_wrapped_lines(doc)
  if not doc.wrapped_lines then return #doc.lines end
  return #doc.wrapped_lines / 2
end

local function get_line_col_from_index_and_x(doc, default_font, idx, x)
  local line, col = LineWrapping:get_idx_line_col(doc, idx)
  local xoffset, last_i, i = 0, 1, 1
  for _, type, text in doc.highlighter:each_token(line) do
    local font = style.syntax_fonts[type] or default_font
    for char in common.utf8_chars(text) do
      if i > col then
        local w = font:get_width(char)
        if xoffset >= x then
          return line, ((xoffset - x > w / 2) and last_i or i)
        end
        xoffset = xoffset + w
      end
      last_i = i
      i = i + #char
    end
  end
  return line, #doc.lines[line]
end


local old_doc_insert = Doc.raw_insert
function Doc:raw_insert(line, col, text, undo_stack, time)
  old_doc_insert(self, line, col, text, undo_stack, time)
  LineWrapping:reconstruct_breaks(self, core.active_view:get_font(), math.huge)
  self.break_size = math.huge
end

local old_doc_remove = Doc.raw_remove
function Doc:raw_remove(line1, col1, line2, col2, undo_stack, time)
  old_doc_remove(self, line1, col1, line2, col2, undo_stack, time)
  LineWrapping:reconstruct_breaks(self, core.active_view:get_font(), math.huge)
  self.break_size = math.huge
end

local old_doc_update = DocView.update
function DocView:update()
  old_doc_update(self)
  if self.size.x > 0 and (self.doc.break_size == nil or self.size.x ~= self.doc.break_size) then
    LineWrapping:reconstruct_breaks(self.doc, self:get_font(), self.size.x)
    self.doc.break_size = self.size.x
  end
end

function DocView:get_scrollable_size()
  if not config.scroll_past_end then
    return self:get_line_height() * LineWrapping:get_total_wrapped_lines(self.doc) + style.padding.y * 2
  end
  return self:get_line_height() * (LineWrapping:get_total_wrapped_lines(self.doc) - 1) + self.size.y
end

function DocView:get_visible_line_range()
  local x, y, x2, y2 = self:get_content_bounds()
  local lh = self:get_line_height()
  local minline = LineWrapping:get_idx_line_col(self.doc, math.max(1, math.floor(y / lh)))
  local maxline = LineWrapping:get_idx_line_col(self.doc, math.min(LineWrapping:get_total_wrapped_lines(self.doc), math.floor(y2 / lh) + 1))
  return minline, maxline
end

function DocView:get_x_offset_col(line, x)
  local idx = LineWrapping:get_line_idx_col_count(self.doc, line)
  return get_line_col_from_index_and_x(self.doc, self:get_font(), idx, x)
end

-- If line end is true, returns the end of the previous line, in a multi-line break.
function DocView:get_col_x_offset(line, col, line_end)
  local idx, ncol, count, scol = LineWrapping:get_line_idx_col_count(self.doc, line, col, line_end)
  local xoffset, i = 0, 1
  local default_font = self:get_font()
  for _, type, text in self.doc.highlighter:each_token(line) do
    if i + #text >= scol then   
      if i < scol then 
        text = text:sub(scol - i + 1)
        i = scol
      end
      local font = style.syntax_fonts[type] or default_font
      for char in common.utf8_chars(text) do
        if i >= col then
          return xoffset
        end
        xoffset = xoffset + font:get_width(char)
        i = i + #char
      end
    else
     i = i + #text
    end
  end
  return xoffset
end

function DocView:get_line_screen_position(line, col)
  local idx, ncol, count = LineWrapping:get_line_idx_col_count(self.doc, line, col)
  local x, y = self:get_content_offset()
  local lh = self:get_line_height()
  local gw = self:get_gutter_width()
  return x + gw + (col and self:get_col_x_offset(line, col) or 0), y + (idx-1) * lh + style.padding.y
end

function DocView:resolve_screen_position(x, y)
  local ox, oy = self:get_line_screen_position(1)
  local idx = common.clamp(math.floor((y - oy) / self:get_line_height()) + 1, 1, LineWrapping:get_total_wrapped_lines(self.doc))
  return get_line_col_from_index_and_x(self.doc, self:get_font(), idx, x - ox)
end

function DocView:draw_line_text(line, x, y)
  local default_font = self:get_font()
  local tx, ty = x, y + self:get_line_text_y_offset()
  local lh = self:get_line_height()
  local idx, _, count = LineWrapping:get_line_idx_col_count(self.doc, line)
  local total_offset = 1
  for _, type, text in self.doc.highlighter:each_token(line) do
    local color = style.syntax[type]
    local font = style.syntax_fonts[type] or default_font
    local token_offset = 1
    -- Split tokens if we're at the end of the document.
    while token_offset <= #text do
      local next_line, next_line_start_col = LineWrapping:get_idx_line_col(self.doc, idx + 1)
      if next_line ~= line then
        next_line_start_col = #self.doc.lines[line] 
      end
      local max_length = next_line_start_col - total_offset
      local rendered_text = text:sub(token_offset, token_offset + max_length - 1)
      tx = renderer.draw_text(font, rendered_text, tx, ty, color)
      total_offset = total_offset + #rendered_text
      if total_offset ~= next_line_start_col or max_length == 0 then break end
      token_offset = token_offset + #rendered_text
      idx = idx + 1
      tx, ty = x, ty + lh
    end
  end
  return lh * count
end

function DocView:draw_line_body(line, x, y)
  -- draw selection if it overlaps this line
  local lh = self:get_line_height()
  local idx0 = LineWrapping:get_line_idx_col_count(self.doc, line)
  for lidx, line1, col1, line2, col2 in self.doc:get_selections(true) do
    if line >= line1 and line <= line2 then
      if line1 ~= line then col1 = 1 end
      if line2 ~= line then col2 = #self.doc.lines[line] + 1 end
      if col1 ~= col2 then
        local idx1, ncol1 = LineWrapping:get_line_idx_col_count(self.doc, line, col1)
        local idx2, ncol2 = LineWrapping:get_line_idx_col_count(self.doc, line, col2)
        for i = idx1, idx2 do
          local x1, x2 = x + (idx1 == i and self:get_col_x_offset(line1, col1) or 0)
          if idx2 == i then
            x2 = x + self:get_col_x_offset(line, col2)
          else
            x2 = x + self:get_col_x_offset(line, LineWrapping:get_idx_line_length(self.doc, i, line) + 1, true)
          end
          renderer.draw_rect(x1, y + (i - idx0) * lh, x2 - x1, lh, style.selection)
        end
      end
    end
  end
  local draw_highlight = nil
  for lidx, line1, col1, line2, col2 in self.doc:get_selections(true) do
    -- draw line highlight if caret is on this line
    if draw_highlight ~= false and config.highlight_current_line
    and line1 == line and core.active_view == self then
      draw_highlight = (line1 == line2 and col1 == col2)
    end
  end
  if draw_highlight then 
    local _, _, count = LineWrapping:get_line_idx_col_count(self.doc, line)
    for i=1,count do 
      self:draw_line_highlight(x + self.scroll.x, y + lh * (i - 1))
    end
  end
  -- draw line's text
  return self:draw_line_text(line, x, y)
end

local old_draw = DocView.draw
function DocView:draw()
  old_draw(self)
  local x, y = self:get_content_offset()
  local gw = self:get_gutter_width()
  renderer.draw_rect(x + gw + LineWrapping.width_override, y, 1, core.root_view.size.y, style.selection)
end 

local old_draw_line_gutter = DocView.draw_line_gutter
function DocView:draw_line_gutter(line, x, y, width)
  local lh = self:get_line_height()
  local _, _, count = LineWrapping:get_line_idx_col_count(self.doc, line)
  return (old_draw_line_gutter(self, line, x, y, width) or lh) * count
end

function translate.end_of_line(doc, line, col)
  local idx, ncol = LineWrapping:get_line_idx_col_count(self.doc, line, col)
  local nline, ncol2 = LineWrapping:get_idx_line_col(self.doc, idx + 1)
  if nline ~= line then return line, math.huge end
  return line, ncol2 - 1
end

function translate.start_of_line(doc, line, col)
  local idx, ncol = LineWrapping:get_line_idx_col_count(self.doc, line, col)
  local nline, ncol2 = LineWrapping:get_idx_line_col(self.doc, idx - 1)
  if nline ~= line then return line, 1 end
  return line, ncol2 + 1
end

function DocView.translate.previous_line(doc, line, col, dv)
  local idx, ncol = LineWrapping:get_line_idx_col_count(self.doc, line, col)
  local nline, ncol2 = LineWrapping:get_idx_line_col(self.doc, idx - 1)
  if nline ~= line then return line - 1, dv:get_col_x_offset(line, col) end
  return nline, ncol2
end

function DocView.translate.next_line(doc, line, col, dv)
  local idx, ncol = LineWrapping:get_line_idx_col_count(self.doc, line, col)
  local nline, ncol2 = LineWrapping:get_idx_line_col(self.doc, idx + 1)
  if nline ~= line then return line + 1, dv:get_col_x_offset(line, col) end
  return nline, ncol2
end

command.add(nil, {
  ["linewrapping:enable"] = function() 
    LineWrapping.width_override = nil 
  end,
  ["linewrapping:disable"] = function() 
    LineWrapping.width_override = math.huge 
    if core.active_view and core.active_view.doc then
      LineWrapping:reconstruct_breaks(core.active_view.doc)
    end
  end,
})

return LineWrapping
