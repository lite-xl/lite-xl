local core = require "core"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local keymap = require "core.keymap"
local translate = require "core.doc.translate"
local View = require "core.view"

---@class core.docview : core.view
---@field super core.view
local DocView = View:extend()

DocView.context = "session"

local function move_to_line_offset(dv, line, col, offset)
  local xo = dv.last_x_offset
  if xo.line ~= line or xo.col ~= col then
    xo.offset = dv:get_col_x_offset(line, col)
  end
  xo.line = line + offset
  xo.col = dv:get_x_offset_col(line + offset, xo.offset)
  return xo.line, xo.col
end


DocView.translate = {
  ["previous_page"] = function(doc, line, col, dv)
    local min, max = dv:get_visible_line_range()
    return line - (max - min), 1
  end,

  ["next_page"] = function(doc, line, col, dv)
    if line == #doc.lines then
      return #doc.lines, #doc.lines[line]
    end
    local min, max = dv:get_visible_line_range()
    return line + (max - min), 1
  end,

  ["previous_line"] = function(doc, line, col, dv)
    if line == 1 then
      return 1, 1
    end
    return move_to_line_offset(dv, line, col, -1)
  end,

  ["next_line"] = function(doc, line, col, dv)
    if line == #doc.lines then
      return #doc.lines, math.huge
    end
    return move_to_line_offset(dv, line, col, 1)
  end,
}


