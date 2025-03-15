local core = require "core"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local Object = require "core.object"

---Scrollbar
---Use Scrollbar:set_size to set the bounding box of the view the scrollbar belongs to.
---Use Scrollbar:update to update the scrollbar animations.
---Use Scrollbar:draw to draw the scrollbar.
---Use Scrollbar:on_mouse_pressed, Scrollbar:on_mouse_released,
---Scrollbar:on_mouse_moved and Scrollbar:on_mouse_left to react to mouse movements;
---the scrollbar won't update automatically.
---Use Scrollbar:set_percent to set the scrollbar location externally.
---
---To manage all the orientations, the scrollbar changes the coordinates system
---accordingly. The "normal" coordinate system adapts the scrollbar coordinates
---as if it's always a vertical scrollbar, positioned at the end of the bounding box.
---@class core.scrollbar : core.object
local Scrollbar = Object:extend()

function Scrollbar:__tostring() return "Scrollbar" end

---@class ScrollbarOptions
---@field direction "v" | "h" @Vertical or Horizontal
---@field alignment "s" | "e" @Start or End (left to right, top to bottom)
---@field force_status "expanded" | "contracted" | false @Force the scrollbar status
---@field expanded_size number? @Override the default value specified by `style.expanded_scrollbar_size`
---@field contracted_size number? @Override the default value specified by `style.scrollbar_size`

---@param options ScrollbarOptions
function Scrollbar:new(options)
  ---Position information of the owner
  self.rect = {
    x = 0, y = 0, w = 0, h = 0,
    ---Scrollable size
    scrollable = 0
  }
  self.normal_rect = {
    across = 0,
    along = 0,
    across_size = 0,
    along_size = 0,
    scrollable = 0
  }
  ---@type integer @Position in percent [0-1]
  self.percent = 0
  ---@type boolean @Scrollbar dragging status
  self.dragging = false
  ---@type integer @Private. Used to offset the start of the drag from the top of the thumb
  self.drag_start_offset = 0
  ---What is currently being hovered. `thumb` implies` track`
  self.hovering = { track = false, thumb = false }
  ---@type "v" | "h"@Vertical or Horizontal
  self.direction = options.direction or "v"
  ---@type "s" | "e" @Start or End (left to right, top to bottom)
  self.alignment = options.alignment or "e"
  ---@type number @Private. Used to keep track of animations
  self.expand_percent = 0
  ---@type "expanded" | "contracted" | false @Force the scrollbar status
  self.force_status = options.force_status
  self:set_forced_status(options.force_status)
  ---@type number? @Override the default value specified by `style.expanded_scrollbar_size`
  self.contracted_size = options.contracted_size
  ---@type number? @Override the default value specified by `style.scrollbar_size`
  self.expanded_size = options.expanded_size
end


---Set the status the scrollbar is forced to keep
---@param status "expanded" | "contracted" | false @The status to force
function Scrollbar:set_forced_status(status)
  self.force_status = status
  if self.force_status == "expanded" then
    self.expand_percent = 1
  end
end


function Scrollbar:real_to_normal(x, y, w, h)
  x, y, w, h = x or 0, y or 0, w or 0, h or 0
  if self.direction == "v" then
    if self.alignment == "s" then
      x = (self.rect.x + self.rect.w) - x - w
    end
    return x, y, w, h
  else
    if self.alignment == "s" then
      y = (self.rect.y + self.rect.h) - y - h
    end
    return y, x, h, w
  end
end


function Scrollbar:normal_to_real(x, y, w, h)
  x, y, w, h = x or 0, y or 0, w or 0, h or 0
  if self.direction == "v" then
    if self.alignment == "s" then
      x = (self.rect.x + self.rect.w) - x - w
    end
    return x, y, w, h
  else
    if self.alignment == "s" then
      x = (self.rect.y + self.rect.h) - x - w
    end
    return y, x, h, w
  end
end


