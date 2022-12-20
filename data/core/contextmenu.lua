local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local Object = require "core.object"
local View = require "core.view"

local border_width = 1
local divider_width = 1
local divider_padding = 5
local DIVIDER = {}

---@class core.contextmenu : core.object
local ContextMenu = Object:extend()

ContextMenu.DIVIDER = DIVIDER

function ContextMenu:new()
  self.itemset = {}
  self.show_context_menu = false
  self.selected = -1
  self.height = 0
  self.position = { x = 0, y = 0 }
  self.current_scale = SCALE
end

local function get_item_size(item)
  local lw, lh
  if item == DIVIDER then
    lw = 0
    lh = divider_width + divider_padding * SCALE * 2
  else
    lw = style.font:get_width(item.text)
    if item.info then
      lw = lw + style.padding.x + style.font:get_width(item.info)
    end
    lh = style.font:get_height() + style.padding.y
  end
  return lw, lh
end

local function update_items_size(items, update_binding)
  local width, height = 0, 0
  for _, item in ipairs(items) do
    if update_binding and item ~= DIVIDER then
      item.info = keymap.get_binding(item.command)
    end
    local lw, lh = get_item_size(item)
    width = math.max(width, lw)
    height = height + lh
  end
  width = width + style.padding.x * 2
  items.width, items.height = width, height
end

function ContextMenu:register(predicate, items)
  predicate = command.generate_predicate(predicate)
  update_items_size(items, true)
  table.insert(self.itemset, { predicate = predicate, items = items })
end

function ContextMenu:show(x, y)
  self.items = nil
  local items_list = { width = 0, height = 0 }
  for _, items in ipairs(self.itemset) do
    if items.predicate(x, y) then
      items_list.width = math.max(items_list.width, items.items.width)
      items_list.height = items_list.height
      for _, subitems in ipairs(items.items) do
        if not subitems.command or command.is_valid(subitems.command) then
          local lw, lh = get_item_size(subitems)
          items_list.height = items_list.height + lh
          table.insert(items_list, subitems)
        end
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
    core.request_cursor("arrow")
    return true
  end
  return false
end

function ContextMenu:hide()
  self.show_context_menu = false
  self.items = nil
  self.selected = -1
  self.height = 0
  core.request_cursor(core.active_view.cursor)
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
  return true
end

function ContextMenu:on_selected(item)
  if type(item.command) == "string" then
    command.perform(item.command)
  else
    item.command()
  end
end

local function change_value(value, change)
  return value + change
end

function ContextMenu:focus_previous()
  self.selected = (self.selected == -1 or self.selected == 1) and #self.items or change_value(self.selected, -1)
  if self:get_item_selected() == DIVIDER then
    self.selected = change_value(self.selected, -1)
  end
end

function ContextMenu:focus_next()
  self.selected = (self.selected == -1 or self.selected == #self.items) and 1 or change_value(self.selected, 1)
  if self:get_item_selected() == DIVIDER then
    self.selected = change_value(self.selected, 1)
  end
end

function ContextMenu:get_item_selected()
  return (self.items or {})[self.selected]
end

function ContextMenu:call_selected_item()
    local selected = self:get_item_selected()
    self:hide()
    if selected then
      self:on_selected(selected)
    end
end

function ContextMenu:on_mouse_pressed(button, px, py, clicks)
  local caught = false

  if self.show_context_menu then
    if button == "left" then
      local selected = self:get_item_selected()
      if selected then
        self:on_selected(selected)
      end
    end
    self:hide()
    caught = true
  else
    if button == "right" then
      caught = self:show(px, py)
    end
  end
  return caught
end

ContextMenu.move_towards = View.move_towards

function ContextMenu:update()
  if self.show_context_menu then
    self:move_towards("height", self.items.height, nil, "contextmenu")
  end
end

function ContextMenu:draw()
  if not self.show_context_menu then return end
  if self.current_scale ~= SCALE then
    update_items_size(self.items)
    for _, set in ipairs(self.itemset) do
      update_items_size(set.items)
    end
    self.current_scale = SCALE
  end
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
      renderer.draw_rect(x, y + divider_padding * SCALE, w, divider_width, style.divider)
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
