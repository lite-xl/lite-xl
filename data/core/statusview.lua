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

---A status bar implementation for lite, check core.status_view.
---@class StatusView : View
---@field private items StatusView.Item[]
---@field private active_items StatusView.Item[]
---@field private hovered_item StatusView.Item
---@field private message_timeout number
---@field private message StatusView.styledtext
---@field private tooltip_mode boolean
---@field private tooltip StatusView.styledtext
---@field private left_width number
---@field private right_width number
---@field private r_left_width number
---@field private r_right_width number
---@field private left_xoffset number
---@field private right_xoffset number
---@field private dragged_panel '"left"' | '"right"'
---@field private hovered_panel '"left"' | '"right"'
---@field private hide_messages boolean
local StatusView = View:extend()

---Space separator
---@type string
StatusView.separator  = "      "

---Pipe separator
---@type string
StatusView.separator2 = "   |   "

---@alias StatusView.Item.separator
---|>'StatusView.separator' # Space separator
---| 'StatusView.separator2' # Pipe separator

---@alias StatusView.Item.predicate fun():boolean
---@alias StatusView.Item.onclick fun(button: string, x: number, y: number)
---@alias StatusView.Item.getitem fun():StatusView.styledtext,StatusView.styledtext
---@alias StatusView.Item.ondraw fun(x, y, h, calc_only: boolean):number

---@class StatusView.Item : Object
---@field name string
---@field predicate StatusView.Item.predicate
---@field alignment StatusView.Item.alignment
---@field tooltip string | nil
---@field command string | nil @Command to perform when the item is clicked.
---@field on_click StatusView.Item.onclick | nil @Function called when item is clicked and no command is set.
---@field on_draw StatusView.Item.ondraw | nil @Custom drawing that when passed calc true should return the needed width for drawing and when false should draw.
---@field background_color renderer.color | nil
---@field visible boolean
---@field separator StatusView.Item.separator
---@field private active boolean
---@field private x number
---@field private w number
---@field private deprecated boolean
---@field private cached_item StatusView.styledtext
StatusView.Item = Object:extend()

---Flag to tell the item should me aligned on left side of status bar.
---@type number
StatusView.Item.LEFT = 1

---Flag to tell the item should me aligned on right side of status bar.
---@type number
StatusView.Item.RIGHT = 2

---@alias StatusView.Item.alignment
---|>'StatusView.Item.LEFT'
---| 'StatusView.Item.RIGHT'

---Constructor
---@param predicate string | table | StatusView.Item.predicate
---@param name string
---@param alignment StatusView.Item.alignment
---@param command string | StatusView.Item.onclick
---@param tooltip? string | nil
function StatusView.Item:new(predicate, name, alignment, command, tooltip)
  self:set_predicate(predicate)
  self.name = name
  self.alignment = alignment or StatusView.Item.LEFT
  self.command = type(command) == "string" and command or nil
  self.tooltip = tooltip or ""
  self.on_click = type(command) == "function" and command or nil
  self.on_draw = nil
  self.background_color = nil
  self.visible = true
  self.active = false
  self.x = 0
  self.w = 0
  self.separator = StatusView.separator
end

---Called by the status bar each time that the item needs to be rendered,
---if on_draw() is set this function is obviated.
---@return StatusView.styledtext
function StatusView.Item:get_item() return {} end

---Do not show the item on the status bar.
function StatusView.Item:hide() self.visible = false end

---Show the item on the status bar.
function StatusView.Item:show() self.visible = true end

---Function assiged by default when user provides a nil predicate.
local function predicate_always_true() return true end

---A condition to evaluate if the item should be displayed. If a string
---is given it is treated as a require import that should return a valid object
---which is checked against the current active view, the sames applies if a
---table is given. A function that returns a boolean can be used instead to
---perform a custom evaluation, setting to nil means always evaluates to true.
---@param predicate string | table | StatusView.Item.predicate
function StatusView.Item:set_predicate(predicate)
  predicate = predicate or predicate_always_true
  if type(predicate) == "string" then
    predicate = require(predicate)
  end
  if type(predicate) == "table" then
    local class = predicate
    predicate = function() return core.active_view:is(class) end
  end
  self.predicate = predicate
