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


---@alias core.statusview.styledtext table<integer, renderer.font|renderer.color|string>
---@alias core.statusview.position '"left"' | '"right"'

---A status bar implementation for lite, check core.status_view.
---@class core.statusview : core.view
---@field super core.view
---@field items core.statusview.item[]
---@field active_items core.statusview.item[]
---@field hovered_item core.statusview.item
---@field message_timeout number
---@field message core.statusview.styledtext
---@field tooltip_mode boolean
---@field tooltip core.statusview.styledtext
---@field left_width number
---@field right_width number
---@field r_left_width number
---@field r_right_width number
---@field left_xoffset number
---@field right_xoffset number
---@field dragged_panel '""' | core.statusview.position
---@field hovered_panel '""' | core.statusview.position
---@field hide_messages boolean
local StatusView = View:extend()

function StatusView:__tostring() return "StatusView" end

---Space separator
---@type string
StatusView.separator  = "      "

---Pipe separator
---@type string
StatusView.separator2 = "   |   "

---@alias core.statusview.item.separator
---|>`StatusView.separator`
---| `StatusView.separator2`

---@alias core.statusview.item.predicate fun():boolean
---@alias core.statusview.item.onclick fun(button: string, x: number, y: number)
---@alias core.statusview.item.get_item fun(self: core.statusview.item):core.statusview.styledtext?,core.statusview.styledtext?
---@alias core.statusview.item.ondraw fun(x, y, h, hovered: boolean, calc_only?: boolean):number

---@class core.statusview.item : core.object
---@field name string
---@field predicate core.statusview.item.predicate
---@field alignment core.statusview.item.alignment
---@field tooltip string
---@field command string | nil @Command to perform when the item is clicked.
---Function called when item is clicked and no command is set.
---@field on_click core.statusview.item.onclick | nil
---Custom drawing that when passed calc true should return the needed width for
---drawing and when false should draw.
---@field on_draw core.statusview.item.ondraw | nil
---@field background_color renderer.color | nil
---@field background_color_hover renderer.color | nil
---@field visible boolean
---@field separator core.statusview.item.separator
---@field active boolean
---@field x number
---@field w number
---@field cached_item core.statusview.styledtext
local StatusViewItem = Object:extend()

function StatusViewItem:__tostring() return "StatusViewItem" end

---Available StatusViewItem options.
---@class core.statusview.item.options : table
---A condition to evaluate if the item should be displayed. If a string
---is given it is treated as a require import that should return a valid object
---which is checked against the current active view, the sames applies if a
---table is given. A function that returns a boolean can be used instead to
---perform a custom evaluation, setting to nil means always evaluates to true.
---@field predicate string | table | core.statusview.item.predicate
---A unique name to identify the item on the status bar.
---@field name string @A unique name to identify the item on the status bar.
---@field alignment core.statusview.item.alignment
---A function that should return a core.statusview.styledtext element,
---returning an empty table is allowed.
---@field get_item core.statusview.item.get_item
---The name of a valid registered command or a callback function to execute
---when the item is clicked.
---@field command string | core.statusview.item.onclick | nil
---The position in which to insert the given item on the internal table,
---a value of -1 inserts the item at the end which is the default. A value
---of 1 will insert the item at the beggining.
---@field position? integer
---@field tooltip? string @Text displayed when mouse hovers the item.
---@field visible boolean @Flag to show or hide the item
---The type of separator rendered to the right of the item if another item
---follows it.
---@field separator? core.statusview.item.separator

---Flag to tell the item should me aligned on left side of status bar.
---@type integer
StatusViewItem.LEFT = 1

---Flag to tell the item should me aligned on right side of status bar.
---@type integer
StatusViewItem.RIGHT = 2

---@alias core.statusview.item.alignment
---|>`StatusView.Item.LEFT`
---| `StatusView.Item.RIGHT`

