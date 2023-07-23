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

---An item in the context menu.
---@class core.contextmenu.item
---@field text string
---@field info string|nil If provided, this text is displayed on the right side of the menu.
---@field command string|fun()

---A list of items with the same predicate.
---@see core.command.predicate
---@class core.contextmenu.itemset
---@field predicate core.command.predicate
---@field items core.contextmenu.item[]

---A context menu.
---@class core.contextmenu : core.object
---@field itemset core.contextmenu.itemset[]
---@field show_context_menu boolean
---@field selected number
---@field position core.view.position
---@field current_scale number
local ContextMenu = Object:extend()

---A unique value representing the divider in a context menu.
ContextMenu.DIVIDER = DIVIDER

---Creates a new context menu.
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

---Registers a list of items into the context menu with a predicate.
---@param predicate core.command.predicate
---@param items core.contextmenu.item[]
function ContextMenu:register(predicate, items)
  predicate = command.generate_predicate(predicate)
  update_items_size(items, true)
  table.insert(self.itemset, { predicate = predicate, items = items })
end

---Shows the context menu.
---@param x number
---@param y number
---@return boolean # If true, the context menu is shown.
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
    x = common.clamp(x, 0, core.root_view.size.x - w - style.padding.x)
    y = common.clamp(y, 0, core.root_view.size.y - h)

    self.position.x, self.position.y = x, y
    self.show_context_menu = true
    core.request_cursor("arrow")
    return true
  end
  return false
end

---Hides the context menu.
function ContextMenu:hide()
  self.show_context_menu = false
  self.items = nil
  self.selected = -1
  self.height = 0
  core.request_cursor(core.active_view.cursor)
end

---Returns an iterator that iterates over each context menu item and their dimensions.
---@return fun(): number, core.contextmenu.item, number, number, number, number
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

---Event handler for mouse movements.
---@param px any
---@param py any
---@return boolean # true if the event is caught.
function ContextMenu:on_mouse_moved(px, py)
  if not self.show_context_menu then return false end

  self.selected = -1
  for i, item, x, y, w, h in self:each_item() do
    if px > x and px <= x + w and py > y and py <= y + h then
      self.selected = i
      break
    end
  end
  return true
end

---Event handler for when the selection is confirmed.
---@param item core.contextmenu.item
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

---Selects the the previous item.
function ContextMenu:focus_previous()
  self.selected = (self.selected == -1 or self.selected == 1) and #self.items or change_value(self.selected, -1)
  if self:get_item_selected() == DIVIDER then
    self.selected = change_value(self.selected, -1)
  end
end

---Selects the next item.
function ContextMenu:focus_next()
  self.selected = (self.selected == -1 or self.selected == #self.items) and 1 or change_value(self.selected, 1)
  if self:get_item_selected() == DIVIDER then
    self.selected = change_value(self.selected, 1)
  end
end

---Gets the currently selected item.
---@return core.contextmenu.item|nil
function ContextMenu:get_item_selected()
  return (self.items or {})[self.selected]
end

---Hides the context menu and performs the command if an item is selected.
function ContextMenu:call_selected_item()
    local selected = self:get_item_selected()
    self:hide()
    if selected then
      self:on_selected(selected)
    end
end

---Event handler for mouse press.
---@param button core.view.mousebutton
---@param px number
---@param py number
---@param clicks number
---@return boolean # true if the event is caught.
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

---@type fun(self: table, k: string, dest: number, rate?: number, name?: string)
ContextMenu.move_towards = View.move_towards

---Event handler for content update.
function ContextMenu:update()
  if self.show_context_menu then
    self:move_towards("height", self.items.height, nil, "contextmenu")
  end
end

---Draws the context menu.
---
---This wraps `ContextMenu:draw_context_menu()`.
---@see core.contextmenu.draw_context_menu
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

---Draws the context menu.
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