function Scrollbar:_get_thumb_rect_normal()
  local nr = self.normal_rect
  local sz = nr.scrollable
  if sz == math.huge or sz <= nr.along_size
  then
    return 0, 0, 0, 0
  end
  local scrollbar_size = self.contracted_size or style.scrollbar_size
  local expanded_scrollbar_size = self.expanded_size or style.expanded_scrollbar_size
  local along_size = math.max(20, nr.along_size * nr.along_size / sz)
  local across_size = scrollbar_size
  across_size = across_size + (expanded_scrollbar_size - scrollbar_size) * self.expand_percent
  return
    nr.across + nr.across_size - across_size,
    nr.along + self.percent * nr.scrollable * (nr.along_size - along_size) / (sz - nr.along_size),
    across_size,
    along_size
end

---Get the thumb rect (the part of the scrollbar that can be dragged)
---@return integer,integer,integer,integer @x, y, w, h
function Scrollbar:get_thumb_rect()
  return self:normal_to_real(self:_get_thumb_rect_normal())
end


function Scrollbar:_get_track_rect_normal()
  local nr = self.normal_rect
  local sz = nr.scrollable
  if sz <= nr.along_size or sz == math.huge then
    return 0, 0, 0, 0
  end
  local scrollbar_size = self.contracted_size or style.scrollbar_size
  local expanded_scrollbar_size = self.expanded_size or style.expanded_scrollbar_size
  local across_size = scrollbar_size
  across_size = across_size + (expanded_scrollbar_size - scrollbar_size) * self.expand_percent
  return
    nr.across + nr.across_size - across_size,
    nr.along,
    across_size,
    nr.along_size
end

---Get the track rect (the "background" of the scrollbar)
---@return number,number,number,number @x, y, w, h
function Scrollbar:get_track_rect()
  return self:normal_to_real(self:_get_track_rect_normal())
end


function Scrollbar:_overlaps_normal(x, y)
  local sx, sy, sw, sh = self:_get_thumb_rect_normal()
  local scrollbar_size = self.contracted_size or style.scrollbar_size
  local result
  if x >= sx - scrollbar_size * 3 and x <= sx + sw and y >= sy and y <= sy + sh then
    result = "thumb"
  else
    sx, sy, sw, sh = self:_get_track_rect_normal()
    if x >= sx - scrollbar_size * 3 and x <= sx + sw and y >= sy and y <= sy + sh then
      result = "track"
    end
  end
  return result
end

---Get what part of the scrollbar the coordinates overlap
---@return "thumb"|"track"|nil
function Scrollbar:overlaps(x, y)
  x, y = self:real_to_normal(x, y)
  return self:_overlaps_normal(x, y)
end


function Scrollbar:_on_mouse_pressed_normal(button, x, y, clicks)
  local overlaps = self:_overlaps_normal(x, y)
  if overlaps then
    local _, along, _, along_size = self:_get_thumb_rect_normal()
    self.dragging = true
    if overlaps == "thumb" then
      self.drag_start_offset = along - y
      return true
    elseif overlaps == "track" then
      local nr = self.normal_rect
      self.drag_start_offset = - along_size / 2
      return common.clamp((y - nr.along - along_size / 2) / (nr.along_size - along_size), 0, 1)
    end
  end
end

---Updates the scrollbar with mouse pressed info.
---Won't update the scrollbar position automatically.
---Use Scrollbar:set_percent to update it.
---
---This sets the dragging status if needed.
---
---Returns a falsy value if the event happened outside the scrollbar.
---Returns `true` if the thumb was pressed.
---If the track was pressed this returns a value between 0 and 1
---representing the percent of the position.
---@return boolean|number
function Scrollbar:on_mouse_pressed(button, x, y, clicks)
  if button ~= "left" then return end
  x, y = self:real_to_normal(x, y)
  return self:_on_mouse_pressed_normal(button, x, y, clicks)
end

---Updates the scrollbar hover status.
---This gets called by other functions and shouldn't be called manually
function Scrollbar:_update_hover_status_normal(x, y)
  local overlaps = self:_overlaps_normal(x, y)
  self.hovering.thumb = overlaps == "thumb"
  self.hovering.track = self.hovering.thumb or overlaps == "track"
  return self.hovering.track or self.hovering.thumb
