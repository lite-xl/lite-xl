-- mod-version:2 -- lite-xl 2.0

local style = require "core.style"
local DocView = require "core.docview"
local common = require "core.common"

local draw_line_text = DocView.draw_line_text

function DocView:draw_line_text(idx, x, y)
  local font = (self:get_font() or style.syntax_fonts["comment"])
  local color = style.syntax.comment
  local ty, tx = y + self:get_line_text_y_offset()
  local text, offset, s, e = self.doc.lines[idx], 1
  while true do
    s, e = text:find(" +", offset)
    if not s then break end
    tx = self:get_col_x_offset(idx, s) + x
    renderer.draw_text(font, string.rep("·", e - s + 1), tx, ty, color)
    offset = e + 1
  end
  offset = 1
  while true do
    s, e = text:find("\t", offset)
    if not s then break end
    tx = self:get_col_x_offset(idx, s) + x
    renderer.draw_text(font, "»", tx, ty, color)
    offset = e + 1
  end
  draw_line_text(self, idx, x, y)
end


