-- mod-version:3 -- lite-xl 2.1

local style = require "core.style"
local DocView = require "core.docview"
local common = require "core.common"

local draw_line_text = DocView.draw_line_text

function DocView:draw_line_text(idx, x, y)
  local font = (self:get_font() or style.syntax_fonts["whitespace"] or style.syntax_fonts["comment"])
  local color = style.syntax.whitespace or style.syntax.comment
  local ty = y + self:get_line_text_y_offset()
  local tx
  local text, offset, s, e = self.doc.lines[idx], 1
  local x1, _, x2, _ = self:get_content_bounds()
  local _offset = self:get_x_offset_col(idx, x1)
  offset = _offset
  while true do
    s, e = text:find(" +", offset)
    if not s then break end
    tx = self:get_col_x_offset(idx, s) + x
    renderer.draw_text(font, string.rep("·", e - s + 1), tx, ty, color)
    if tx > x + x2 then break end
    offset = e + 1
  end
  offset = _offset
  while true do
    s, e = text:find("\t", offset)
    if not s then break end
    tx = self:get_col_x_offset(idx, s) + x
    renderer.draw_text(font, "»", tx, ty, color)
    if tx > x + x2 then break end
    offset = e + 1
  end
  draw_line_text(self, idx, x, y)
end
