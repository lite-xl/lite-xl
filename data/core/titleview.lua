local core = require "core"
local style = require "core.style"
local StatusView = require "core.statusview"


local TitleView = StatusView:extend()

TitleView.separator = " "

function TitleView:new()
  TitleView.super.new(self)
end


function TitleView:on_mouse_pressed()
  core.set_active_view(core.last_active_view)
end


function TitleView:get_items()
  local title = core.compose_window_title(core.window_title)
  return {
    style.text, style.icon_font, "g ", style.font, title,
  }, {
    style.text, style.icon_font, "_", TitleView.separator, "w", TitleView.separator, "W",
  }
end


return TitleView
