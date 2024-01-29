local core = require "core"
local common = require "core.common"
local style = require "core.style"
local Doc = require "core.doc"
local DocView = require "core.docview"
local View = require "core.view"
local RootView = require "core.rootview"


---@class core.commandview.input : core.doc
---@field super core.doc
local SingleLineDoc = Doc:extend()

function SingleLineDoc:insert(line, col, text)
  SingleLineDoc.super.insert(self, line, col, text:gsub("\n", ""))
end

---@class core.commandview : core.docview
---@field super core.docview
local CommandView = DocView:extend()

CommandView.context = "application"

local max_suggestions = 10

local noop = function() end

---@class core.commandview.state
---@field submit function
---@field suggest function
---@field cancel function
---@field validate function
---@field text string
---@field select_text boolean
---@field show_suggestions boolean
---@field typeahead boolean
---@field wrap boolean
local default_state = {
  submit = noop,
  suggest = noop,
  cancel = noop,
  validate = function() return true end,
  text = "",
  select_text = false,
  show_suggestions = true,
  typeahead = true,
  wrap = true,
}


function CommandView:new()
  CommandView.super.new(self, SingleLineDoc())
  self.suggestion_idx = 1
  self.suggestions = {}
  self.suggestions_height = 0
  self.suggestions_offset = 0
  self.suggestions_first = 1
  self.suggestions_last = 0
  self.last_change_id = 0
  self.last_text = ""
  self.gutter_width = 0
  self.gutter_text_brightness = 0
  self.selection_offset = 0
  self.state = default_state
  self.font = "font"
  self.size.y = 0
  self.label = ""
  self.mouse_position = {x = 0, y = 0}
end


---@deprecated
function CommandView:set_hidden_suggestions()
  core.warn("Using deprecated function CommandView:set_hidden_suggestions")
  self.state.show_suggestions = false
end


function CommandView:get_name()
  return View.get_name(self)
end


function CommandView:get_line_screen_position(line, col)
  local x = CommandView.super.get_line_screen_position(self, 1, col)
  local _, y = self:get_content_offset()
  local lh = self:get_line_height()
  return x, y + (self.size.y - lh) / 2
end


function CommandView:supports_text_input()
  return true
end


function CommandView:get_scrollable_size()
  return 0
end

function CommandView:get_h_scrollable_size()
  return 0
end


function CommandView:scroll_to_make_visible()
  -- no-op function to disable this functionality
end


function CommandView:get_text()
  return self.doc:get_text(1, 1, 1, math.huge)
end


function CommandView:set_text(text, select)
  self.last_text = text
  self.doc:remove(1, 1, math.huge, math.huge)
  self.doc:text_input(text)
  if select then
    self.doc:set_selection(math.huge, math.huge, 1, 1)
  end
end


