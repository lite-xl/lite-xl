local core = require "core"
local config = require "core.config"
local common = require "core.common"
local View = require "core.view"
local style = require "core.style"

local BORDER_WIDTH = common.round(2 * SCALE)
local BORDER_PADDING = common.round(5 * SCALE)

local noop = function() end

local NagView = View:extend()

function NagView:new()
  NagView.super.new(self)
  self.size.y = 0
  self.force_focus = false
  self.title = "Warning"
  self.message = ""
  self.options = {}
  self.submit = noop
end

function NagView:get_title()
  return self.title
end

function NagView:each_option()
  return coroutine.wrap(function()
    for i = #self.options, 1, -1 do
      coroutine.yield(i, self.options[i])
    end
  end)
end

function NagView:get_options_height()
  local max = 0
  for _, opt in ipairs(self.options) do
    local lh = style.font:get_height(opt.text)
    if lh > max then max = lh end
  end
  return max
end

function NagView:get_line_height()
  local maxlh = math.max(style.font:get_height(self.message), self:get_options_height())
  return 2 * BORDER_WIDTH + 2 * BORDER_PADDING + maxlh + 2 * style.padding.y
end

function NagView:update()
  NagView.super.update(self)

  local dest = core.active_view == self and self:get_line_height() or 0
  self:move_towards(self.size, "y", dest)
end

function NagView:draw_overlay()
  local ox, oy = self:get_content_offset()
  oy = oy + self.size.y
  local w, h = core.root_view.size.x, core.root_view.size.y - oy
  core.root_view:defer_draw(function()
    renderer.draw_rect(ox, oy, w, h, style.nagbar_dim)
  end)
end

function NagView:each_visible_option()
  return coroutine.wrap(function()
    local halfh = math.floor(self.size.y / 2)
    local ox, oy = self:get_content_offset()
    ox = ox + self.size.x - style.padding.x

    for i, opt in self:each_option() do
      local lw, lh = opt.font:get_width(opt.text), opt.font:get_height(opt.text)
      local bw, bh = (lw + 2 * BORDER_WIDTH + 2 * BORDER_PADDING), (lh + 2 * BORDER_WIDTH + 2 * BORDER_PADDING)
      local halfbh = math.floor(bh / 2)
      local bx, by = math.max(0, ox - bw), math.max(0, oy + halfh - halfbh)
      local fw, fh = bw - 2 * BORDER_WIDTH, bh - 2 * BORDER_WIDTH
      local fx, fy = bx + BORDER_WIDTH, by + BORDER_WIDTH
      coroutine.yield(i, opt, bx,by,bw,bh, fx,fy,fw,fh)
      ox = ox - bw - style.padding.x
    end
  end)
end

function NagView:on_mouse_moved(mx, my, ...)
  NagView.super.on_mouse_moved(self, mx, my, ...)
  local selected = false
  for i, _, x,y,w,h in self:each_visible_option() do
    if mx >= x and my >= y and mx < x + w and my < y + h then
      self.selected = i
      selected = true
      break
    end
  end

  if not selected then self.selected = nil end
end

function NagView:on_mouse_pressed(...)
  if not NagView.super.on_mouse_pressed(self, ...) and self.selected then
    self.force_focus = false
    core.set_active_view(core.last_active_view)
    self.submit(self.options[self.selected])
  end
end

function NagView:draw()
  if self.size.y <= 0 then return end

  self:draw_overlay()
  self:draw_background(style.nagbar)

  -- draw message
  local ox, oy = self:get_content_offset()
  common.draw_text(style.font, style.nagbar_text, self.message, "left", ox + style.padding.x, oy, self.size.x, self.size.y)

  -- draw buttons
  for i, opt, bx,by,bw,bh, fx,fy,fw,fh in self:each_visible_option() do
    local fill = i == self.selected and style.nagbar_text or style.nagbar
    local text_color = i == self.selected and style.nagbar or style.nagbar_text

    renderer.draw_rect(bx,by,bw,bh, style.nagbar_text)

    if i ~= self.selected then
      renderer.draw_rect(fx,fy,fw,fh, fill)
    end

    common.draw_text(opt.font, text_color, opt.text, "center", fx,fy,fw,fh)
  end
end

function NagView:show(title, message, options, on_select, on_cancel)
  self.title = title or "Warning"
  self.message = message or "Empty?"
  self.options = options or {}
  if on_cancel then table.insert(options, { key = "cancel", font = style.icon_font, text = "C" }) end
  self.force_focus = true
  self.submit = function(item)
    self.submit = noop -- reset the submit function
    if item.key == "cancel" and on_cancel then
      on_cancel()
    elseif on_select then
      on_select(item)
    end
  end
  core.set_active_view(self)
end

return NagView