end


---Predicated used on the default docview widgets.
---@return boolean
local function predicate_docview()
  return  core.active_view:is(DocView)
    and not core.active_view:is(CommandView)
end


---Constructor
function StatusView:new()
  StatusView.super.new(self)
  self.message_timeout = 0
  self.message = {}
  self.tooltip_mode = false
  self.tooltip = {}
  self.items = {}
  self.active_items = {}
  self.hovered_item = {}
  self.pointer = {x = 0, y = 0}
  self.left_width = 0
  self.right_width = 0
  self.r_left_width = 0
  self.r_right_width = 0
  self.left_xoffset = 0
  self.right_xoffset = 0
  self.dragged_panel = ""
  self.hovered_panel = ""
  self.hide_messages = false

  self:register_docview_items()
  self:register_command_items()
end

---The predefined status bar items displayed when a document view is active.
function StatusView:register_docview_items()
  if self:get_item("doc:file") then return end

  self:add_item(
    predicate_docview,
    "doc:file",
    StatusView.Item.LEFT,
    function()
      local dv = core.active_view
      return {
        dv.doc:is_dirty() and style.accent or style.text, style.icon_font, "f",
        style.dim, style.font, self.separator2, style.text,
        dv.doc.filename and style.text or style.dim, dv.doc:get_name()
      }
    end
  )

  self:add_item(
    predicate_docview,
    "doc:position",
    StatusView.Item.LEFT,
    function()
      local dv = core.active_view
      local line, col = dv.doc:get_selection()
      return {
        line,
        ":",
        col > config.line_limit and style.accent or style.text, col,
        style.text,
        self.separator,
        string.format("%.f%%", line / #dv.doc.lines * 100)
      }
    end,
    "doc:go-to-line"
  ).tooltip = "line : column"

  self:add_item(
    predicate_docview,
    "doc:indentation",
    StatusView.Item.RIGHT,
    function()
      local dv = core.active_view
      local indent_type, indent_size, indent_confirmed = dv.doc:get_indent_info()
      local indent_label = (indent_type == "hard") and "tabs: " or "spaces: "
      return {
        style.text, indent_label, indent_size
      }
    end,
    function(button, x, y)
      if button == "left" then
        command.perform "indent:set-file-indent-size"
      elseif button == "right" then
        command.perform "indent:set-file-indent-type"
      end
    end
  ).separator = self.separator2

  self:add_item(
    predicate_docview,
    "doc:lines",
    StatusView.Item.RIGHT,
    function()
      local dv = core.active_view
      return {
        style.text,
        style.icon_font, "g",
        style.font, style.dim, self.separator2, style.text,
        #dv.doc.lines, " lines",
      }
    end
  ).separator = self.separator2

  self:add_item(
    predicate_docview,
    "doc:line-ending",
    StatusView.Item.RIGHT,
    function()
      local dv = core.active_view
      return {
        dv.doc.crlf and "CRLF" or "LF"
      }
    end,
    "doc:toggle-line-ending"
  )
end


---The predefined status bar items displayed when a command view is active.
function StatusView:register_command_items()
  if self:get_item("command:files") then return end

  self:add_item(
    "core.commandview",
    "command:files",
    StatusView.Item.RIGHT,
    function()
      return {
        style.icon_font, "g",
        style.font, style.dim, self.separator2,
        #core.docs, style.text, " / ",
        #core.project_files, " files"
      }
    end
  )
end


---Adds an item to be rendered in the status bar.
---@param predicate string | table | StatusView.Item.predicate :
---A condition to evaluate if the item should be displayed. If a string
---is given it is treated as a require import that should return a valid object
---which is checked against the current active view, the sames applies if a
---table is given. A function that returns a boolean can be used instead to
---perform a custom evaluation, setting to nil means always evaluates to true.
---@param name string A unique name to identify the item on the status bar.
---@param alignment StatusView.Item.alignment
---@param getitem StatusView.Item.getitem :
---A function that should return a StatusView.styledtext element,
---returning empty table is allowed.
---@param command? string | StatusView.Item.onclick :
---The name of a valid registered command or a callback function to execute
---when the item is clicked.
---@param pos? integer :
---The position in which to insert the given item on the internal table,
---a value of -1 inserts the item at the end which is the default. A value
---of 1 will insert the item at the beggining.
---@param tooltip? string Displayed when mouse hovers the item
---@return StatusView.Item
function StatusView:add_item(predicate, name, alignment, getitem, command, pos, tooltip)
  assert(self:get_item(name) == nil, "status item already exists: " .. name)
  ---@type StatusView.Item
  local item = StatusView.Item(predicate, name, alignment, command, tooltip)
  item.get_item = getitem
  pos = type(pos) == "nil" and -1 or tonumber(pos)
  if pos == -1 then
    table.insert(self.items, item)
  else
    table.insert(self.items, math.abs(pos), item)
  end
  return item
end


---Get an item associated object or nil if not found.
---@param name string
---@return StatusView.Item | nil
function StatusView:get_item(name)
  for _, item in ipairs(self.items) do
    if item.name == name then return item end
  end
  return nil
end


---Get a list of items.
---@param alignment? StatusView.Item.alignment
---@return StatusView.Item[]
function StatusView:get_items_list(alignment)
  if alignment then
    local items = {}
    for _, item in ipairs(self.items) do
      if item.alignment == alignment then
        table.insert(items, item)
      end
    end
    return items
  end
  return self.items
end


---Hides the given items from the status view or all if no names given.
---@param names table<integer, string> | string | nil
function StatusView:hide_items(names)
  if type(names) == "string" then
    names = {names}
  end
  if not names then
    for _, item in ipairs(self.items) do
      item:hide()
    end
    return
  end
  for _, name in ipairs(names) do
    local item = self:get_item(name)
    if item then item:hide() end
  end
end


---Shows the given items from the status view or all if no names given.
---@param names table<integer, string> | string | nil
function StatusView:show_items(names)
  if type(names) == "string" then
    names = {names}
  end
  if not names then
    for _, item in ipairs(self.items) do
      item:show()
    end
    return
  end
  for _, name in ipairs(names) do
    local item = self:get_item(name)
    if item then item:show() end
  end
end


---Shows a message for a predefined amount of time.
---@param icon string
---@param icon_color renderer.color
---@param text string
function StatusView:show_message(icon, icon_color, text)
  if self.hide_messages then return end
  self.message = {
    icon_color, style.icon_font, icon,
    style.dim, style.font, StatusView.separator2, style.text, text
  }
  self.message_timeout = system.get_time() + config.message_timeout
end


---Enable or disable system wide messages on the status bar.
---@param enable boolean
function StatusView:display_messages(enable)
  self.hide_messages = not enable
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
function StatusView:draw_items(items, right_align, xoffset, yoffset)
  local x, y = self:get_content_offset()
  x = x + (xoffset or 0)
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
---@param item StatusView.Item
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
      x + style.padding.x,
      self.position.y - h - (style.padding.y * 2),
      w + (style.padding.x * 2),
      h + (style.padding.y * 2),
      style.background3
    )

    renderer.draw_text(
      style.font,
      text,
      x + (style.padding.x * 2),
      self.position.y - h - style.padding.y,
      style.text
    )
  end)
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
  return {"{:dummy:}"}, {"{:dummy:}"}