function CommandView:move_suggestion_idx(dir)
  local function overflow_suggestion_idx(n, count)
    if count == 0 then return 0 end
    if self.state.wrap then
      return (n - 1) % count + 1
    else
      return common.clamp(n, 1, count)
    end
  end

  if self.state.show_suggestions then
    local n = self.suggestion_idx + dir
    self.suggestion_idx = overflow_suggestion_idx(n, #self.suggestions)
    self:complete()
    self.last_change_id = self.doc:get_change_id()
  else
    local current_suggestion = #self.suggestions > 0 and self.suggestions[self.suggestion_idx].text
    local text = self:get_text()
    if text == current_suggestion then
      local n = self.suggestion_idx + dir
      if n == 0 and self.save_suggestion then
        self:set_text(self.save_suggestion)
      else
        self.suggestion_idx = overflow_suggestion_idx(n, #self.suggestions)
        self:complete()
      end
    else
      self.save_suggestion = text
      self:complete()
    end
    self.last_change_id = self.doc:get_change_id()
    self.state.suggest(self:get_text())
  end
end


function CommandView:complete()
  if #self.suggestions > 0 then
    self:set_text(self.suggestions[self.suggestion_idx].text)
  end
end


function CommandView:submit()
  local suggestion = self.suggestions[self.suggestion_idx]
  local text = self:get_text()
  if self.state.validate(text, suggestion) then
    local submit = self.state.submit
    self:exit(true)
    submit(text, suggestion)
  end
end

---@param label string
---@varargs any
---@overload fun(label:string, options: core.commandview.state)
function CommandView:enter(label, ...)
  if self.state ~= default_state then
    return
  end
  local options = select(1, ...)

  if type(options) ~= "table" then
    core.warn("Using CommandView:enter in a deprecated way")
    local submit, suggest, cancel, validate = ...
    options = {
      submit = submit,
      suggest = suggest,
      cancel = cancel,
      validate = validate,
    }
  end

  -- Support deprecated CommandView:set_hidden_suggestions
  -- Remove this when set_hidden_suggestions is not supported anymore
  if options.show_suggestions == nil then
    options.show_suggestions = self.state.show_suggestions
  end

  self.state = common.merge(default_state, options)

  -- We need to keep the text entered with CommandView:set_text to
  -- maintain compatibility with deprecated usage, but still allow
  -- overwriting with options.text
  local old_text = self:get_text()
  if old_text ~= "" then
    core.warn("Using deprecated function CommandView:set_text")
  end
  if options.text or options.select_text then
    local text = options.text or old_text
    self:set_text(text, self.state.select_text)
  end
  -- Replace with a simple
  -- self:set_text(self.state.text, self.state.select_text)
  -- once old usage is removed

  core.set_active_view(self)
  self:update_suggestions()
  self.gutter_text_brightness = 100
  self.label = label .. ": "
end


function CommandView:exit(submitted, inexplicit)
  if core.active_view == self then
    core.set_active_view(core.last_active_view)
  end
  local cancel = self.state.cancel
  self.state = default_state
  self.doc:reset()
  self.suggestions = {}
  if not submitted then cancel(not inexplicit) end
  self.save_suggestion = nil
  self.last_text = ""
end


function CommandView:get_line_height()
  return math.floor(self:get_font():get_height() * 1.2)
end


function CommandView:get_gutter_width()
  return self.gutter_width
end


function CommandView:get_suggestion_line_height()
  return self:get_font():get_height() + style.padding.y
end


function CommandView:update_suggestions()
  local t = self.state.suggest(self:get_text()) or {}
  local res = {}
  for i, item in ipairs(t) do
    if type(item) == "string" then
      item = { text = item }
    end
    res[i] = item
  end
  self.suggestions = res
  self.suggestion_idx = 1
end


function CommandView:update()
  CommandView.super.update(self)

  if core.active_view ~= self and self.state ~= default_state then
    self:exit(false, true)
  end

  -- update suggestions if text has changed
  if self.last_change_id ~= self.doc:get_change_id() then
    self:update_suggestions()
    if self.state.typeahead and self.suggestions[self.suggestion_idx] then
      local current_text = self:get_text()
      local suggested_text = self.suggestions[self.suggestion_idx].text or ""
      if #self.last_text < #current_text and
         string.find(suggested_text, current_text, 1, true) == 1 then
        self:set_text(suggested_text)
        self.doc:set_selection(1, #current_text + 1, 1, math.huge)
      end
      self.last_text = current_text
    end
    self.last_change_id = self.doc:get_change_id()
  end

  -- update gutter text color brightness
  self:move_towards("gutter_text_brightness", 0, 0.1, "commandview")

  -- update gutter width
  local dest = self:get_font():get_width(self.label) + style.padding.x
  if self.size.y <= 0 then
    self.gutter_width = dest
  else
    self:move_towards("gutter_width", dest, nil, "commandview")
  end

  -- update suggestions box height
  local lh = self:get_suggestion_line_height()
  local dest = self.state.show_suggestions and math.min(#self.suggestions, max_suggestions) * lh or 0
  self:move_towards("suggestions_height", dest, nil, "commandview")

  -- update suggestion cursor offset
  local dest = math.min(self.suggestion_idx, max_suggestions) * self:get_suggestion_line_height()
  self:move_towards("selection_offset", dest, nil, "commandview")

  -- update size based on whether this is the active_view
  local dest = 0
  if self == core.active_view then
    dest = style.font:get_height() + style.padding.y * 2
  end
  self:move_towards(self.size, "y", dest, nil, "commandview")
end


function CommandView:draw_line_highlight()
  -- no-op function to disable this functionality
end


function CommandView:draw_line_gutter(idx, x, y)
  local yoffset = self:get_line_text_y_offset()
  local pos = self.position
  local color = common.lerp(style.text, style.accent, self.gutter_text_brightness / 100)
  core.push_clip_rect(pos.x, pos.y, self:get_gutter_width(), self.size.y)
  x = x + style.padding.x
  renderer.draw_text(self:get_font(), self.label, x, y + yoffset, color)
  core.pop_clip_rect()
  return self:get_line_height()
end


---Check if the mouse is hovering the suggestions box.
---@return boolean mouse_on_top
function CommandView:is_mouse_on_suggestions()
  if self.state.show_suggestions and #self.suggestions > 0 then
    local mx, my = self.mouse_position.x, self.mouse_position.y
    local dh = style.divider_size
    local sh = math.ceil(self.suggestions_height)
    local x, y, w, h = self.position.x, self.position.y - sh - dh, self.size.x, sh
    if mx >= x and mx <= x+w and my >= y and my <= y+h then
      return true
    end
  end
  return false
end


local function draw_suggestions_box(self)
  local lh = self:get_suggestion_line_height()
  local dh = style.divider_size
  local x, _ = self:get_line_screen_position()
  local h = math.ceil(self.suggestions_height)
  local rx, ry, rw, rh = self.position.x, self.position.y - h - dh, self.size.x, h

  if #self.suggestions > 0 then
    -- draw suggestions background
    renderer.draw_rect(rx, ry, rw, rh, style.background3)
    renderer.draw_rect(rx, ry - dh, rw, dh, style.divider)

    -- draw suggestion text
    local current = self.suggestion_idx
    local offset = math.max(current - max_suggestions, 0)
    if self.suggestions_first-1 == current then
      offset = math.max(self.suggestions_first - 2, 0)
    end
    local first = 1 + offset
    local last = math.min(offset + max_suggestions, #self.suggestions)
    if current < self.suggestions_first or current > self.suggestions_last then
      self.suggestions_first = first
      self.suggestions_last = last
      self.suggestions_offset = offset
    else
      offset = self.suggestions_offset
      first = self.suggestions_first
      last = math.min(self.suggestions_last, #self.suggestions)
    end
    core.push_clip_rect(rx, ry, rw, rh)
    for i=first, last do
      local item = self.suggestions[i]
      local color = (i == current) and style.accent or style.text
      local y = self.position.y - (i - offset) * lh - dh
      if i == current then
        renderer.draw_rect(rx, y, rw, lh, style.line_highlight)
      end
      common.draw_text(self:get_font(), color, item.text, nil, x, y, 0, lh)
      if item.info then
        local w = self.size.x - x - style.padding.x
        common.draw_text(self:get_font(), style.dim, item.info, "right", x, y, w, lh)
      end
    end
    core.pop_clip_rect()
  end
end


function CommandView:draw()
  CommandView.super.draw(self)
  if self.state.show_suggestions then
    core.root_view:defer_draw(draw_suggestions_box, self)
  end
end


function CommandView:on_mouse_moved(x, y)
  self.mouse_position.x = x
  self.mouse_position.y = y
  if self:is_mouse_on_suggestions() then
    core.request_cursor("arrow")

    local lh = self:get_suggestion_line_height()
    local dh = style.divider_size
    local offset = self.suggestions_offset
    local first = self.suggestions_first
    local last = self.suggestions_last

    for i=first, last do
      local sy = self.position.y - (i - offset) * lh - dh
      if y >= sy then
        self.suggestion_idx=i
        self:complete()
        self.last_change_id = self.doc:get_change_id()
        break
      end
    end
    return true
  end
  return false
end


function CommandView:on_mouse_wheel(y)
  if self:is_mouse_on_suggestions() then
    if y < 0 then
      self:move_suggestion_idx(-1)
    else
      self:move_suggestion_idx(1)
    end
    return true
  end
  return false
end


function CommandView:on_mouse_pressed(button, x, y, clicks)
  if self:is_mouse_on_suggestions() then
    if button == "left" then
      self:submit()
    end
    return true
  end
  return false
end


function CommandView:on_mouse_released()
  if self:is_mouse_on_suggestions() then
    return true
  end
  return false
end


--------------------------------------------------------------------------------
-- Transmit mouse events to the suggestions box
-- TODO: Remove these overrides once FloatingView is implemented
--------------------------------------------------------------------------------
local root_view_on_mouse_moved = RootView.on_mouse_moved
local root_view_on_mouse_wheel = RootView.on_mouse_wheel
local root_view_on_mouse_pressed = RootView.on_mouse_pressed
local root_view_on_mouse_released = RootView.on_mouse_released

function RootView:on_mouse_moved(...)
  if core.active_view:is(CommandView) then
    if core.active_view:on_mouse_moved(...) then return true end
  end
  return root_view_on_mouse_moved(self, ...)
end

function RootView:on_mouse_wheel(...)
  if core.active_view:is(CommandView) then
    if core.active_view:on_mouse_wheel(...) then return true end
  end
  return root_view_on_mouse_wheel(self, ...)
end

function RootView:on_mouse_pressed(...)
  if core.active_view:is(CommandView) then
    if core.active_view:on_mouse_pressed(...) then return true end
  end
  return root_view_on_mouse_pressed(self, ...)
end

function RootView:on_mouse_released(...)
  if core.active_view:is(CommandView) then
    if core.active_view:on_mouse_released(...) then return true end
  end
  return root_view_on_mouse_released(self, ...)
end


return CommandView
