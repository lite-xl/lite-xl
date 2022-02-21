local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local style = require "core.style"
local DocView = require "core.docview"
local CommandView = require "core.commandview"
local LogView = require "core.logview"
local View = require "core.view"
local Object = require "core.object"

---@alias StatusView.styledtext table<integer, renderer.font|renderer.color|string>
---@alias StatusView.itemscb fun():StatusView.styledtext,StatusView.styledtext
---@alias StatusView.clickcb fun(button: string, x: number, y: number)
---@alias StatusView.predicate fun():boolean

---A status bar implementation for lite, check core.status_view.
---@class StatusView : View
---@field private items StatusView.item[]
---@field private hovered_item StatusView.item
---@field private message_timeout number
---@field private message StatusView.styledtext
---@field private tooltip_mode boolean
---@field private tooltip StatusView.styledtext
local StatusView = View:extend()

---@class StatusView.item
---@field predicate StatusView.predicate
---@field items StatusView.itemscb
---@field onclick StatusView.clickcb
---@field tooltip string | nil
---@field lx number
---@field lw number
---@field rx number
---@field rw number
---@field active boolean
StatusView.item = {}

---Space separator
---@type string
StatusView.separator  = "      "

---Pipe separator
---@type string
StatusView.separator2 = "   |   "


---Constructor
function StatusView:new()
  StatusView.super.new(self)
  self.message_timeout = 0
  self.message = {}
  self.tooltip_mode = false
  self.tooltip = {}
  self.items = {}
  self.hovered_item = {}
  self.pointer = {x = 0, y = 0}

  self:add_item(
    function()
      return  core.active_view:is(DocView) and
        not core.active_view:is(CommandView)
    end,
    self.get_doc_items
  )

  self:add_item("core.commandview", self.get_command_items)
end


---Adds an item to be rendered in the status bar.
---@param predicate string | table | StatusView.predicate :
---A coindition to evaluate if the item should be displayed. If a string
---is given it is treated as a file that returns a valid object which is
---checked against the current active view, the sames applies if a table is
---given. A function can be used instead to perform a custom evaluation.
---@param itemscb StatusView.itemscb :
---This function should return two tables of StatusView.styledtext elements
---for both left and right, empty tables are allowed.
---@param pos? integer :
---The position in which to insert the given item on the internal table,
---a value of -1 inserts the item at the end which is the default. A value
---of 1 will insert the item at the beggining.
---@param onclick? StatusView.clickcb Executed when user clicks the item
---@param tooltip? string Displayed when mouse hovers the item
function StatusView:add_item(predicate, itemscb, pos, onclick, tooltip)
  predicate = predicate or always_true
  if type(predicate) == "string" then
    predicate = require(predicate)
  end
  if type(predicate) == "table" then
    local class = predicate
    predicate = function() return core.active_view:is(class) end
  end
  ---@type StatusView.item
  local item = {
    predicate = predicate,
    items = itemscb,
    onclick = onclick,
    tooltip = tooltip
  }
  pos = type(pos) == "nil" and -1 or math.abs(tonumber(pos))
  if pos == -1 then
    table.insert(self.items, item)
  else
    table.insert(self.items, pos, item)
  end
end


---Shows a message for a predefined amount of time.
---@param icon string
---@param icon_color renderer.color
---@param text string
function StatusView:show_message(icon, icon_color, text)
  self.message = {
    icon_color, style.icon_font, icon,
    style.dim, style.font, StatusView.separator2, style.text, text
  }
  self.message_timeout = system.get_time() + config.message_timeout
end


---Activates tooltip mode displaying only the given
---text until StatusView:remove_tooltip() is called.
---@param text string | StatusView.styledtext
function StatusView:show_tooltip(text)
  self.tooltip = type(text) == "table" and text or { text }
  self.tooltip_mode = true
end


---Deactivates tooltip mode.
function StatusView:remove_tooltip()
  self.tooltip_mode = false
end


