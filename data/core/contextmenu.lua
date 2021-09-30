local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local Object = require "core.object"

local border_width = 1
local divider_width = 1
local DIVIDER = {}

local ContextMenu = Object:extend()

ContextMenu.DIVIDER = DIVIDER

function ContextMenu:new()
  self.itemset = {}
  self.show_context_menu = false
  self.selected = -1
  self.height = 0
  self.position = { x = 0, y = 0 }
end

local function get_item_size(item)
  local lw, lh
  if item == DIVIDER then
    lw = 0
    lh = divider_width
  else
    lw = style.font:get_width(item.text)
    if item.info then
      lw = lw + style.padding.x + style.font:get_width(item.info)
    end
    lh = style.font:get_height() + style.padding.y
  end
  return lw, lh
end

function ContextMenu:register(predicate, items)
  if type(predicate) == "string" then
    predicate = require(predicate)
  end
  if type(predicate) == "table" then
    local class = predicate
    predicate = function() return core.active_view:is(class) end
  end

  local width, height = 0, 0 --precalculate the size of context menu
  for i, item in ipairs(items) do
    if item ~= DIVIDER then
      item.info = keymap.reverse_map[item.command]
    end
    local lw, lh = get_item_size(item)
    width = math.max(width, lw)
    height = height + lh
  end
  width = width + style.padding.x * 2
  items.width, items.height = width, height
  table.insert(self.itemset, { predicate = predicate, items = items })
end

function ContextMenu:show(x, y)
  self.items = nil
  local items_list = { width = 0, height = 0 }
  for _, items in ipairs(self.itemset) do
    if items.predicate(x, y) then
      items_list.width = math.max(items_list.width, items.items.width)
      items_list.height = items_list.height + items.items.height
      for _, subitems in ipairs(items.items) do
        table.insert(items_list, subitems)
      end
    end
  end

  if #items_list > 0 then
    self.items = items_list
    local w, h = self.items.width, self.items.height

    -- by default the box is opened on the right and below
    if x + w >= core.root_view.size.x then
      x = x - w
    end
    if y + h >= core.root_view.size.y then
      y = y - h
    end

    self.position.x, self.position.y = x, y
    self.show_context_menu = true
    return true
  end
  return false
end

function ContextMenu:hide()
  self.show_context_menu = false
  self.items = nil
  self.selected = -1
  self.height = 0
end

function ContextMenu:each_item()
  local x, y, w = self.position.x, self.position.y, self.items.width
  local oy = y
  return coroutine.wrap(function()
    for i, item in ipairs(self.items) do
      local _, lh = get_item_size(item)
      if y - oy > self.height then break end
      coroutine.yield(i, item, x, y, w, lh)
      y = y + lh
    end
  end)
end

function ContextMenu:on_mouse_moved(px, py)
  if not self.show_context_menu then return end

  self.selected = -1
  for i, item, x, y, w, h in self:each_item() do
    if px > x and px <= x + w and py > y and py <= y + h then
      self.selected = i
      break
    end
  end
  if self.selected >= 0 then
    core.request_cursor("arrow")
  end
  return true
end

function ContextMenu:on_selected(item)
  if type(item.command) == "string" then
    command.perform(item.command)
  else
    item.command()
  end
end

function ContextMenu:on_mouse_pressed(button, x, y, clicks)
  local selected = (self.items or {})[self.selected]
  local caught = false

  self:hide()
  if button == "left" then
    if selected then
      self:on_selected(selected)
      caught = true
    end
  end

  if button == "right" then
    caught = self:show(x, y)
  end
  return caught
end

-- copied from core.docview
function ContextMenu:move_towards(t, k, dest, rate)
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

function ContextMenu:update()
  if self.show_context_menu then
    self:move_towards("height", self.items.height)
  end
end

function ContextMenu:draw()
  if not self.show_context_menu then return end
  core.root_view:defer_draw(self.draw_context_menu, self)
end

function ContextMenu:draw_context_menu()
  if not self.items then return end
  local bx, by, bw, bh = self.position.x, self.position.y, self.items.width, self.height

  renderer.draw_rect(
    bx - border_width,
    by - border_width,
    bw + (border_width * 2),
    bh + (border_width * 2),
    style.divider
  )
  renderer.draw_rect(bx, by, bw, bh, style.background3)

  for i, item, x, y, w, h in self:each_item() do
    if item == DIVIDER then
      renderer.draw_rect(x, y, w, h, style.caret)
    else
      if i == self.selected then
        renderer.draw_rect(x, y, w, h, style.selection)
      end

      common.draw_text(style.font, style.text, item.text, "left", x + style.padding.x, y, w, h)
      if item.info then
        common.draw_text(style.font, style.dim, item.info, "right", x, y, w - style.padding.x, h)
      end
    end
  end
end

return ContextMenu