end

function Scrollbar:_on_mouse_released_normal(button, x, y)
  self.dragging = false
  return self:_update_hover_status_normal(x, y)
end

---Updates the scrollbar dragging status
function Scrollbar:on_mouse_released(button, x, y)
  if button ~= "left" then return end
  x, y = self:real_to_normal(x, y)
  return self:_on_mouse_released_normal(button, x, y)
end


function Scrollbar:_on_mouse_moved_normal(x, y, dx, dy)
  if self.dragging then
    local nr = self.normal_rect
    return common.clamp((y - nr.along + self.drag_start_offset) / nr.along_size, 0, 1)
  end
  return self:_update_hover_status_normal(x, y)
end

---Updates the scrollbar with mouse moved info.
---Won't update the scrollbar position automatically.
---Use Scrollbar:set_percent to update it.
---
---This updates the hovering status.
---
---Returns a falsy value if the event happened outside the scrollbar.
---Returns `true` if the scrollbar is hovered.
---If the scrollbar was being dragged, this returns a value between 0 and 1
---representing the percent of the position.
---@return boolean|number
function Scrollbar:on_mouse_moved(x, y, dx, dy)
  x, y = self:real_to_normal(x, y)
  dx, dy = self:real_to_normal(dx, dy) -- TODO: do we need this? (is this even correct?)
  return self:_on_mouse_moved_normal(x, y, dx, dy)
end

---Updates the scrollbar hovering status
function Scrollbar:on_mouse_left()
  self.hovering.track, self.hovering.thumb = false, false
end

---Updates the bounding box of the view the scrollbar belongs to.
---@param x number
---@param y number
---@param w number
---@param h number
---@param scrollable number @size of the scrollable area
function Scrollbar:set_size(x, y, w, h, scrollable)
  self.rect.x, self.rect.y, self.rect.w, self.rect.h = x, y, w, h
  self.rect.scrollable = scrollable

  local nr = self.normal_rect
  nr.across, nr.along, nr.across_size, nr.along_size = self:real_to_normal(x, y, w, h)
  nr.scrollable = scrollable
end

---Updates the scrollbar location
---@param percent number @number between 0 and 1 representing the position of the middle part of the thumb
function Scrollbar:set_percent(percent)
  self.percent = percent
end

---Updates the scrollbar animations
function Scrollbar:update()
  -- TODO: move the animation code to its own class
  if not self.force_status then
    local dest = (self.hovering.track or self.dragging) and 1 or 0
    local diff = math.abs(self.expand_percent - dest)
    if not config.transitions or diff < 0.05 or config.disabled_transitions["scroll"] then
      self.expand_percent = dest
    else
      local rate = 0.3
      if config.fps ~= 60 or config.animation_rate ~= 1 then
        local dt = 60 / config.fps
        rate = 1 - common.clamp(1 - rate, 1e-8, 1 - 1e-8)^(config.animation_rate * dt)
      end
      self.expand_percent = common.lerp(self.expand_percent, dest, rate)
    end
    if diff > 1e-8 then
      core.redraw = true
    end
  elseif self.force_status == "expanded" then
    self.expand_percent = 1
  elseif self.force_status == "contracted" then
    self.expand_percent = 0
  end
end


---Draw the scrollbar track
function Scrollbar:draw_track()
  if not (self.hovering.track or self.dragging)
     and self.expand_percent == 0 then
    return
  end
  local color = { table.unpack(style.scrollbar_track) }
  color[4] = color[4] * self.expand_percent
  local x, y, w, h = self:get_track_rect()
  renderer.draw_rect(x, y, w, h, color)
end

---Draw the scrollbar thumb
function Scrollbar:draw_thumb()
  local highlight = self.hovering.thumb or self.dragging
  local color = highlight and style.scrollbar2 or style.scrollbar
  local x, y, w, h = self:get_thumb_rect()
  renderer.draw_rect(x, y, w, h, color)
end

---Draw both the scrollbar track and thumb
function Scrollbar:draw()
  self:draw_track()
  self:draw_thumb()
end

return Scrollbar
