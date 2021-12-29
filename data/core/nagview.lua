local core = require "core"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local View = require "core.view"
local style = require "core.style"

local BORDER_WIDTH = common.round(1 * SCALE)
local UNDERLINE_WIDTH = common.round(2 * SCALE)
local UNDERLINE_MARGIN = common.round(1 * SCALE)

local noop = function() end

local NagView = View:extend()

function NagView:new()
  NagView.super.new(self)
  self.size.y = 0
  self.show_height = 0
  self.force_focus = false
  self.queue = {}
end

function NagView:get_title()
  return self.title
end

-- The two methods below are duplicated from DocView
function NagView:get_line_height()
  return math.floor(style.font:get_height() * config.line_height)
end

function NagView:get_line_text_y_offset()
  local lh = self:get_line_height()
  local th = style.font:get_height()
  return (lh - th) / 2
end

-- Buttons height without padding
function NagView:get_buttons_height()
  local lh = style.font:get_height()
  local bt_padding = lh / 2
  return lh + 2 * BORDER_WIDTH + 2 * bt_padding
end

function NagView:get_target_height()
  return self.target_height + 2 * style.padding.y
end

function NagView:update()
  NagView.super.update(self)

  if core.active_view == self and self.title then
    self:move_towards(self, "show_height", self:get_target_height())
    self:move_towards(self, "underline_progress", 1)
  else
    self:move_towards(self, "show_height", 0)
  end
end

function NagView:dim_window_content()
  local ox, oy = self:get_content_offset()
  oy = oy + self.show_height
  local w, h = core.root_view.size.x, core.root_view.size.y - oy
  core.root_view:defer_draw(function()
    renderer.draw_rect(ox, oy, w, h, style.nagbar_dim)
  end)
end

function NagView:change_hovered(i)
  if i ~= self.hovered_item then
    self.hovered_item = i
    self.underline_progress = 0
    core.redraw = true
  end
end

function NagView:each_option()
  return coroutine.wrap(function()
    if not self.options then return end
    local opt, bw,bh,ox,oy
    bh = self:get_buttons_height()
    ox,oy = self:get_content_offset()
    ox = ox + self.size.x
    oy = oy + self.show_height - bh - style.padding.y

    for i = #self.options, 1, -1 do
      opt = self.options[i]
      bw = opt.font:get_width(opt.text) + 2 * BORDER_WIDTH + style.padding.x

      ox = ox - bw - style.padding.x
      coroutine.yield(i, opt, ox,oy,bw,bh)
    end
  end)
end

function NagView:on_mouse_moved(mx, my, ...)
  NagView.super.on_mouse_moved(self, mx, my, ...)
  for i, _, x,y,w,h in self:each_option() do
    if mx >= x and my >= y and mx < x + w and my < y + h then
      self:change_hovered(i)
      break
    end
  end
end

-- Used to store saved value for RootView.on_view_mouse_pressed
local on_view_mouse_pressed


local function capture_mouse_pressed(nag_view)
  -- RootView is loaded locally to avoid NagView and RootView being
  -- mutually recursive
  local RootView = require "core.rootview"
  on_view_mouse_pressed = RootView.on_view_mouse_pressed
  RootView.on_view_mouse_pressed = function(button, x, y, clicks)
    local handled = NagView.on_mouse_pressed(nag_view, button, x, y, clicks)
    return handled or on_view_mouse_pressed(button, x, y, clicks)
  end
end


local function release_mouse_pressed()
  local RootView = require "core.rootview"
  if on_view_mouse_pressed then
    RootView.on_view_mouse_pressed = on_view_mouse_pressed
    on_view_mouse_pressed = nil
  end
end


function NagView:on_mouse_pressed(button, mx, my, clicks)
  if NagView.super.on_mouse_pressed(self, button, mx, my, clicks) then return true end
  for i, _, x,y,w,h in self:each_option() do
    if mx >= x and my >= y and mx < x + w and my < y + h then
      self:change_hovered(i)
      command.perform "dialog:select"
      return true
    end
  end
