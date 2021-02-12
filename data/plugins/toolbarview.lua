local core = require "core"
local common = require "core.common"
local command = require "core.command"
local style = require "core.style"
local View = require "core.view"

local icon_h, icon_w = style.icon_big_font:get_height(), style.icon_big_font:get_width("D")

local spacing = {
  margin = {x = icon_w / 2, y = icon_h / 3},
  padding = {x = icon_w / 2, y = 0},
}

local ToolbarView = View:extend()

local toolbar_commands = {
  {"f", "core:open-file"},
  {"S", "doc:save"},
  {"L", "core:find-file"},
}

function ToolbarView:new()
  ToolbarView.super.new(self)
end

function ToolbarView:update()
  self.size.x = (icon_w + spacing.padding.x) * #toolbar_commands - spacing.padding.x + 2 * spacing.margin.x
  self.size.y = style.icon_big_font:get_height() + style.padding.y * 2
  ToolbarView.super.update(self)
end

function ToolbarView:draw()
  self:draw_background(style.background2)

  local x, y = self:get_content_offset()
  x = x + spacing.margin.x
  for i, item in ipairs(toolbar_commands) do
    x = common.draw_text(style.icon_big_font, style.text, item[1], nil, x, y, 0, self.size.y)
    x = x + spacing.padding.x
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
