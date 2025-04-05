local core = require "core"
local common = require "core.common"
local config = require "core.config"
local keymap = require "core.keymap"
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

function LogView:__tostring() return "LogView" end

LogView.context = "session"


function LogView:new()
  LogView.super.new(self)
  self.last_item = core.log_items[#core.log_items]
  self.expanding = {}
  self.scrollable = true
  self.yoffset = 0

  core.status_view:show_message("i", style.text, "ctrl+click to copy entry")
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


function LogView:get_scrollable_size()
  local _, y_off = self:get_content_offset()
  local last_y, last_h = 0, 0
  for i, item, x, y, w, h in self:each_item() do
    last_y, last_h = y, h
  end
  if not config.scroll_past_end then
    return last_y + last_h - y_off + style.padding.y
  end
  return last_y + self.size.y - y_off
end


function LogView:on_mouse_pressed(button, px, py, clicks)
  if LogView.super.on_mouse_pressed(self, button, px, py, clicks) then
    return true
  end

  local index, selected
  for i, item, x, y, w, h in self:each_item() do
    if px >= x and py >= y and px < x + w and py < y + h then
      index = i
      selected = item
      break
    end
  end

  if selected then
    if keymap.modkeys["ctrl"] then
      system.set_clipboard(core.get_log(selected))
      core.status_view:show_message("i", style.text, "copied entry #"..index.." to clipboard.")
    else
      self:expand_item(selected)
    end
  end

  return true
end


function LogView:update()
  local item = core.log_items[#core.log_items]
  if self.last_item ~= item then
    local lh = style.font:get_height() + style.padding.y
    if 0 < self.scroll.to.y then
      local index = #core.log_items
      while index > 1 and self.last_item ~= core.log_items[index] do
        index = index - 1
      end
      local diff_index = #core.log_items - index
      self.scroll.to.y = self.scroll.to.y + diff_index * lh
      self.scroll.y = self.scroll.to.y
    else
      self.yoffset = -lh
    end
    self.last_item = item
  end

  local expanding = self.expanding[1]
  if expanding then
    self:move_towards(expanding, "current", expanding.target, nil, "logview")
    if expanding.current == expanding.target then
      table.remove(self.expanding, 1)
    end
  end

  self:move_towards("yoffset", 0, nil, "logview")

  LogView.super.update(self)
end


local function draw_text_multiline(font, text, x, y, color)
  local th = font:get_height()
  local resx = x
  for line in text:gmatch("[^\n]+") do
    resx = renderer.draw_text(style.font, line, x, y, color)
    y = y + th
  end
  return resx, y
end

-- this is just to get a date string that's consistent
local datestr = os.date()
function LogView:draw()
  self:draw_background(style.background)

  local th = style.font:get_height()
  local lh = th + style.padding.y -- for one line
  local iw = math.max(
    style.icon_font:get_width(style.log.ERROR.icon),
    style.icon_font:get_width(style.log.INFO.icon)
  )

  local tw = style.font:get_width(datestr)
  for _, item, x, y, w, h in self:each_item() do
    if y + h >= self.position.y and y <= self.position.y + self.size.y then
      core.push_clip_rect(x, y, w, h)
      x = x + style.padding.x

      x = common.draw_text(
        style.icon_font,
        style.log[item.level].color,
        style.log[item.level].icon,
        "center",
        x, y, iw, lh
      )
      x = x + style.padding.x

      -- timestamps are always 15% of the width
      local time = os.date(nil, item.time)
      common.draw_text(style.font, style.dim, time, "left", x, y, tw, lh)
      x = x + tw + style.padding.x

      w = w - (x - self:get_content_offset())

      if is_expanded(item) then
        y = y + common.round(style.padding.y / 2)
        _, y = draw_text_multiline(style.font, item.text, x, y, style.text)

        local at = "at " .. common.home_encode(item.at)
        _, y = common.draw_text(style.font, style.dim, at, "left", x, y, w, lh)

        if item.info then
          _, y = draw_text_multiline(style.font, item.info, x, y, style.dim)
        end
      else
        local line, has_newline = string.match(item.text, "([^\n]+)(\n?)")
        if has_newline ~= "" then
          line = line .. " ..."
        end
        _, y = common.draw_text(style.font, style.text, line, "left", x, y, w, lh)
      end

      core.pop_clip_rect()
    end
  end
  LogView.super.draw_scrollbar(self)
end

return LogView
