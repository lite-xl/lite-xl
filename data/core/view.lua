local core = require "core"
local config = require "core.config"
local style = require "core.style"
local common = require "core.common"
local Object = require "core.object"
local keymap = require "core.keymap"


local View = Object:extend()

-- context can be "application" or "session". The instance of objects
-- with context "session" will be closed when a project session is
-- terminated. The context "application" is for functional UI elements.
View.context = "application"

function View:new()
  self.position = { x = 0, y = 0 }
  self.size = { x = 0, y = 0 }
  self.scroll = { x = 0, y = 0, to = { x = 0, y = 0 } }
  self.cursor = "arrow"
  self.scrollable = false
end

function View:move_towards(t, k, dest, rate)
  if type(t) ~= "table" then
    return self:move_towards(self, t, k, dest, rate)
  end
  local val = t[k]
  if not config.transitions or math.abs(val - dest) < 0.5 then
    t[k] = dest
  else
    rate = rate or 0.5
    if config.fps ~= 60 or config.animation_rate ~= 1 then
      local dt = 60 / config.fps
      rate = 1 - common.clamp(1 - rate, 1e-8, 1 - 1e-8)^(config.animation_rate * dt)
    end
    t[k] = common.lerp(val, dest, rate)
  end
  if val ~= dest then
    core.redraw = true
  end
end


function View:try_close(do_close)
  do_close()
end


function View:get_name()
  return "---"
end


function View:get_scrollable_size()
  return math.huge
end


function View:get_h_scrollable_size()
  return 0
end


function View:get_scrollbar_rect()
  local sz = self:get_scrollable_size()
  if sz <= self.size.y or sz == math.huge then
    return 0, 0, 0, 0
  end
  local h = math.max(20, self.size.y * self.size.y / sz)
  return
    self.position.x + self.size.x - style.scrollbar_size,
    self.position.y + self.scroll.y * (self.size.y - h) / (sz - self.size.y),
    style.scrollbar_size,
    h
end


function View:get_h_scrollbar_rect()
  local sz = self:get_h_scrollable_size()
  if sz <= self.size.x or sz == math.huge then
    return 0, 0, 0, 0
  end
  local w = math.max(20, self.size.x * self.size.x / sz)
  return
    self.position.x + self.scroll.x * (self.size.x - w) / (sz - self.size.x),
    self.position.y + self.size.y - style.scrollbar_size,
    w,
    style.scrollbar_size
end


function View:scrollbar_overlaps_point(x, y)
  local sx, sy, sw, sh = self:get_scrollbar_rect()
  return x >= sx - sw * 3 and x < sx + sw and y >= sy and y <= sy + sh
end


function View:h_scrollbar_overlaps_point(x, y)
  local sx, sy, sw, sh = self:get_h_scrollbar_rect()
  return x >= sx and x <= sx + sw and y > sy - sh * 3 and y <= sy + sh
end


function View:on_mouse_pressed(button, x, y, clicks)
  if self:scrollbar_overlaps_point(x, y) then
    self.dragging_scrollbar = true
    return true
  elseif self:h_scrollbar_overlaps_point(x, y) then
    self.dragging_h_scrollbar = true
    return true
  end
end


function View:on_mouse_released(button, x, y)
  self.dragging_scrollbar = false
  self.dragging_h_scrollbar = false
end


function View:on_mouse_moved(x, y, dx, dy)
  if self.dragging_scrollbar then
    local delta = self:get_scrollable_size() / self.size.y * dy
    self.scroll.to.y = self.scroll.to.y + delta
  elseif self.dragging_h_scrollbar then
    local delta = self:get_h_scrollable_size() / self.size.x * dx
    self.scroll.to.x = self.scroll.to.x + delta
  end
  self.hovered_scrollbar = self:scrollbar_overlaps_point(x, y)
  self.hovered_h_scrollbar = self:h_scrollbar_overlaps_point(x, y)
end


function View:on_text_input(text)
  -- no-op
end


function View:on_mouse_wheel(quant)
  if self.scrollable then
    if keymap.modkeys["shift"] then
      self.scroll.to.x = self.scroll.to.x + quant * -config.mouse_wheel_scroll
    else
      self.scroll.to.y = self.scroll.to.y + quant * -config.mouse_wheel_scroll
    end
  end
end


function View:get_content_bounds()
  local x = self.scroll.x
  local y = self.scroll.y
  return x, y, x + self.size.x, y + self.size.y
end


function View:get_content_offset()
  local x = common.round(self.position.x - self.scroll.x)
  local y = common.round(self.position.y - self.scroll.y)
  return x, y
end


function View:clamp_scroll_position()
  local max_x = self:get_h_scrollable_size() - self.size.x
  local max_y = self:get_scrollable_size() - self.size.y
  self.scroll.to.x = common.clamp(self.scroll.to.x, 0, max_x)
  self.scroll.to.y = common.clamp(self.scroll.to.y, 0, max_y)
end


function View:update()
  self:clamp_scroll_position()
  self:move_towards(self.scroll, "x", self.scroll.to.x, 0.3)
  self:move_towards(self.scroll, "y", self.scroll.to.y, 0.3)
end


function View:draw_background(color)
  local x, y = self.position.x, self.position.y
  local w, h = self.size.x, self.size.y
  renderer.draw_rect(x, y, w + x % 1, h + y % 1, color)
end


function View:draw_scrollbar()
  local x, y, w, h = self:get_scrollbar_rect()
  local highlight = self.hovered_scrollbar or self.dragging_scrollbar
  local color = highlight and style.scrollbar2 or style.scrollbar
  renderer.draw_rect(x, y, w, h, color)
end


function View:draw_h_scrollbar()
  local x, y, w, h = self:get_h_scrollbar_rect()
  local highlight = self.hovered_h_scrollbar and not self.hovered_scrollbar
                    or self.dragging_h_scrollbar
  local color = highlight and style.scrollbar2 or style.scrollbar
  renderer.draw_rect(x, y, w, h, color)
end


function View:draw()
end


return View
