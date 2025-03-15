-- mod-version:3
local core = require "core"
local common = require "core.common"
local command = require "core.command"
local style = require "core.style"
local keymap = require "core.keymap"
local View = require "core.view"

local ToolbarView = View:extend()

function ToolbarView:__tostring() return "ToolbarView" end

function ToolbarView:new()
  ToolbarView.super.new(self)
  self.visible = true
  self.init_size = true
  self.tooltip = false
  self.toolbar_font = style.icon_big_font
  self.toolbar_commands = {
    {symbol = "f", command = "core:new-doc"},
    {symbol = "D", command = "core:open-file"},
    {symbol = "S", command = "doc:save"},
    {symbol = "L", command = "core:find-file"},
    {symbol = "B", command = "core:find-command"},
    {symbol = "P", command = "core:open-user-module"},
  }
end


function ToolbarView:update()
  local dest_size = self.visible and (self.toolbar_font:get_height() + style.padding.y * 2) or 0
  if self.init_size then
    self.size.y = dest_size
    self.init_size = nil
  else
    self:move_towards(self.size, "y", dest_size)
  end
  ToolbarView.super.update(self)
end


function ToolbarView:toggle_visible()
  self.visible = not self.visible
  if self.tooltip then
    core.status_view:remove_tooltip()
    self.tooltip = false
  end
  self.hovered_item = nil
end

function ToolbarView:get_icon_width()
  local max_width = 0
  for i,v in ipairs(self.toolbar_commands) do max_width = math.max(max_width, self.toolbar_font:get_width(v.symbol)) end
  return max_width
end

function ToolbarView:each_item()
  local icon_h, icon_w = self.toolbar_font:get_height(), self:get_icon_width()
  local toolbar_spacing = icon_w / 2
  local ox, oy = self:get_content_offset()
  local index = 0
  local iter = function()
    index = index + 1
    if index <= #self.toolbar_commands then
      local dx = style.padding.x + (icon_w + toolbar_spacing) * (index - 1)
      local dy = style.padding.y
      if dx + icon_w > self.size.x then return end
      return self.toolbar_commands[index], ox + dx, oy + dy, icon_w, icon_h
    end
  end
  return iter
end


function ToolbarView:get_min_width()
  local icon_w = self:get_icon_width()
  local space = icon_w / 2
  return 2 * style.padding.x + (icon_w + space) * #self.toolbar_commands - space
end


function ToolbarView:draw()
  if not self.visible then return end
  self:draw_background(style.background2)

  for item, x, y, w, h in self:each_item() do
    local color = item == self.hovered_item and command.is_valid(item.command) and style.text or style.dim
    common.draw_text(self.toolbar_font, color, item.symbol, nil, x, y, 0, h)
  end
end


function ToolbarView:on_mouse_pressed(button, x, y, clicks)
  if not self.visible then return end
  local caught = ToolbarView.super.on_mouse_pressed(self, button, x, y, clicks)
  if caught then return caught end
  core.set_active_view(core.last_active_view)
  if self.hovered_item and command.is_valid(self.hovered_item.command) then
    command.perform(self.hovered_item.command)
  end
  return true
end


function ToolbarView:on_mouse_moved(px, py, ...)
  if not self.visible then return end
  ToolbarView.super.on_mouse_moved(self, px, py, ...)
  self.hovered_item = nil
  local x_min, x_max, y_min, y_max = self.size.x, 0, self.size.y, 0
  for item, x, y, w, h in self:each_item() do
    x_min, x_max = math.min(x, x_min), math.max(x + w, x_max)
    y_min, y_max = y, y + h
    if px > x and py > y and px <= x + w and py <= y + h then
      self.hovered_item = item
      local binding = keymap.get_binding(item.command)
      local name = command.prettify_name(item.command)
      core.status_view:show_tooltip(binding and { name, style.dim, "  ", binding } or { name })
      self.tooltip = true
      return
    end
  end
  if self.tooltip and not (px > x_min and px <= x_max and py > y_min and py <= y_max) then
    core.status_view:remove_tooltip()
    self.tooltip = false
  end
end

-- The toolbarview pane is not plugged here but it is added in the
-- treeview plugin.

return ToolbarView
