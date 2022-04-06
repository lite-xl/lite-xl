local core = require "core"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local keymap = require "core.keymap"
local translate = require "core.doc.translate"
local View = require "core.view"


local NotebookView = View:extend()

function NotebookView:new()
  NotebookView.super.new(self)
  self.parts = { InputTextView:new() }
  self.active_index = 1
end


-- FIXME: to be adapted to NotebookView, copier from DocView
function NotebookView:draw_overlay()
  if core.active_view == self then
    local minline, maxline = self:get_visible_line_range()
    -- draw caret if it overlaps this line
    local T = config.blink_period
    for _, line, col in self.doc:get_selections() do
      if line >= minline and line <= maxline
      and system.window_has_focus() then
        if config.disable_blink
        or (core.blink_timer - core.blink_start) % T < T / 2 then
          local x, y = self:get_line_screen_position(line)
          self:draw_caret(x + self:get_col_x_offset(line, col), y)
        end
      end
    end
  end
end


function NotebookView:draw()
  -- local x, y = self:get_content_offset()

  self:draw_background(style.background)

  local margin_h, margin_v = 50, 50
  local y = margin_v
  local inner_h, inner_v = 5, 5
  local w = self.size.x - 2 * margin_h
  for _, view in ipairs(self.parts) do
    local h = view:get_scrollable_size() + 2 * inner_v
    renderer.draw_rect(margin_h, y, w, h, style.line_highlight)
    view.size.x, view.size.y = w, h
    view.position.x, view.position.y = margin_h + inner_h, y + margin_v + inner_v
    view:draw()
  end
  self:draw_overlay()
  self:draw_scrollbar()
end

