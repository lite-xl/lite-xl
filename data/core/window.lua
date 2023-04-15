local Object = require "core.object"

local Window = Object:extend()

function Window:new(options)
  local dm = system.get_current_display_mode(0)

  local x = options.x or system.WINDOWPOS_UNDEFINED
  local y = options.y or system.WINDOWPOS_UNDEFINED
  local w = options.w or dm.w * 0.8
  local h = options.h or dm.h * 0.8
  local flags = options.flags or system.WINDOW_RESIZABLE | system.WINDOW_ALLOW_HIGHDPI | system.WINDOW_HIDDEN

  self.handle = system.create_window(x, y, w, h, flags)
end

function Window:get_window_size()
  return system.get_window_size(self.handle)
end

function Window:get_window_mode()
  return system.get_window_mode(self.handle)
end

function Window:destroy()
  return system.destroy_window(self.handle)
end


return Window
