local core = require "core"
local common = require "core.common"
local command = require "core.command"
local style = require "core.style"
local View = require "core.view"

local icon_h, icon_w = style.icon_big_font:get_height(), style.icon_big_font:get_width("D")

local spacing = {
  -- FIXME: simplifies as y is not really needed.
  margin = {x = icon_w / 2},
  padding = {x = icon_w / 4},
}

local ToolbarView = View:extend()

local toolbar_commands = {
  {symbol = "f", command = "core:open-file"},
  {symbol = "S", command = "doc:save"},
  {symbol = "L", command = "core:find-file"},
}

function ToolbarView:new()
  ToolbarView.super.new(self)
end

function ToolbarView:update()
  -- FIXME: remove size.x variable if not really needed.
  -- self.size.x = (icon_w + spacing.padding.x) * #toolbar_commands - spacing.padding.x + 2 * spacing.margin.x
  self.size.y = style.icon_big_font:get_height() + style.padding.y * 2
  ToolbarView.super.update(self)
end

function ToolbarView:each_item()
  local ox, oy = self:get_content_offset()
  local index = 0
  local iter = function()
    index = index + 1
    if index <= #toolbar_commands then
      local dx = spacing.margin.x + (icon_w + spacing.padding.x) * (index - 1)
      return toolbar_commands[index], ox + dx, oy, icon_w, icon_h
    end
  end
  return iter
end

function ToolbarView:draw()
  self:draw_background(style.background2)

  for item, x, y in self:each_item() do
    local color = item == self.hovered_item and style.text or style.dim
    common.draw_text(style.icon_big_font, color, item.symbol, nil, x, y, 0, self.size.y)
  end
end

function ToolbarView:on_mouse_pressed(button, x, y, clicks)
  local caught = ToolbarView.super.on_mouse_pressed(self, button, x, y, clicks)
  if caught then return end
  core.set_active_view(core.last_active_view)
  if self.hovered_item then
    command.perform(self.hovered_item.command)
  end
end


function ToolbarView:on_mouse_moved(px, py, ...)
  ToolbarView.super.on_mouse_moved(self, px, py, ...)
  self.hovered_item = nil
  for item, x, y, w, h in self:each_item() do
    if px > x and py > y and px <= x + w and py <= y + h then
      self.hovered_item = item
      break
    end
  end
end

-- init
if false then
  local view = ToolbarView()
  local node = core.root_view:get_active_node()
  node:split("up", view, true)
end

-- register commands and keymap
--[[command.add(nil, {
  ["toolbar:toggle"] = function()
    view.visible = not view.visible
  end,
})

keymap.add { ["ctrl+\\"] = "treeview:toggle" }
]]

return ToolbarView
