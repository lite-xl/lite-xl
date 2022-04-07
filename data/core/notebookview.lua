local core = require "core"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local keymap = require "core.keymap"
local translate = require "core.doc.translate"
local View = require "core.view"
local Doc = require "core.doc"
local DocView = require "core.docview"


local NotebookView = View:extend()

function NotebookView:new()
  NotebookView.super.new(self)
  local doc = Doc()
  doc:set_syntax(".lua")
  local view = DocView(doc)
  view.scroll_tight = true
  self.parts = { view }
  self.active_view = self.parts[1]
  self.current = 1
end


function NotebookView:get_name()
  return "-- Notebook"
end


function NotebookView:update()
  if core.active_view == self then
    core.set_active_view(self.active_view)
  end
  for _, view in ipairs(self.parts) do
    view:update()
  end
  NotebookView.super.update(self)
end


function NotebookView:get_part_height(view)
  return view:get_line_height() * (#view.doc.lines) + style.padding.y * 2
end


function NotebookView:get_part_drawing_rect(idx)
  local x, y = self:get_content_offset()
  local margin_h, margin_v = 50, 50
  x, y = x + margin_h, y + margin_v
  local inner_h, inner_v = 5, 5
  local w = self.size.x - 2 * margin_h
  for i, view in ipairs(self.parts) do
    local h = self:get_part_height(view) + 2 * inner_v
    if i == idx then return x, y, w, h end
    y = y + h + margin_v
  end
end


function NotebookView:get_scrollable_size()
  local x, y = 0, 0
  local margin_h, margin_v = 50, 50
  x, y = x + margin_h, y + margin_v
  local inner_h, inner_v = 5, 5
  local w = self.size.x - 2 * margin_h
  for i, view in ipairs(self.parts) do
    local h = self:get_part_height(view) + 2 * inner_v
    y = y + h + margin_v
  end
  return y
end


function NotebookView:on_mouse_pressed(button, x, y, clicks)
  local caught = NotebookView.super.on_mouse_pressed(self, button, x, y, clicks)
  if caught then return end
  for i, view in ipairs(self.parts) do
    local x_part, y_part, w, h = self:get_part_drawing_rect(i)
    if x >= x_part and x <= x_part + w and y >= y_part and y <= y_part + h then
      if view ~= core.active_view then
        core.set_active_view(view)
      end
      view:on_mouse_pressed(button, x, y, clicks)
      return true
    end
  end
end


function View:on_text_input(text)
  if core.active_view == self.parts[self.current] then
    view:on_text_input(text)
  end
end


function NotebookView:draw()
  local x, y = self:get_content_offset()

  self:draw_background(style.background)

  local margin_h, margin_v = 50, 50
  x, y = x + margin_h, y + margin_v
  local inner_h, inner_v = 5, 5
  local w = self.size.x - 2 * margin_h
  for _, view in ipairs(self.parts) do
    local h = self:get_part_height(view) + 2 * inner_v
    renderer.draw_rect(margin_h, y, w, h, style.line_highlight)
    view.size.x, view.size.y = w, h
    view.position.x, view.position.y = x + inner_h, y + inner_v
    view:draw()
    y = y + h + margin_v
  end
  -- self:draw_overlay()
  self:draw_scrollbar()
end

return NotebookView
