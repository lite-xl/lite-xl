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

function TitleView:on_mouse_moved(px, py, ...)
end


function TitleView:update()
  TitleView.super.update(self)
  local title_height = self.size.y
  if core.window_borderless and title_height ~= core.hit_test_title_height then
    local resize_border = title_height / 2
    system.set_window_hit_test(title_height, resize_border)
    core.hit_test_title_height = title_height
  end
end


function TitleView:get_items()
  local title = core.compose_window_title(core.window_title)
  return {
    style.text, style.icon_font, "M ", style.font, title,
  }, {
    style.text, style.icon_font, "_", TitleView.separator, "w", TitleView.separator, "W",
  }
end


return TitleView
