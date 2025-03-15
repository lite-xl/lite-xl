local core = require "core"
local config = require "core.config"
local common = require "core.common"
local Object = require "core.object"
local Scrollbar = require "core.scrollbar"

---@class core.view.position
---@field x number
---@field y number

---@class core.view.scroll
---@field x number
---@field y number
---@field to core.view.position

---@class core.view.thumbtrack
---@field thumb number
---@field track number

---@class core.view.thumbtrackwidth
---@field thumb number
---@field track number
---@field to core.view.thumbtrack

---@class core.view.scrollbar
---@field x core.view.thumbtrack
---@field y core.view.thumbtrack
---@field w core.view.thumbtrackwidth
---@field h core.view.thumbtrack

---@alias core.view.cursor "'arrow'" | "'ibeam'" | "'sizeh'" | "'sizev'" | "'hand'"

---@alias core.view.mousebutton "'left'" | "'right'"

---@alias core.view.context "'application'" | "'session'"

---Base view.
---@class core.view : core.object
---@field context core.view.context
---@field super core.object
---@field position core.view.position
---@field size core.view.position
---@field scroll core.view.scroll
---@field cursor core.view.cursor
---@field scrollable boolean
---@field v_scrollbar core.scrollbar
---@field h_scrollbar core.scrollbar
---@field current_scale number
local View = Object:extend()

function View:__tostring() return "View" end

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
  self.v_scrollbar = Scrollbar({direction = "v", alignment = "e"})
  self.h_scrollbar = Scrollbar({direction = "h", alignment = "e"})
  self.current_scale = SCALE
end

function View:move_towards(t, k, dest, rate, name)
  if type(t) ~= "table" then
    return self:move_towards(self, t, k, dest, rate, name)
  end
  local val = t[k]
  local diff = math.abs(val - dest)
  if not config.transitions or diff < 0.5 or config.disabled_transitions[name] then
    t[k] = dest
  else
    rate = rate or 0.5
    if config.fps ~= 60 or config.animation_rate ~= 1 then
      local dt = 60 / config.fps
      rate = 1 - common.clamp(1 - rate, 1e-8, 1 - 1e-8)^(config.animation_rate * dt)
    end
    t[k] = common.lerp(val, dest, rate)
  end
  if diff > 1e-8 then
    core.redraw = true
  end
end


function View:try_close(do_close)
  do_close()
end


---@return string
function View:get_name()
  return "---"
end


---@return number
function View:get_scrollable_size()
  return math.huge
end

---@return number
function View:get_h_scrollable_size()
  return 0
end


---@param x number
---@param y number
---@return boolean
function View:scrollbar_overlaps_point(x, y)
  return not (not (self.v_scrollbar:overlaps(x, y) or self.h_scrollbar:overlaps(x, y)))
end


---@return boolean
function View:scrollbar_dragging()
  return self.v_scrollbar.dragging or self.h_scrollbar.dragging
end


---@return boolean
function View:scrollbar_hovering()
  return self.v_scrollbar.hovering.track or self.h_scrollbar.hovering.track
end


---@param button core.view.mousebutton
---@param x number
---@param y number
---@param clicks integer
---return boolean
function View:on_mouse_pressed(button, x, y, clicks)
  if not self.scrollable then return end
  local result = self.v_scrollbar:on_mouse_pressed(button, x, y, clicks)
  if result then
    if result ~= true then
      self.scroll.to.y = result * self:get_scrollable_size()
    end
    return true
  end
  result = self.h_scrollbar:on_mouse_pressed(button, x, y, clicks)
  if result then
    if result ~= true then
      self.scroll.to.x = result * self:get_h_scrollable_size()
    end
    return true
  end
end


---@param button core.view.mousebutton
---@param x number
---@param y number
function View:on_mouse_released(button, x, y)
  if not self.scrollable then return end
  self.v_scrollbar:on_mouse_released(button, x, y)
  self.h_scrollbar:on_mouse_released(button, x, y)
end


