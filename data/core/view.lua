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

-- Returns `y, x` for compatibility
function View:get_scrollable_size()
  return math.huge, 0 -- TODO: invert y and x
end


function View:get_scrollbar_rect() -- TODO: make plugins use `View:get_scrollbars_rect`
  local rect = self:get_get_scrollbars_rect()
  return rect.x, rect.y, rect.w, rect.h
end

function View:get_scrollbars_rect()
  local v_sizes = { x = 0, y = 0, w = 0, h = 0 }
  local h_sizes = { x = 0, y = 0, w = 0, h = 0 }
  local v_sz, h_sz = self:get_scrollable_size()
  h_sz = h_sz or 0 -- FIXME: not every subclass returns the second value

  if v_sz > self.size.y and v_sz ~= math.huge then
    local h = math.max(20, self.size.y * self.size.y / v_sz)
    v_sizes.x = self.position.x + self.size.x - style.scrollbar_size
    v_sizes.y = self.position.y + self.scroll.y * (self.size.y - h) / (v_sz - self.size.y)
    v_sizes.w = style.scrollbar_size
    v_sizes.h = h
  end

  if h_sz > self.size.x and h_sz ~= math.huge then
    local w = math.max(20, self.size.x * self.size.x / h_sz)
    h_sizes.x = self.position.x + self.scroll.x * (self.size.x - w) / (h_sz - self.size.x)
    h_sizes.y = self.position.y + self.size.y - style.scrollbar_size
    h_sizes.w = w
    h_sizes.h = style.scrollbar_size
  end

  return v_sizes, h_sizes
end


function View:scrollbar_overlaps_point(x, y)
  local v, h = self:get_scrollbars_rect()
  local v_overlap = x >= v.x - v.w * 3 and x < v.x + v.w and y >= v.y and y < v.y + v.h
  local h_overlap = x >= h.x and x < h.x + h.w and y >= h.y - h.h * 3 and y <= h.y + h.h
  return v_overlap, not v_overlap and h_overlap -- precedence to vertical scrollbar
end


function View:on_mouse_pressed(button, x, y, clicks)
  self.dragging_v_scrollbar, self.dragging_h_scrollbar = self:scrollbar_overlaps_point(x, y)
  self.dragging_scrollbar = self.dragging_v_scrollbar -- TODO: make plugins use `self.dragging_v_scrollbar`
  return self.dragging_v_scrollbar or self.dragging_h_scrollbar
end


function View:on_mouse_released(button, x, y)
  self.dragging_v_scrollbar = false
  self.dragging_h_scrollbar = false
  self.dragging_scrollbar = self.dragging_v_scrollbar -- TODO: make plugins use `self.dragging_v_scrollbar`
end


function View:on_mouse_moved(x, y, dx, dy)
  if self.dragging_v_scrollbar then
    local v_sz,_ = self:get_scrollable_size()
    local delta = v_sz / self.size.y * dy
    self.scroll.to.y = self.scroll.to.y + delta
  elseif self.dragging_h_scrollbar then
    local _,h_sz = self:get_scrollable_size()
    local delta = h_sz / self.size.x * dx
    self.scroll.to.x = self.scroll.to.x + delta
  end
  self.hovered_v_scrollbar, self.hovered_h_scrollbar = self:scrollbar_overlaps_point(x, y)
  self.hovered_scrollbar = self.hovered_v_scrollbar -- TODO: make plugins use `self.hovered_v_scrollbar`
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
  local scrollsize_y, scrollsize_x = self:get_scrollable_size()
  scrollsize_x = scrollsize_x or 0 -- FIXME: not every subclass returns the second value
  local max_x = scrollsize_x - self.size.x
  local max_y = scrollsize_y - self.size.y
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
  local v, h = self:get_scrollbars_rect()
  local v_highlight = self.hovered_v_scrollbar or self.dragging_v_scrollbar
  local h_highlight = self.hovered_h_scrollbar or self.dragging_h_scrollbar
  local v_color = v_highlight and style.scrollbar2 or style.scrollbar
  local h_color = h_highlight and style.scrollbar2 or style.scrollbar
  renderer.draw_rect(v.x, v.y, v.w, v.h, v_color)
  renderer.draw_rect(h.x, h.y, h.w, h.h, h_color)
end


function View:draw()
end


return View
