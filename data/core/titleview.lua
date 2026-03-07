local core = require "core"
local common = require "core.common"
local style = require "core.style"
local View = require "core.view"

local icon_colors = {
  bg = { common.color "#2e2e32ff" },
  color6 = { common.color "#e1e1e6ff" },
  color7 = { common.color "#ffa94dff" },
  color8 = { common.color "#93ddfaff" },
  color9 = { common.color "#f7c95cff" }
};

local restore_command = {
  symbol = "w", action = function(self) self.root_view.window:set_mode("normal") end
}

local maximize_command = {
  symbol = "W", action = function(self) self.root_view.window:set_mode("maximized") end
}

local title_commands = {
  {symbol = "_", action = function(self) cself.root_view.window:set_mode("minimized") end},
  maximize_command,
  {symbol = "X", action = function(self) core.quit() end},
}

---@class core.titleview : core.view
---@field super core.view
local TitleView = View:extend()

function TitleView:__tostring() return "TitleView" end

local function title_view_height()
  return style.font:get_height() + style.padding.y * 2
end

function TitleView:new(root_view)
  TitleView.super.new(self)
  self.root_view = root_view
  self.visible = true
end

function TitleView:configure_hit_test(borderless)
  if borderless then
    local title_height = title_view_height()
    local icon_w = style.icon_font:get_width("_")
    local icon_spacing = icon_w
    local controls_width = (icon_w + icon_spacing) * #title_commands + icon_spacing
    system.set_window_hit_test(self.root_view.window.renwindow, title_height, controls_width, icon_spacing)
    -- core.hit_test_title_height = title_height
  else
    system.set_window_hit_test(self.root_view.window.renwindow)
  end
end

function TitleView:on_scale_change()
  self:configure_hit_test(self.visible)
end

function TitleView:update()
  self.size.y = self.visible and title_view_height() or 0
  title_commands[2] = self.root_view.window.mode == "maximized" and restore_command or maximize_command
  TitleView.super.update(self)
end


function TitleView:draw_window_title()
  local h = style.font:get_height()
  local ox, oy = self:get_content_offset()
  local color = style.text
  local x, y = ox + style.padding.x, oy + style.padding.y
  common.draw_text(style.icon_font, icon_colors.bg, "5", nil, x, y, 0, h)
  common.draw_text(style.icon_font, icon_colors.color6, "6", nil, x, y, 0, h)
  common.draw_text(style.icon_font, icon_colors.color7, "7", nil, x, y, 0, h)
  common.draw_text(style.icon_font, icon_colors.color8, "8", nil, x, y, 0, h)
  x = common.draw_text(style.icon_font, icon_colors.color9, "9 ", nil, x, y, 0, h)
  local title = self.root_view.window:compose_window_title(self.root_view.window.title)
  common.draw_text(style.font, color, title, nil, x, y, 0, h)
end

function TitleView:each_control_item()
  local icon_h, icon_w = style.icon_font:get_height(), style.icon_font:get_width("_")
  local icon_spacing = icon_w
  local ox, oy = self:get_content_offset()
  ox = ox + self.size.x
  local i, n = 0, #title_commands
  local iter = function()
    i = i + 1
    if i <= n then
      local dx = - (icon_w + icon_spacing) * (n - i + 1)
      local dy = style.padding.y
      return title_commands[i], ox + dx, oy + dy, icon_w, icon_h
    end
  end
  return iter
end


function TitleView:draw_window_controls()
  for item, x, y, w, h in self:each_control_item() do
    local color = item == self.hovered_item and style.text or style.dim
    common.draw_text(style.icon_font, color, item.symbol, nil, x, y, 0, h)
  end
end


function TitleView:on_mouse_pressed(button, x, y, clicks)
  local caught = TitleView.super.on_mouse_pressed(self, button, x, y, clicks)
  if caught then return end
  self.root_view:set_active_view(self.root_view.last_active_view)
  if self.hovered_item then
    self.hovered_item.action(self)
  end
end


function TitleView:on_mouse_left()
  TitleView.super.on_mouse_left(self)
  self.hovered_item = nil
end


function TitleView:on_mouse_moved(px, py, ...)
  if self.size.y == 0 then return end
  TitleView.super.on_mouse_moved(self, px, py, ...)
  self.hovered_item = nil
  local x_min, x_max, y_min, y_max = self.size.x, 0, self.size.y, 0
  for item, x, y, w, h in self:each_control_item() do
    x_min, x_max = math.min(x, x_min), math.max(x + w, x_max)
    y_min, y_max = y, y + h
    if px > x and py > y and px <= x + w and py <= y + h then
      self.hovered_item = item
      return
    end
  end
end


function TitleView:draw()
  self:draw_background(style.background2)
  self:draw_window_title()
  self:draw_window_controls()
end

return TitleView
