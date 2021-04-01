local core = require "core"
local config = require "core.config"
local command = require "core.command"
local common = require "core.common"
local View = require "core.view"
local style = require "core.style"

local BORDER_WIDTH = common.round(2 * SCALE)
local BORDER_PADDING = common.round(5 * SCALE)

local function noop() end
local function reviter(tbl, i)
  i = i - 1
  if tbl[i] then return i, tbl[i] end
end
local function revipairs(tbl)
  return reviter, tbl, #tbl + 1
end

local NagView = View:extend()

function NagView:new()
  NagView.super.new(self)
  self.size.y = 0
  self.force_focus = false
  self.queue = {}
end

function NagView:get_title()
  return self.title
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

  if core.active_view == self and self.title then
    self:move_towards(self.size, "y", self:get_line_height())
  else
    self:move_towards(self.size, "y", 0)
  end
end

function NagView:draw_overlay()
  local ox, oy = self:get_content_offset()
  oy = oy + self.size.y
  local w, h = core.root_view.size.x, core.root_view.size.y - oy
  core.root_view:defer_draw(function()
    renderer.draw_rect(ox, oy, w, h, style.nagbar_dim)
  end)
end

function NagView:each_option()
  return coroutine.wrap(function()
    local halfh = math.floor(self.size.y / 2)
    local ox, oy = self:get_content_offset()
    ox = ox + self.size.x - style.padding.x

    for i, opt in revipairs(self.options) do
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
  if not self.options then return end
  for i, _, x,y,w,h in self:each_option() do
    if mx >= x and my >= y and mx < x + w and my < y + h then
      self.selected = i
      break
    end
  end
end

function NagView:on_mouse_pressed(button, mx, my, clicks)
  if NagView.super.on_mouse_pressed(self, button, mx, my, clicks) then return end
  for i, _, x,y,w,h in self:each_option() do
    if mx >= x and my >= y and mx < x + w and my < y + h then
      self.selected = i
      command.perform "nag:select"
    end
  end
end

function NagView:on_text_input(text)
  if text:lower() == "y" then
    command.perform "nag:select-yes"
  elseif text:lower() == "n" then
    command.perform "nag:select-no"
  end
end

function NagView:draw()
  if self.size.y <= 0 or not self.title then return end

  self:draw_overlay()
  self:draw_background(style.nagbar)

  local ox, oy = self:get_content_offset()
  ox = ox + style.padding.x

  -- if there are other items, show it
  local message = self.message
  if #self.queue > 0 then
    message = string.format("[%d] %s", #self.queue, message)
  end

  -- draw message
  common.draw_text(style.font, style.nagbar_text, message, "left", style.padding.x, oy, self.size.x, self.size.y)

  -- draw buttons
  for i, opt, bx,by,bw,bh, fx,fy,fw,fh in self:each_option() do
    local fill = i == self.selected and style.nagbar_text or style.nagbar
    local text_color = i == self.selected and style.nagbar or style.nagbar_text

    renderer.draw_rect(bx,by,bw,bh, style.nagbar_text)

    if i ~= self.selected then
      renderer.draw_rect(fx,fy,fw,fh, fill)
    end

    common.draw_text(opt.font, text_color, opt.text, "center", fx,fy,fw,fh)
  end
end

local function findindex(tbl, prop)
  for i, o in ipairs(tbl) do
    if o[prop] then return i end
  end
end

function NagView:next()
  local opts = table.remove(self.queue, 1) or {}
  self.title = opts.title
  self.message = opts.message
  self.options = opts.options
  if self.options then
    self.selected = findindex(self.options, config.yes_by_default and "default_yes" or "default_no")
  end
  self.on_selected = opts.on_selected
  if self.title then
    self.force_focus = true
    core.set_active_view(self)
  else
    self.force_focus = false
    core.set_active_view(core.last_active_view)
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

command.add(NagView, {
  ["nag:previous-entry"] = function()
    local v = core.active_view
    if v ~= core.nag_view then return end
    v.selected = v.selected or 1
    v.selected = v.selected == 1 and #v.options or v.selected - 1
    core.redraw = true
  end,
  ["nag:next-entry"] = function()
    local v = core.active_view
    if v ~= core.nag_view then return end
    v.selected = v.selected or 1
    v.selected = v.selected == #v.options and 1 or v.selected + 1
    core.redraw = true
  end,
  ["nag:select-yes"] = function()
    local v = core.active_view
    if v ~= core.nag_view then return end
    v.selected = findindex(v.options, "default_yes")
    command.perform "nag:select"
  end,
  ["nag:select-no"] = function()
    local v = core.active_view
    if v ~= core.nag_view then return end
    v.selected = findindex(v.options, "default_no")
    command.perform "nag:select"
  end,
  ["nag:select"] = function()
    local v = core.active_view
    if v.selected then
      v.on_selected(v.options[v.selected])
      v:next()
    end
  end,
})

return NagView