---Helper function to draw the styled text.
---@param self StatusView
---@param items StatusView.styledtext
---@param x number
---@param y number
---@param draw_fn fun(font,color,text,align, x,y,w,h):number
local function draw_items(self, items, x, y, draw_fn)
  local font = style.font
  local color = style.text

  for _, item in ipairs(items) do
    if Object.is(item, renderer.font) then
      font = item
    elseif type(item) == "table" then
      color = item
    else
      x = draw_fn(font, color, item, nil, x, y, 0, self.size.y)
    end
  end

  return x
end


---Helper function to calculate the width of text by using it as part of
---the helper function draw_items().
---@param font renderer.font
---@param text string
---@param x number
local function text_width(font, _, text, _, x)
  return x + font:get_width(text)
end


---Draws a table of styled text on the status bar starting on the left or right.
---@param items StatusView.styledtext
---@param right_align boolean
---@param yoffset number
function StatusView:draw_items(items, right_align, yoffset)
  local x, y = self:get_content_offset()
  y = y + (yoffset or 0)
  if right_align then
    local w = draw_items(self, items, 0, 0, text_width)
    x = x + self.size.x - w - style.padding.x
    draw_items(self, items, x, y, common.draw_text)
  else
    x = x + style.padding.x
    draw_items(self, items, x, y, common.draw_text)
  end
end


---Draw the tooltip of a given status bar item.
---@param item StatusView.item
function StatusView:draw_item_tooltip(item)
  core.root_view:defer_draw(function()
    local text = item.tooltip
    local w = style.font:get_width(text)
    local h = style.font:get_height()
    local x = self.pointer.x - (w / 2) - (style.padding.x * 2)

    if x < 0 then x = 0 end
    if x + w + (style.padding.x * 2) > self.size.x then
      x = self.size.x - w - (style.padding.x * 2)
    end

    renderer.draw_rect(
      x,
      self.position.y - h - (style.padding.y * 2),
      w + (style.padding.x * 2),
      h + (style.padding.y * 2),
      style.background3
    )

    renderer.draw_text(
      style.font,
      text,
      x + style.padding.x,
      self.position.y - h - style.padding.y,
      style.text
    )
  end)
end