end

function NagView:on_text_input(text)
  if text:lower() == "y" then
    command.perform "dialog:select-yes"
  elseif text:lower() == "n" then
    command.perform "dialog:select-no"
  end
end


local function draw_nagview_message(self)
  if self.show_height <= 0 or not self.title then return end

  self:dim_window_content()

  -- draw message's background
  local ox, oy = self:get_content_offset()
  renderer.draw_rect(ox, oy, self.size.x, self.show_height, style.nagbar)

  ox = ox + style.padding.x

  -- if there are other items, show it
  if #self.queue > 0 then
    local str = string.format("[%d]", #self.queue)
    ox = common.draw_text(style.font, style.nagbar_text, str, "left", ox, oy, self.size.x, self.show_height)
    ox = ox + style.padding.x
  end

  -- draw message
  local lh = style.font:get_height() * config.line_height
  oy = oy + style.padding.y + (self.target_height - self:get_message_height()) / 2
  for msg_line in self.message:gmatch("(.-)\n") do
    local ty = oy + self:get_line_text_y_offset()
    renderer.draw_text(style.font, msg_line, ox, ty, style.nagbar_text)
    oy = oy + lh
  end

  -- draw buttons
  for i, opt, bx,by,bw,bh in self:each_option() do
    local fw,fh = bw - 2 * BORDER_WIDTH, bh - 2 * BORDER_WIDTH
    local fx,fy = bx + BORDER_WIDTH, by + BORDER_WIDTH

    -- draw the button
    renderer.draw_rect(bx,by,bw,bh, style.nagbar_text)
    renderer.draw_rect(fx,fy,fw,fh, style.nagbar)

    if i == self.hovered_item then -- draw underline
      local uw = fw - 2 * UNDERLINE_MARGIN
      local halfuw = uw / 2
      local lx = fx + UNDERLINE_MARGIN + halfuw - (halfuw * self.underline_progress)
      local ly = fy + fh - UNDERLINE_MARGIN - UNDERLINE_WIDTH
      uw = uw * self.underline_progress
      renderer.draw_rect(lx,ly,uw,UNDERLINE_WIDTH, style.nagbar_text)
    end

    common.draw_text(opt.font, style.nagbar_text, opt.text, "center", fx,fy,fw,fh)
  end
end

function NagView:draw()
  core.root_view:defer_draw(draw_nagview_message, self)
end

function NagView:get_message_height()
  local h = 0
  for str in string.gmatch(self.message, "(.-)\n") do
    h = h + style.font:get_height() * config.line_height
  end
  return h
end


function NagView:next()
  local opts = table.remove(self.queue, 1) or {}
  self.title = opts.title
  self.message = opts.message and opts.message .. "\n"
  self.options = opts.options
  self.on_selected = opts.on_selected
  if self.message and self.options then
    local message_height = self:get_message_height()
    -- self.target_height is the nagview height needed to display the message and
    -- the buttons, excluding the top and bottom padding space.
    self.target_height = math.max(message_height, self:get_buttons_height())
    self:change_hovered(common.find_index(self.options, "default_yes"))
  end
  self.force_focus = self.message ~= nil
  core.set_active_view(self.message ~= nil and self or
                       core.next_active_view or core.last_active_view)
  if self.message ~= nil and self then
    -- We add a hook to manage all the mouse_pressed events.
    capture_mouse_pressed(self)
  else
    release_mouse_pressed()
  end
end

function NagView:show(title, message, options, on_select)
  local opts = {}
  opts.title = assert(title, "No title")
  opts.message = assert(message, "No message")
  opts.options = assert(options, "No options")
  opts.on_selected = on_select or noop
  table.insert(self.queue, opts)
  if #self.queue > 0 and not self.title then self:next() end
end

return NagView