---Constructor
---@param options core.statusview.item.options
function StatusViewItem:new(options)
  self:set_predicate(options.predicate)
  self.name = options.name
  self.alignment = options.alignment or StatusView.Item.LEFT
  self.command = type(options.command) == "string" and options.command or nil
  self.tooltip = options.tooltip or ""
  self.on_click = type(options.command) == "function" and options.command or nil
  self.on_draw = nil
  self.background_color = nil
  self.background_color_hover = nil
  self.visible = options.visible == nil and true or options.visible
  self.active = false
  self.x = 0
  self.w = 0
  self.separator = options.separator or StatusView.separator
  self.get_item = options.get_item
end

---Called by the status bar each time that the item needs to be rendered,
---if on_draw() is set this function is obviated.
---@return core.statusview.styledtext
function StatusViewItem:get_item() return {} end

---Do not show the item on the status bar.
function StatusViewItem:hide() self.visible = false end

---Show the item on the status bar.
function StatusViewItem:show() self.visible = true end

---A condition to evaluate if the item should be displayed. If a string
---is given it is treated as a require import that should return a valid object
---which is checked against the current active view, the sames applies if a
---table is given. A function that returns a boolean can be used instead to
---perform a custom evaluation, setting to nil means always evaluates to true.
---@param predicate string | table | core.statusview.item.predicate
function StatusViewItem:set_predicate(predicate)
  self.predicate = command.generate_predicate(predicate)
end

---@type core.statusview.item
StatusView.Item = StatusViewItem


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
  self.visible = true

  self:register_docview_items()
  self:register_command_items()
end