---@param x number
---@param y number
---@param dx number
---@param dy number
function View:on_mouse_moved(x, y, dx, dy)
  if not self.scrollable then return end
  local result
  if self.h_scrollbar.dragging then goto skip_v_scrollbar end
  result = self.v_scrollbar:on_mouse_moved(x, y, dx, dy)
  if result then
    if result ~= true then
      self.scroll.to.y = result * self:get_scrollable_size()
      if not config.animate_drag_scroll then
        self:clamp_scroll_position()
        self.scroll.y = self.scroll.to.y
      end
    end
    -- hide horizontal scrollbar
    self.h_scrollbar:on_mouse_left()
    return true
  end
  ::skip_v_scrollbar::
  result = self.h_scrollbar:on_mouse_moved(x, y, dx, dy)
  if result then
    if result ~= true then
      self.scroll.to.x = result * self:get_h_scrollable_size()
      if not config.animate_drag_scroll then
        self:clamp_scroll_position()
        self.scroll.x = self.scroll.to.x
      end
    end
    return true
  end
end


function View:on_mouse_left()
  if not self.scrollable then return end
  self.v_scrollbar:on_mouse_left()
  self.h_scrollbar:on_mouse_left()
end


---@param filename string
---@param x number
---@param y number
---@return boolean
function View:on_file_dropped(filename, x, y)
  return false
end


---@param text string
function View:on_text_input(text)
  -- no-op
end


function View:on_ime_text_editing(text, start, length)
  -- no-op
end


---@param y number @Vertical scroll delta; positive is "up"
---@param x number @Horizontal scroll delta; positive is "left"
---@return boolean @Capture event
function View:on_mouse_wheel(y, x)
  -- no-op
end

---Can be overriden to listen for scale change events to apply
---any neccesary changes in sizes, padding, etc...
---@param new_scale number
---@param prev_scale number
function View:on_scale_change(new_scale, prev_scale) end

function View:get_content_bounds()
  local x = self.scroll.x
  local y = self.scroll.y
  return x, y, x + self.size.x, y + self.size.y
end


---@return number x
---@return number y
function View:get_content_offset()
  local x = common.round(self.position.x - self.scroll.x)
  local y = common.round(self.position.y - self.scroll.y)
  return x, y
end


function View:clamp_scroll_position()
  local max = self:get_scrollable_size() - self.size.y
  self.scroll.to.y = common.clamp(self.scroll.to.y, 0, max)

  max = self:get_h_scrollable_size() - self.size.x
  self.scroll.to.x = common.clamp(self.scroll.to.x, 0, max)
end


function View:update_scrollbar()
  local v_scrollable = self:get_scrollable_size()
  self.v_scrollbar:set_size(self.position.x, self.position.y, self.size.x, self.size.y, v_scrollable)
  self.v_scrollbar:set_percent(self.scroll.y/v_scrollable)
  self.v_scrollbar:update()

  local h_scrollable = self:get_h_scrollable_size()
  self.h_scrollbar:set_size(self.position.x, self.position.y, self.size.x, self.size.y, h_scrollable)
  self.h_scrollbar:set_percent(self.scroll.x/h_scrollable)
  self.h_scrollbar:update()
end


function View:update()
  if self.current_scale ~= SCALE then
    self:on_scale_change(SCALE, self.current_scale)
    self.current_scale = SCALE
  end

  self:clamp_scroll_position()
  self:move_towards(self.scroll, "x", self.scroll.to.x, 0.3, "scroll")
  self:move_towards(self.scroll, "y", self.scroll.to.y, 0.3, "scroll")
  if not self.scrollable then return end
  self:update_scrollbar()
end


---@param color renderer.color
function View:draw_background(color)
  local x, y = self.position.x, self.position.y
  local w, h = self.size.x, self.size.y
  renderer.draw_rect(x, y, w, h, color)
end


function View:draw_scrollbar()
  self.v_scrollbar:draw()
  self.h_scrollbar:draw()
end


function View:draw()
end

return View