end


---Helper function to copy a styled text table into another.
---@param t1 StatusView.styledtext
---@param t2 StatusView.styledtext
local function table_add(t1, t2)
  for i, value in ipairs(t2) do
    table.insert(t1, value)
  end
end


---Helper function to merge deprecated items to a temp items table.
---@param destination table
---@param items StatusView.styledtext
---@param alignment StatusView.Item.alignment
local function merge_deprecated_items(destination, items, alignment)
  local start = true
  local items_start, items_end = {}, {}
  for i, value in ipairs(items) do
    if value ~= "{:dummy:}" then
      if start then
        table.insert(items_start, i, value)
      else
        table.insert(items_end, value)
      end
    else
      start = false
    end
  end

  local position = alignment == StatusView.Item.LEFT and "left" or "right"

  local item_start = StatusView.Item(
    predicate_always_true,
    "deprecated:"..position.."-start",
    alignment
  )
  item_start.get_item = items_start

  local item_end = StatusView.Item(
    predicate_always_true,
    "deprecated:"..position.."-end",
    alignment
  )
  item_end.get_item = items_end

  table.insert(destination, 1, item_start)
  table.insert(destination, item_end)
end


---@param self StatusView
---@param styled_text StatusView.styledtext
---@param separator string
local function add_spacing(self, styled_text, separator)
  if
    Object.is(styled_text[1], renderer.font)
    or
    (
      styled_text[2] ~= self.separator
      or
      styled_text[2] ~= self.separator2
    )
  then
    if separator == self.separator2 then
      table.insert(styled_text, 1, style.dim)
    else
      table.insert(styled_text, 1, style.text)
    end
    table.insert(styled_text, 2, separator)
  end
