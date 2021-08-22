local core = require "core"
local common = require "core.common"
local style = require "core.style"
local View = require "core.view"


local function lines(text)
  if text == "" then return 0 end
  local l = 1
  for _ in string.gmatch(text, "\n") do
    l = l + 1
  end
  return l
end


local item_height_result = {}


local function get_item_height(item)
  local h = item_height_result[item]
  if not h then
    h = {}
    local l = 1 + lines(item.text) + lines(item.info or "")
    h.normal = style.font:get_height() + style.padding.y
    h.expanded = l * style.font:get_height() + style.padding.y
    h.current = h.normal
    h.target = h.current
    item_height_result[item] = h
  end
  return h
end


local LogView = View:extend()


function LogView:new()
  LogView.super.new(self)
  self.last_item = core.log_items[#core.log_items]
  self.expanding = {}
  self.scrollable = true
  self.yoffset = 0
end


function LogView:get_name()
  return "Log"
end


local function is_expanded(item)
  local item_height = get_item_height(item)
  return item_height.target == item_height.expanded
end


function LogView:expand_item(item)
  item = get_item_height(item)
  item.target = item.target == item.expanded and item.normal or item.expanded
  table.insert(self.expanding, item)
end


function LogView:each_item()
  local x, y = self:get_content_offset()
  y = y + style.padding.y + self.yoffset
  return coroutine.wrap(function()
    for i = #core.log_items, 1, -1 do
      local item = core.log_items[i]
      local h = get_item_height(item).current
      coroutine.yield(i, item, x, y, self.size.x, h)
      y = y + h
    end
  end)
end


function LogView:on_mouse_moved(px, py, ...)
  LogView.super.on_mouse_moved(self, px, py, ...)
  local hovered = false
  for _, item, x, y, w, h in self:each_item() do
    if px >= x and py >= y and px < x + w and py < y + h then
      hovered = true
      self.hovered_item = item
      break
    end
  end
  if not hovered then self.hovered_item = nil end
end


function LogView:on_mouse_pressed(button, mx, my, clicks)
  if LogView.super.on_mouse_pressed(self, button, mx, my, clicks) then return end
  if self.hovered_item then
    self:expand_item(self.hovered_item)
  end
end


function LogView:update()
  local item = core.log_items[#core.log_items]
  if self.last_item ~= item then
    self.last_item = item
    self.scroll.to.y = 0
    self.yoffset = -(style.font:get_height() + style.padding.y)
  end

  local expanding = self.expanding[1]
  if expanding then
    self:move_towards(expanding, "current", expanding.target)
    if expanding.current == expanding.target then
      table.remove(self.expanding, 1)
    end
  end

  self:move_towards("yoffset", 0)

  LogView.super.update(self)
end


local function draw_text_multiline(font, text, x, y, color)
  local th = font:get_height()
  local resx, resy = x, y
  for line in text:gmatch("[^\n]+") do
    resy = y
    resx = renderer.draw_text(style.font, line, x, y, color)
    y = y + th
  end
  return resx, resy
end


local function draw_text_elipsis(font, color, text, x, y, w, h, elipsis_style)
  elipsis_style = elipsis_style or "end"
  local c = font:get_width("_")
  local approxc = math.floor(w / c)
  if #text > approxc then
    if elipsis_style == "end" then
      text = string.sub(text, 1, approxc - 3) .. "..."
    elseif elipsis_style == "middle" then
      local mid = math.floor(#text / 2)
      text = string.sub(text, 1, mid - 3) .. "..." .. string.sub(text, mid)
    end
  end
  return common.draw_text(font, color, text, "left", x, y, w, h)
end


function LogView:draw()
  self:draw_background(style.background)

  local th = style.font:get_height()
  local lh = th + style.padding.y -- for one line
  for _, item, x, y, w, h in self:each_item() do
    core.push_clip_rect(x, y, w, h)
    x = x + style.padding.x

    local time = os.date(nil, item.time)
    x = common.draw_text(style.font, style.dim, time, "left", x, y, w, lh)
    x = x + style.padding.x

    x = common.draw_text(style.code_font, style.dim, is_expanded(item) and "-" or "+", "left", x, y, w, lh)
    x = x + style.padding.x
    w = w - (x - self:get_content_offset())

    if is_expanded(item) then
      y = y + common.round(style.padding.y / 2)
      draw_text_multiline(style.font, item.text, x, y, style.text)
      y = y + th

      local at = "at " .. common.home_encode(item.at)
      draw_text_elipsis(style.font, style.dim, at, x, y, w, lh, "middle")
      y = y + th

      if item.info then
        draw_text_multiline(style.font, item.info, x, y, style.dim)
      end
    else
      draw_text_elipsis(style.font, style.text, item.text, x, y, w, lh)
      y = y + th
    end

    core.pop_clip_rect()
  end
end


return LogView