function DocView:new(doc)
  DocView.super.new(self)
  self.cursor = "ibeam"
  self.scrollable = true
  self.doc = assert(doc)
  self.font = "code_font"
  self.last_x_offset = {}
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
  if not config.scroll_past_end then
    return self:get_line_height() * (#self.doc.lines) + style.padding.y * 2
  end
  return self:get_line_height() * (#self.doc.lines - 1) + self.size.y
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


function DocView:get_line_screen_position(line, col)
  local x, y = self:get_content_offset()
  local lh = self:get_line_height()
  local gw = self:get_gutter_width()
  y = y + (line-1) * lh + style.padding.y
  if col then
    return x + gw + self:get_col_x_offset(line, col), y
  else
    return x + gw, y
  end
end

function DocView:get_line_text_y_offset()
  local lh = self:get_line_height()
  local th = self:get_font():get_height()
  return (lh - th) / 2
end


function DocView:get_visible_line_range()
  local x, y, x2, y2 = self:get_content_bounds()
  local lh = self:get_line_height()
  local minline = math.max(1, math.floor(y / lh))
  local maxline = math.min(#self.doc.lines, math.floor(y2 / lh) + 1)
  return minline, maxline
end


function DocView:get_col_x_offset(line, col)
  local default_font = self:get_font()
  local column = 1
  local xoffset = 0
  for _, type, text in self.doc.highlighter:each_token(line) do
    local font = style.syntax_fonts[type] or default_font
    for char in common.utf8_chars(text) do
      if column == col then
        return xoffset
      end
      xoffset = xoffset + font:get_width(char)
      column = column + #char
    end
  end

  return xoffset
end


function DocView:get_x_offset_col(line, x)
  local line_text = self.doc.lines[line]

  local xoffset, last_i, i = 0, 1, 1
  local default_font = self:get_font()
  for _, type, text in self.doc.highlighter:each_token(line) do
    local font = style.syntax_fonts[type] or default_font
    for char in common.utf8_chars(text) do
      local w = font:get_width(char)
      if xoffset >= x then
        return (xoffset - x > w / 2) and last_i or i
      end
      xoffset = xoffset + w
      last_i = i
      i = i + #char
    end
  end

  return #line_text
end


function DocView:resolve_screen_position(x, y)
  local ox, oy = self:get_line_screen_position(1)
  local line = math.floor((y - oy) / self:get_line_height()) + 1
  line = common.clamp(line, 1, #self.doc.lines)
  local col = self:get_x_offset_col(line, x - ox)
  return line, col
end


function DocView:scroll_to_line(line, ignore_if_visible, instant)
  local min, max = self:get_visible_line_range()
  if not (ignore_if_visible and line > min and line < max) then
    local x, y = self:get_line_screen_position(line)
    local ox, oy = self:get_content_offset()
    self.scroll.to.y = math.max(0, y - oy - self.size.y / 2)
    if instant then
      self.scroll.y = self.scroll.to.y
    end
  end
end


function DocView:scroll_to_make_visible(line, col)
  local ox, oy = self:get_content_offset()
  local _, ly = self:get_line_screen_position(line, col)
  local lh = self:get_line_height()
  self.scroll.to.y = common.clamp(self.scroll.to.y, ly - oy - self.size.y + lh * 2, ly - oy - lh)
  local gw = self:get_gutter_width()
  local xoffset = self:get_col_x_offset(line, col)
  local xmargin = 3 * self:get_font():get_width(' ')
  local xsup = xoffset + gw + xmargin
  local xinf = xoffset - xmargin
  if xsup > self.scroll.x + self.size.x then
    self.scroll.to.x = xsup - self.size.x
  elseif xinf < self.scroll.x then
    self.scroll.to.x = math.max(0, xinf)
  end
end

function DocView:on_mouse_moved(x, y, ...)
  DocView.super.on_mouse_moved(self, x, y, ...)

  if self.hovered_scrollbar_track or self.dragging_scrollbar then
    self.cursor = "arrow"
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
        self.doc:set_selections(i - l1 + 1, i, math.min(c1, #self.doc.lines[i]), i, math.min(c2, #self.doc.lines[i]))
      end
    else
      if snap_type then
        l1, c1, l2, c2 = self:mouse_selection(self.doc, snap_type, l1, c1, l2, c2)
      end
      self.doc:set_selection(l1, c1, l2, c2)
    end
  end
end


function DocView:mouse_selection(doc, snap_type, line1, col1, line2, col2)
  local swap = line2 < line1 or line2 == line1 and col2 <= col1
  if swap then
    line1, col1, line2, col2 = line2, col2, line1, col1
  end
  if snap_type == "word" then
    line1, col1 = translate.start_of_word(doc, line1, col1)
    line2, col2 = translate.end_of_word(doc, line2, col2)
  elseif snap_type == "lines" then
    col1, col2 = 1, math.huge
  end
  if swap then
    return line2, col2, line1, col1
  end
  return line1, col1, line2, col2
end


function DocView:on_mouse_released(...)
  DocView.super.on_mouse_released(self, ...)
  self.mouse_selecting = nil
end


function DocView:on_text_input(text)
  self.doc:text_input(text)
end


function DocView:update()
  -- scroll to make caret visible and reset blink timer if it moved
  local line1, col1, line2, col2 = self.doc:get_selection()
  if (line1 ~= self.last_line1 or col1 ~= self.last_col1 or
      line2 ~= self.last_line2 or col2 ~= self.last_col2) and self.size.x > 0 then
    if core.active_view == self then
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

  DocView.super.update(self)
end


function DocView:draw_line_highlight(x, y)
  local lh = self:get_line_height()
  renderer.draw_rect(x, y, self.size.x, lh, style.line_highlight)
end


function DocView:draw_line_text(line, x, y)
  local default_font = self:get_font()
  local tx, ty = x, y + self:get_line_text_y_offset()
  for _, type, text in self.doc.highlighter:each_token(line) do
    local color = style.syntax[type]
    local font = style.syntax_fonts[type] or default_font
    tx = renderer.draw_text(font, text, tx, ty, color)
  end
  return self:get_line_height()
end

function DocView:draw_caret(x, y)
    local lh = self:get_line_height()
    renderer.draw_rect(x, y, style.caret_width, lh, style.caret)
end

function DocView:draw_line_body(line, x, y)
  -- draw highlight if any selection ends on this line
  local draw_highlight = false
  local hcl = config.highlight_current_line
  if hcl ~= false then
    for lidx, line1, col1, line2, col2 in self.doc:get_selections(false) do
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
  for lidx, line1, col1, line2, col2 in self.doc:get_selections(true) do
    if line >= line1 and line <= line2 then
      local text = self.doc.lines[line]
      if line1 ~= line then col1 = 1 end
      if line2 ~= line then col2 = #text + 1 end
      local x1 = x + self:get_col_x_offset(line, col1)
      local x2 = x + self:get_col_x_offset(line, col2)
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
  for _, line1, _, line2 in self.doc:get_selections(true) do
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


function DocView:draw_overlay()
  if core.active_view == self then
    local minline, maxline = self:get_visible_line_range()
    -- draw caret if it overlaps this line
    local T = config.blink_period
    for _, line, col in self.doc:get_selections() do
      if line >= minline and line <= maxline
      and system.window_has_focus() then
        if config.disable_blink
        or (core.blink_timer - core.blink_start) % T < T / 2 then
          self:draw_caret(self:get_line_screen_position(line, col))
        end
      end
    end
  end
end

function DocView:draw()
  self:draw_background(style.background)
  local _, indent_size = self.doc:get_indent_info()
  self:get_font():set_tab_size(indent_size)

  local minline, maxline = self:get_visible_line_range()
  local lh = self:get_line_height()

  local x, y = self:get_line_screen_position(minline)
  local gw, gpad = self:get_gutter_width()
  for i = minline, maxline do
    y = y + (self:draw_line_gutter(i, self.position.x, y, gpad and gw - gpad or gw) or lh)
  end

  local pos = self.position
  x, y = self:get_line_screen_position(minline)
  -- the clip below ensure we don't write on the gutter region. On the
  -- right side it is redundant with the Node's clip.
  core.push_clip_rect(pos.x + gw, pos.y, self.size.x - gw, self.size.y)
  for i = minline, maxline do
    y = y + (self:draw_line_body(i, x, y) or lh)
  end
  self:draw_overlay()
  core.pop_clip_rect()

  self:draw_scrollbar()
end


return DocView