end


---@param self StatusView
---@param styled_text StatusView.styledtext
local function remove_spacing(self, styled_text)
  if
    not Object.is(styled_text[1], renderer.font)
    and
    type(styled_text[1]) == "table"
    and
    (
      styled_text[2] == self.separator
      or
      styled_text[2] == self.separator2
    )
  then
    table.remove(styled_text, 1)
    table.remove(styled_text, 1)
  end

  if
    not Object.is(styled_text[#styled_text-1], renderer.font)
    and
    type(styled_text[#styled_text-1]) == "table"
    and
    (
      styled_text[#styled_text] == self.separator
      or
      styled_text[#styled_text] == self.separator2
    )
  then
    table.remove(styled_text, #styled_text)
    table.remove(styled_text, #styled_text)
  end
end


---Get the styled text that will be displayed on the left side or
---right side of the status bar checking their predicates and performing
---positioning calculations for proper functioning of tooltips and clicks.
---@return StatusView.styledtext left
---@return StatusView.styledtext right
function StatusView:update_active_items()
  local left, right = {}, {}

  local x = self:get_content_offset()

  local rx = x + self.size.x
  local lx = x
  local rw, lw = 0, 0

  self.active_items = {}

  ---@type StatusView.Item[]
  local combined_items = {}
  table_add(combined_items, self.items)

  -- load deprecated items for compatibility
  local dleft, dright = self:get_items(true)
  merge_deprecated_items(combined_items, dleft, StatusView.Item.LEFT)
  merge_deprecated_items(combined_items, dright, StatusView.Item.RIGHT)

  local lfirst, rfirst = true, true

  -- calculate left and right width
  for _, item in ipairs(combined_items) do
    item.cached_item = {}
    if item.visible and item.predicate(self) then
      local styled_text = type(item.get_item) == "function"
        and item.get_item(self) or item.get_item

      if #styled_text > 0 then
        remove_spacing(self, styled_text)
      end

      if #styled_text > 0 or item.on_draw then
        item.active = true
        if item.alignment == StatusView.Item.LEFT then
          if not lfirst then
            add_spacing(self, styled_text, item.separator, true)
          else
            lfirst = false
          end
          item.w = item.on_draw and
            item.on_draw(lx, self.position.y, self.size.y, true)
            or
            draw_items(self, styled_text, 0, 0, text_width)
          item.x = lx
          lw = lw + item.w
          lx = lx + item.w
        else
          if not rfirst then
            add_spacing(self, styled_text, item.separator, true)
          else
            rfirst = false
          end
          item.w = item.on_draw and
            item.on_draw(rx, self.position.y, self.size.y, true)
            or
            draw_items(self, styled_text, 0, 0, text_width)
          item.x = rx
          rw = rw + item.w
          rx = rx + item.w
        end
        item.cached_item = styled_text
        table.insert(self.active_items, item)
      else
        item.active = false
      end
    else
      item.active = false
    end
  end

  self.r_left_width, self.r_right_width = lw, rw

  -- try to calc best size for left and right
  if lw + rw + (style.padding.x * 4) > self.size.x then
    if lw + (style.padding.x * 2) < self.size.x / 2 then
      rw = self.size.x - lw  - (style.padding.x * 3)
      if rw > self.r_right_width then
        lw = lw + (rw - self.r_right_width)
        rw = self.r_right_width
      end
    elseif rw + (style.padding.x * 2) < self.size.x / 2 then
      lw = self.size.x - rw  - (style.padding.x * 3)
    else
      lw = self.size.x / 2 - (style.padding.x + style.padding.x / 2)
      rw = self.size.x / 2 - (style.padding.x + style.padding.x / 2)
    end
  else
    self.left_xoffset = 0
    self.right_xoffset = 0
  end

  self.left_width, self.right_width = lw, rw

  for _, item in ipairs(self.active_items) do
    if item.alignment == StatusView.Item.RIGHT then
      -- re-calculate x position now that we have the total width
      item.x = item.x - rw - (style.padding.x * 2)
    end
  end
end


---Drag the given panel if possible.
---@param panel '"left"' | '"right"'
---@param dx number
function StatusView:drag_panel(panel, dx)
  if panel == "left" and self.r_left_width > self.left_width then
    local nonvisible_w = self.r_left_width - self.left_width
    local new_offset = self.left_xoffset + dx
    if new_offset >= 0 - nonvisible_w and new_offset <= 0 then
      self.left_xoffset = new_offset
    elseif dx < 0 then
      self.left_xoffset = 0 - nonvisible_w
    else
      self.left_xoffset = 0
    end
  elseif panel == "right" and self.r_right_width > self.right_width then
    local nonvisible_w = self.r_right_width - self.right_width
    local new_offset = self.right_xoffset + dx
    if new_offset >= 0 - nonvisible_w and new_offset <= 0 then
      self.right_xoffset = new_offset
    elseif dx < 0 then
      self.right_xoffset = 0 - nonvisible_w
    else
      self.right_xoffset = 0
    end
  end
end


---Return the currently hovered panel or empty string if none.
---@param x number
---@param y number
---@return string
function StatusView:get_hovered_panel(x, y)
  if y >= self.position.y and x <= self.left_width + style.padding.x then
    return "left"
  else
    return "right"
  end
  return ""
end


---@param item StatusView.Item
---@return number x
---@return number w
function StatusView:get_item_visible_area(item)
  local item_ox = item.alignment == StatusView.Item.LEFT and
    self.left_xoffset or self.right_xoffset

  local item_x = item_ox + item.x + style.padding.x
  local item_w = item.w

  if item.alignment == StatusView.Item.LEFT then
    if self.left_width - item_x > 0 and self.left_width - item_x < item.w then
      item_w = (self.left_width + style.padding.x) - item_x
    elseif self.left_width - item_x < 0 then
      item_x = 0
      item_w = 0
    end
  else
    local rx = self.size.x - self.right_width - style.padding.x
    if item_x < rx then
      if item_x + item.w > rx then
        item_x = rx
        item_w = (item_x + item.w) - rx
      else
        item_x = 0
        item_w = 0
      end
    end
  end

  return item_x, item_w
end



function StatusView:on_mouse_pressed(button, x, y, clicks)
  core.set_active_view(core.last_active_view)
  if
    system.get_time() < self.message_timeout
    and
    not core.active_view:is(LogView)
  then
    command.perform "core:open-log"
  else
    if y >= self.position.y and button == "left" and clicks == 1 then
      self.position.dx = x
      if self.r_left_width > self.left_width then
        self.dragged_panel = self:get_hovered_panel(x, y)
        self.cursor = "hand"
      end
    end
  end
  return true
end


function StatusView:on_mouse_moved(x, y, dx, dy)
  StatusView.super.on_mouse_moved(self, x, y, dx, dy)

  self.hovered_panel = self:get_hovered_panel(x, y)

  if self.dragged_panel ~= "" then
    self:drag_panel(self.dragged_panel, dx)
    return
  end

  if y < self.position.y or system.get_time() <= self.message_timeout then
    self.cursor = "arrow"
    self.hovered_item = {}
    return
  end

  for _, item in ipairs(self.items) do
    if
      item.visible and item.active
      and
      (item.command or item.on_click or item.tooltip ~= "")
    then
      local item_x, item_w = self:get_item_visible_area(item)

      if x > item_x and (item_x + item_w) > x then
        self.pointer.x = x
        self.pointer.y = y
        if self.hovered_item ~= item then
          self.hovered_item = item
        end
        if item.command or item.on_click then
          self.cursor = "hand"
        end
        return
      end
    end
  end
  self.cursor = "arrow"
  self.hovered_item = {}
end


function StatusView:on_mouse_released(button, x, y)
  StatusView.super.on_mouse_released(self, button, x, y)

  if self.dragged_panel ~= "" then
    self.dragged_panel = ""
    self.cursor = "arrow"
    if self.position.dx ~= x then
      return
    end
  end

  if y < self.position.y or not self.hovered_item.active then return end

  local item = self.hovered_item
  local item_x, item_w = self:get_item_visible_area(item)

  if x > item_x and (item_x + item_w) > x then
    if item.command then
      command.perform(item.command)
    elseif item.on_click then
      item.on_click(button, x, y)
    end
  end
end


function StatusView:on_mouse_wheel(y)
  self:drag_panel(self.hovered_panel, y * self.left_width / 10)
end


function StatusView:update()
  self.size.y = style.font:get_height() + style.padding.y * 2

  if system.get_time() < self.message_timeout then
    self.scroll.to.y = self.size.y
  else
    self.scroll.to.y = 0
  end

  StatusView.super.update(self)

  self:update_active_items()
end


function StatusView:draw()
  self:draw_background(style.background2)

  if self.message and system.get_time() <= self.message_timeout then
    self:draw_items(self.message, false, 0, self.size.y)
  elseif self.tooltip_mode then
    self:draw_items(self.tooltip)
  else
    if #self.active_items > 0 then
      --- draw left pane
      core.push_clip_rect(
        0, self.position.y,
        self.left_width + style.padding.x, self.size.y
      )
      for _, item in ipairs(self.active_items) do
        local item_x = self.left_xoffset + item.x + style.padding.x
        if item.alignment == StatusView.Item.LEFT then
          if type(item.background_color) == "table" then
            renderer.draw_rect(
              item_x, self.position.y,
              item.w, self.size.y, item.background_color
            )
          end
          if item.on_draw then
            core.push_clip_rect(item_x, self.position.y, item.w, self.size.y)
            item.on_draw(item_x, self.position.y, self.size.y)
            core.pop_clip_rect()
          else
            self:draw_items(item.cached_item, false, item_x - style.padding.x)
          end
        end
      end
      core.pop_clip_rect()

      --- draw right pane
      core.push_clip_rect(
        self.size.x - (self.right_width + style.padding.x), self.position.y,
        self.right_width + style.padding.x, self.size.y
      )
      for _, item in ipairs(self.active_items) do
        local item_x = self.right_xoffset + item.x + style.padding.x
        if item.alignment == StatusView.Item.RIGHT then
          if type(item.background_color) == "table" then
            renderer.draw_rect(
              item_x, self.position.y,
              item.w, self.size.y, item.background_color
            )
          end
          if item.on_draw then
            core.push_clip_rect(item_x, self.position.y, item.w, self.size.y)
            item.on_draw(item_x, self.position.y, self.size.y)
            core.pop_clip_rect()
          else
            self:draw_items(item.cached_item, false, item_x - style.padding.x)
          end
        end
      end
      core.pop_clip_rect()

      -- draw tooltip
      if self.hovered_item.tooltip ~= "" and self.hovered_item.active then
        self:draw_item_tooltip(self.hovered_item)
      end
    end
  end
end


return StatusView