---The predefined status bar items displayed when a document view is active.
function StatusView:register_docview_items()
  if self:get_item("doc:file") then return end

  self:add_item({
    predicate = predicate_docview,
    name = "doc:file",
    alignment = StatusView.Item.LEFT,
    get_item = function()
      local dv = core.active_view
      return {
        dv.doc:is_dirty() and style.accent or style.text, style.icon_font, "f",
        style.dim, style.font, self.separator2, style.text,
        dv.doc.filename and style.text or style.dim, common.home_encode(dv.doc:get_name())
      }
    end
  })

  self:add_item({
    predicate = predicate_docview,
    name = "doc:position",
    alignment = StatusView.Item.LEFT,
    get_item = function()
      local dv = core.active_view
      local line, col = dv.doc:get_selection()
      local _, indent_size = dv.doc:get_indent_info()
      -- Calculating tabs when the doc is using the "hard" indent type.
      local ntabs = 0
      local last_idx = 0
      while last_idx < col do
        local s, e = string.find(dv.doc.lines[line], "\t", last_idx, true)
        if s and s < col then
          ntabs = ntabs + 1
          last_idx = e + 1
        else
          break
        end
      end
      col = col + ntabs * (indent_size - 1)
      return {
        style.text, line, ":",
        col > config.line_limit and style.accent or style.text, col,
        style.text,
        self.separator,
        string.format("%.f%%", line / #dv.doc.lines * 100)
      }
    end,
    command = "doc:go-to-line",
    tooltip = "line : column"
  })

  self:add_item({
    predicate = predicate_docview,
    name = "doc:indentation",
    alignment = StatusView.Item.RIGHT,
    get_item = function()
      local dv = core.active_view
      local indent_type, indent_size, indent_confirmed = dv.doc:get_indent_info()
      local indent_label = (indent_type == "hard") and "tabs: " or "spaces: "
      return {
        style.text, indent_label, indent_size,
        indent_confirmed and "" or "*"
      }
    end,
    command = function(button, x, y)
      if button == "left" then
        command.perform "indent:set-file-indent-size"
      elseif button == "right" then
        command.perform "indent:set-file-indent-type"
      end
    end,
    separator = self.separator2
  })

  self:add_item({
    predicate = predicate_docview,
    name = "doc:lines",
    alignment = StatusView.Item.RIGHT,
    get_item = function()
      local dv = core.active_view
      return {
        style.text,
        style.icon_font, "g",
        style.font, style.dim, self.separator2,
        style.text, #dv.doc.lines, " lines",
      }
    end,
    separator = self.separator2
  })

  self:add_item({
    predicate = predicate_docview,
    name = "doc:line-ending",
    alignment = StatusView.Item.RIGHT,
    get_item = function()
      local dv = core.active_view
      return {
        style.text, dv.doc.crlf and "CRLF" or "LF"
      }
    end,
    command = "doc:toggle-line-ending"
  })
end


---The predefined status bar items displayed when a command view is active.
function StatusView:register_command_items()
  if self:get_item("command:files") then return end

  self:add_item({
    predicate = "core.commandview",
    name = "command:files",
    alignment = StatusView.Item.RIGHT,
    get_item = function()
      return {
        style.icon_font, "g",
        style.font, style.dim, self.separator2,
        style.text, #core.docs, style.text, " / ",
        #core.project_files, " files"
      }
    end
  })
end


---Set a position to the best match according to total available items.
---@param self core.statusview
---@param position integer
---@param alignment core.statusview.item.alignment
---@return integer position
local function normalize_position(self, position, alignment)
  local offset = 0
  local items_count = 0
  local left = self:get_items_list(1)
  local right = self:get_items_list(2)
  if alignment == 2 then
    items_count = #right
    offset = #left
  else
    items_count = #left
  end
  if position == 0 then
    position = offset +  1
  elseif position < 0 then
    position = offset + items_count + (position + 2)
  else
    position = offset + position
  end
  if position < 1 then
    position = offset + 1
  elseif position > #left + #right then
    position = offset + items_count + 1
  end
  return position
end


---Adds an item to be rendered in the status bar.
---@param options core.statusview.item.options
---@return core.statusview.item
function StatusView:add_item(options)
  assert(self:get_item(options.name) == nil, "status item already exists: " .. options.name)
  ---@type core.statusview.item
  local item = StatusView.Item(options)
  table.insert(self.items, normalize_position(self, options.position or -1, options.alignment), item)
  return item
end


---Get an item object associated to a name or nil if not found.
---@param name string
---@return core.statusview.item | nil
function StatusView:get_item(name)
  for _, item in ipairs(self.items) do
    if item.name == name then return item end
  end
  return nil
end


---Get a list of items.
---@param alignment? core.statusview.item.alignment
---@return core.statusview.item[]
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


---Move an item to a different position.
---@param name string
---@param position integer Can be negative value to position in reverse order
---@param alignment? core.statusview.item.alignment
---@return boolean moved
function StatusView:move_item(name, position, alignment)
  assert(name, "no name provided")
  assert(position, "no position provided")
  local item = nil
  for pos, it in ipairs(self.items) do
    if it.name == name then
      item = table.remove(self.items, pos)
      break
    end
  end
  if item then
    if alignment then
      item.alignment = alignment
    end
    position = normalize_position(self, position, item.alignment)
    table.insert(self.items, position, item)
    return true
  end
  return false
end


---Remove an item from the status view.
---@param name string
---@return core.statusview.item removed_item
function StatusView:remove_item(name)
  local item = nil
  for pos, it in ipairs(self.items) do
    if it.name == name then
      item = table.remove(self.items, pos)
      break
    end
  end
  return item
end


---Order the items by name
---@param names table<integer, string>
function StatusView:order_items(names)
  local removed_items = {}
  for _, name in ipairs(names) do
    local item = self:remove_item(name)
    if item then table.insert(removed_items, item) end
  end

  for i, item in ipairs(removed_items) do
    table.insert(self.items, i, item)
  end
end


---Hide the status bar
function StatusView:hide()
  self.visible = false
end


---Show the status bar
function StatusView:show()
  self.visible = true
end


---Toggle the visibility of the status bar
function StatusView:toggle()
  self.visible = not self.visible
end


---Hides the given items from the status view or all if no names given.
---@param names? table<integer, string> | string
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
---@param names? table<integer, string> | string
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
  if not self.visible or self.hide_messages then return end
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
---text until core.statusview:remove_tooltip() is called.
---@param text string | core.statusview.styledtext
function StatusView:show_tooltip(text)
  self.tooltip = type(text) == "table" and text or { text }
  self.tooltip_mode = true
end


---Deactivates tooltip mode.
function StatusView:remove_tooltip()
  self.tooltip_mode = false
end


---Helper function to draw the styled text.
---@param self core.statusview
---@param items core.statusview.styledtext
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
---@param items core.statusview.styledtext
---@param right_align? boolean
---@param xoffset? number
---@param yoffset? number
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
---@param item core.statusview.item
function StatusView:draw_item_tooltip(item)
  core.root_view:defer_draw(function()
    local text = item.tooltip
    local w = style.font:get_width(text)
    local h = style.font:get_height()
    local x = self.pointer.x - (w / 2) - (style.padding.x * 2)

    if x < 0 then x = 0 end
    if (x + w + (style.padding.x * 3)) > self.size.x then
      x = self.size.x - w - (style.padding.x * 3)
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
    core.warn(
      "Overriding StatusView:get_items() is deprecated, "
      .. "use core.status_view:add_item() instead."
    )
    self.get_items_warn = true
  end
  return {"{:dummy:}"}, {"{:dummy:}"}
end


---Helper function to copy a styled text table into another.
---@param t1 core.statusview.styledtext
---@param t2 core.statusview.styledtext
local function table_add(t1, t2)
  for _, value in ipairs(t2) do
    table.insert(t1, value)
  end
end


---Helper function to merge deprecated items to a temp items table.
---@param destination table
---@param items core.statusview.styledtext
---@param alignment core.statusview.item.alignment
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

  local item_start = StatusView.Item({
    name = "deprecated:"..position.."-start",
    alignment = alignment,
    get_item = items_start
  })

  local item_end = StatusView.Item({
    name = "deprecated:"..position.."-end",
    alignment = alignment,
    get_item = items_end
  })

  table.insert(destination, 1, item_start)
  table.insert(destination, item_end)
end


---Append a space item into the given items list.
---@param self core.statusview
---@param destination core.statusview.item[]
---@param separator string
---@param alignment core.statusview.item.alignment
---@return core.statusview.item
local function add_spacing(self, destination, separator, alignment, x)
  ---@type core.statusview.item
  local space = StatusView.Item({name = "space", alignment = alignment})
  space.cached_item = separator == self.separator and {
    style.text, separator
  } or {
    style.dim, separator
  }
  space.x = x
  space.w = draw_items(self, space.cached_item, 0, 0, text_width)

  table.insert(destination, space)

  return space
end


---Remove starting and ending separators.
---@param self core.statusview
---@param styled_text core.statusview.styledtext
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


---Set the active items that will be displayed on the left or right side
---of the status bar checking their predicates and performing positioning
---calculations for proper functioning of tooltips and clicks.
function StatusView:update_active_items()
  local x = self:get_content_offset()

  local rx = x + self.size.x
  local lx = x
  local rw, lw = 0, 0

  self.active_items = {}

  ---@type core.statusview.item[]
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
    if item.visible and item:predicate() then
      local styled_text = type(item.get_item) == "function"
        and item.get_item(item) or item.get_item

      if #styled_text > 0 then
        remove_spacing(self, styled_text)
      end

      if #styled_text > 0 or item.on_draw then
        item.active = true
        local hovered = self.hovered_item == item
        if item.alignment == StatusView.Item.LEFT then
          if not lfirst then
            local space = add_spacing(
              self, self.active_items, item.separator, item.alignment, lx
            )
            lw = lw + space.w
            lx = lx + space.w
          else
            lfirst = false
          end
          item.w = item.on_draw and
            item.on_draw(lx, self.position.y, self.size.y, hovered, true)
            or
            draw_items(self, styled_text, 0, 0, text_width)
          item.x = lx
          lw = lw + item.w
          lx = lx + item.w
        else
          if not rfirst then
            local space = add_spacing(
              self, self.active_items, item.separator, item.alignment, rx
            )
            rw = rw + space.w
            rx = rx + space.w
          else
            rfirst = false
          end
          item.w = item.on_draw and
            item.on_draw(rx, self.position.y, self.size.y, hovered, true)
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
    -- reposition left and right offsets when window is resized
    if rw >= self.r_right_width then
      self.right_xoffset = 0
    elseif rw > self.right_xoffset + self.r_right_width then
      self.right_xoffset = rw - self.r_right_width
    end
    if lw >= self.r_left_width then
      self.left_xoffset = 0
    elseif lw > self.left_xoffset + self.r_left_width then
      self.left_xoffset = lw - self.r_left_width
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
---@param panel core.statusview.position
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
  end
  return "right"
end


---@param item core.statusview.item
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
  if not self.visible then return end
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
      if
        self.r_left_width > self.left_width
        or
        self.r_right_width > self.right_width
      then
        self.dragged_panel = self:get_hovered_panel(x, y)
        self.cursor = "hand"
      end
    end
  end
  return true
end


function StatusView:on_mouse_moved(x, y, dx, dy)
  if not self.visible then return end
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
  if not self.visible then return end
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


function StatusView:on_mouse_wheel(y, x)
  if not self.visible or self.hovered_panel == "" then return end
  if x ~= 0 then
    self:drag_panel(self.hovered_panel, x * self.left_width / 10)
  else
    self:drag_panel(self.hovered_panel, y * self.left_width / 10)
  end
end


function StatusView:update()
  if not self.visible and self.size.y <= 0 then
    return
  elseif not self.visible and self.size.y > 0 then
    self:move_towards(self.size, "y", 0, nil, "statusbar")
    return
  end

  local height = style.font:get_height() + style.padding.y * 2;

  if self.size.y + 1 < height then
    self:move_towards(self.size, "y", height, nil, "statusbar")
  else
    self.size.y = height
  end

  if system.get_time() < self.message_timeout then
    self.scroll.to.y = self.size.y
  else
    self.scroll.to.y = 0
  end

  StatusView.super.update(self)

  self:update_active_items()
end


---Retrieve the hover status and proper background color if any.
---@param self core.statusview
---@param item core.statusview.item
---@return boolean is_hovered
---@return renderer.color | nil color
local function get_item_bg_color(self, item)
  local hovered = self.hovered_item == item

  local item_bg = hovered
    and item.background_color_hover or item.background_color

  return hovered, item_bg
end


function StatusView:draw()
  if not self.visible and self.size.y <= 0 then return end

  self:draw_background(style.background2)

  if self.message and system.get_time() <= self.message_timeout then
    self:draw_items(self.message, false, 0, self.size.y)
  else
    if self.tooltip_mode then
      self:draw_items(self.tooltip)
    end
    if #self.active_items > 0 then
      --- draw left pane
      core.push_clip_rect(
        0, self.position.y,
        self.left_width + style.padding.x, self.size.y
      )
      for _, item in ipairs(self.active_items) do
        local item_x = self.left_xoffset + item.x + style.padding.x
        local hovered, item_bg = get_item_bg_color(self, item)
        if item.alignment == StatusView.Item.LEFT and not self.tooltip_mode then
          if type(item_bg) == "table" then
            renderer.draw_rect(
              item_x, self.position.y,
              item.w, self.size.y, item_bg
            )
          end
          if item.on_draw then
            core.push_clip_rect(item_x, self.position.y, item.w, self.size.y)
            item.on_draw(item_x, self.position.y, self.size.y, hovered)
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
        local hovered, item_bg = get_item_bg_color(self, item)
        if item.alignment == StatusView.Item.RIGHT then
          if type(item_bg) == "table" then
            renderer.draw_rect(
              item_x, self.position.y,
              item.w, self.size.y, item_bg
            )
          end
          if item.on_draw then
            core.push_clip_rect(item_x, self.position.y, item.w, self.size.y)
            item.on_draw(item_x, self.position.y, self.size.y, hovered)
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
