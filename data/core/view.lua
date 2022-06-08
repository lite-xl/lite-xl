local core = require "core"
local config = require "core.config"
local style = require "core.style"
local common = require "core.common"
local Object = require "core.object"

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

---@class core.view.increment
---@field value number
---@field to number

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
---@field scrollbar core.view.scrollbar
---@field scrollbar_alpha core.view.increment
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
  self.scrollbar = {
    x = { thumb = 0, track = 0 },
    y = { thumb = 0, track = 0 },
    w = { thumb = 0, track = 0, to = { thumb = 0, track = 0 } },
    h = { thumb = 0, track = 0 },
  }
  self.scrollbar_alpha = { value = 0, to = 0 }
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


---@return number x
---@return number y
---@return number width
---@return number height
function View:get_scrollbar_track_rect()
  local sz = self:get_scrollable_size()
  if sz <= self.size.y or sz == math.huge then
    return 0, 0, 0, 0
  end
  local width = style.scrollbar_size
  if self.hovered_scrollbar_track or self.dragging_scrollbar then
    width = style.expanded_scrollbar_size
  end
  return
    self.position.x + self.size.x - width,
    self.position.y,
    width,
    self.size.y
end


---@return number x
---@return number y
---@return number width
---@return number height
function View:get_scrollbar_rect()
  local sz = self:get_scrollable_size()
  if sz <= self.size.y or sz == math.huge then
    return 0, 0, 0, 0
  end
  local h = math.max(20, self.size.y * self.size.y / sz)
  local width = style.scrollbar_size
  if self.hovered_scrollbar_track or self.dragging_scrollbar then
    width = style.expanded_scrollbar_size
  end
  return
    self.position.x + self.size.x - width,
    self.position.y + self.scroll.y * (self.size.y - h) / (sz - self.size.y),
    width,
    h
end


---@param x number
---@param y number
---@return boolean
function View:scrollbar_overlaps_point(x, y)
  local sx, sy, sw, sh = self:get_scrollbar_rect()
  return x >= sx - style.scrollbar_size * 3 and x < sx + sw and y > sy and y <= sy + sh
end

---@param x number
---@param y number
---@return boolean
function View:scrollbar_track_overlaps_point(x, y)
  local sx, sy, sw, sh = self:get_scrollbar_track_rect()
  return x >= sx - style.scrollbar_size * 3 and x < sx + sw and y > sy and y <= sy + sh
end


---@param button core.view.mousebutton
---@param x number
---@param y number
---@param clicks integer
---return boolean
function View:on_mouse_pressed(button, x, y, clicks)
  if self:scrollbar_track_overlaps_point(x, y) then
    if self:scrollbar_overlaps_point(x, y) then
      self.dragging_scrollbar = true
    else
      local _, _, _, sh = self:get_scrollbar_rect()
      local ly = (y - self.position.y) - sh / 2
      local pct = common.clamp(ly / self.size.y, 0, 100)
      self.scroll.to.y = self:get_scrollable_size() * pct
    end
    return true
  end
end


---@param button core.view.mousebutton
---@param x number
---@param y number
function View:on_mouse_released(button, x, y)
  self.dragging_scrollbar = false
end


---@param x number
---@param y number
---@param dx number
---@param dy number
function View:on_mouse_moved(x, y, dx, dy)
  if self.dragging_scrollbar then
    local delta = self:get_scrollable_size() / self.size.y * dy
    self.scroll.to.y = self.scroll.to.y + delta
    if not config.animate_drag_scroll then
      self:clamp_scroll_position()
      self.scroll.y = self.scroll.to.y
    end
  end
  self.hovered_scrollbar = self:scrollbar_overlaps_point(x, y)
  self.hovered_scrollbar_track = self.hovered_scrollbar or self:scrollbar_track_overlaps_point(x, y)
end


function View:on_mouse_left()
  self.hovered_scrollbar = false
  self.hovered_scrollbar_track = false
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

---@param y number
---@return boolean
function View:on_mouse_wheel(y)

end

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
end


function View:update_scrollbar()
    local x, y, w, h = self:get_scrollbar_rect()
    self.scrollbar.w.to.thumb = w
    self:move_towards(self.scrollbar.w, "thumb", self.scrollbar.w.to.thumb, 0.3, "scroll")
    self.scrollbar.x.thumb = x + w - self.scrollbar.w.thumb
    self.scrollbar.y.thumb = y
    self.scrollbar.h.thumb = h

    local x, y, w, h = self:get_scrollbar_track_rect()
    self.scrollbar.w.to.track = w
    self:move_towards(self.scrollbar.w, "track", self.scrollbar.w.to.track, 0.3, "scroll")
    self.scrollbar.x.track = x + w - self.scrollbar.w.track
    self.scrollbar.y.track = y
    self.scrollbar.h.track = h

    -- we use 100 for a smoother transition
    self.scrollbar_alpha.to = (self.hovered_scrollbar_track or self.dragging_scrollbar) and 100 or 0
    self:move_towards(self.scrollbar_alpha, "value", self.scrollbar_alpha.to, 0.3, "scroll")
end


function View:update()
  self:clamp_scroll_position()
  self:move_towards(self.scroll, "x", self.scroll.to.x, 0.3, "scroll")
  self:move_towards(self.scroll, "y", self.scroll.to.y, 0.3, "scroll")

  self:update_scrollbar()
end


---@param color renderer.color
function View:draw_background(color)
  local x, y = self.position.x, self.position.y
  local w, h = self.size.x, self.size.y
  renderer.draw_rect(x, y, w, h, color)
end


function View:draw_scrollbar_track()
  if not (self.hovered_scrollbar_track or self.dragging_scrollbar)
     and self.scrollbar_alpha.value == 0 then
    return
  end
  local color = { table.unpack(style.scrollbar_track) }
  color[4] = color[4] * self.scrollbar_alpha.value / 100
  renderer.draw_rect(self.scrollbar.x.track, self.scrollbar.y.track,
                     self.scrollbar.w.track, self.scrollbar.h.track, color)
end


function View:draw_scrollbar_thumb()
  local highlight = self.hovered_scrollbar or self.dragging_scrollbar
  local color = highlight and style.scrollbar2 or style.scrollbar
  renderer.draw_rect(self.scrollbar.x.thumb, self.scrollbar.y.thumb,
                     self.scrollbar.w.thumb, self.scrollbar.h.thumb, color)
end


function View:draw_scrollbar()
  self:draw_scrollbar_track()
  self:draw_scrollbar_thumb()
end


function View:draw()
end


return View