---The predefined status bar items displayed when a document view is active.
---@return table left
---@return table right
function StatusView:get_doc_items()
  local dv = core.active_view
  local line, col = dv.doc:get_selection()
  local dirty = dv.doc:is_dirty()
  local indent_type, indent_size, indent_confirmed = dv.doc:get_indent_info()
  local indent_label = (indent_type == "hard") and "tabs: " or "spaces: "
  local indent_size_str = tostring(indent_size) .. (indent_confirmed and "" or "*") or "unknown"

  return {
    dirty and style.accent or style.text, style.icon_font, "f",
    style.dim, style.font, self.separator2, style.text,
    dv.doc.filename and style.text or style.dim, dv.doc:get_name(),
    style.text,
    self.separator,
    "line: ", line,
    self.separator,
    col > config.line_limit and style.accent or style.text, "col: ", col,
    style.text,
    self.separator,
    string.format("%.f%%", line / #dv.doc.lines * 100),
  }, {
    style.text, indent_label, indent_size,
    style.dim, self.separator2, style.text,
    style.icon_font, "g",
    style.font, style.dim, self.separator2, style.text,
    #dv.doc.lines, " lines",
    self.separator,
    dv.doc.crlf and "CRLF" or "LF"
  }
end


---The predefined status bar items displayed when a command view is active.
---@return table left
---@return table right
function StatusView:get_command_items()
  return {}, {
    style.icon_font, "g",
    style.font, style.dim, self.separator2,
    #core.docs, style.text, " / ",
    #core.project_files, " files"
  }
end


---Helper function to copy a styled text table into another.
---@param t1 StatusView.styledtext
---@param t2 StatusView.styledtext
local function table_add(t1, t2)
  for i, value in ipairs(t2) do
    table.insert(t1, value)
  end
end


---Get the styled text that will be displayed on the left side or
---right side of the status bar checking their predicates and performing
---positioning calculations for proper functioning of tooltips and clicks.
---@return StatusView.styledtext left
---@return StatusView.styledtext right
function StatusView:get_items_from_list()
  local left, right = {}, {}

  local x = self:get_content_offset()

  local rx = x + self.size.x
  local lx = x + style.padding.x
  local rw, lw = 0, 0

  ---@class items
  ---@field item StatusView.item
  local items = {}

  -- calculate left and right width
  for _, item in ipairs(self.items) do
    if item.predicate(self) then
      item.active = true

      local litems, ritems = item.items(self)

      if #litems > 0 then
        item.lw = draw_items(self, litems, 0, 0, text_width)
        item.lx = lx
        lw = lw + item.lw
        lx = lx + item.lw
      end

      if #ritems > 0 then
        item.rw = draw_items(self, ritems, 0, 0, text_width)
        item.rx = rx
        rw = rw + item.rw
        rx = rx + item.rw
      end

      if #litems > 0 or #ritems > 0 then
        table.insert(items, {
          item = item,
          left = litems,
          right = ritems
        })
      end
    else
      item.active = false
    end
  end

  -- load deprecated items for compatibility
  local dleft, dright = self:get_items(true)
  if #dright > 0 then
    rw = rw + draw_items(self, dright, 0, 0, text_width)
  end

  rw = rw < (self.size.x / 2) and rw or self.size.x / 2

  for _, item in ipairs(items) do
    if #item.left > 0 then
      table_add(left, item.left)
    end
    if #item.right > 0 then
      -- re-calculate x position now that we have the total width
      item.item.rx = item.item.rx - rw - style.padding.x
      table_add(right, item.right)
    end
  end

  table_add(left, dleft)
  table_add(right, dright)

  return left, right
end


---Older method of retrieving the status bar items and which is now
---deprecated in favour of core.status_view:add_item().
---@deprecated
---@param nowarn boolean
---@return table left
---@return table right
function StatusView:get_items(nowarn)
  if not nowarn and not self.get_items_warn then
    core.error(
      "Overriding StatusView:get_items() is deprecated, "
      .. "use core.status_view:add_item() instead."
    )
    self.get_items_warn = true
  end
  return {}, {}
end


function StatusView:on_mouse_pressed()
  core.set_active_view(core.last_active_view)
  if system.get_time() < self.message_timeout
  and not core.active_view:is(LogView) then
    command.perform "core:open-log"
  end
  return true
end


function StatusView:on_mouse_moved(x, y, dx, dy)
  StatusView.super.on_mouse_moved(self, x, y, dx, dy)

  if y < self.position.y then self.hovered_item = {} return end

  for _, item in ipairs(self.items) do
    if item.onclick and item.active then
      if
        (item.lx and x > item.lx and (item.lx + item.lw) > x)
        or
        (item.rx and x > item.rx and (item.rx + item.rw) > x)
      then
        self.pointer.x = x
        self.pointer.y = y
        if self.hovered_item ~= item then
          self.hovered_item = item
        end
        return
      end
    end
  end
  self.hovered_item = {}
end


function StatusView:on_mouse_released(button, x, y)
  StatusView.super.on_mouse_released(self, button, x, y)

  if y < self.position.y or not self.hovered_item.onclick then return end

  local item = self.hovered_item
  if
    (item.lx and x > item.lx and (item.lx + item.lw) > x)
    or
    (item.rx and x > item.rx and (item.rx + item.rw) > x)
  then
    self.hovered_item.onclick(button, x, y)
  end
end


function StatusView:update()
  self.size.y = style.font:get_height() + style.padding.y * 2

  if system.get_time() < self.message_timeout then
    self.scroll.to.y = self.size.y
  else
    self.scroll.to.y = 0
  end

  StatusView.super.update(self)
end


function StatusView:draw()
  self:draw_background(style.background2)

  if self.message then
    self:draw_items(self.message, false, self.size.y)
  end

  if self.tooltip_mode then
    self:draw_items(self.tooltip)
  else
    local left, right = self:get_items_from_list()
    self:draw_items(left)
    self:draw_items(right, true)
    if self.hovered_item.tooltip then
      self:draw_item_tooltip(self.hovered_item)
    end
  end
end


return StatusView
