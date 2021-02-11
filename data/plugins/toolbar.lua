local core = require "core"
local common = require "core.common"
local command = require "core.command"
-- local config = require "core.config"
local style = require "core.style"
-- local DocView = require "core.docview"
local View = require "core.view"


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
  self.size.y = style.icon_font:get_height() + style.padding.y * 2

  if system.get_time() < self.message_timeout then
    self.scroll.to.y = self.size.y
  else
    self.scroll.to.y = 0
  end

  ToolbarView.super.update(self)
end

