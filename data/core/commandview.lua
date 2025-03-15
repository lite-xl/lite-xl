local core = require "core"
local common = require "core.common"
local style = require "core.style"
local Doc = require "core.doc"
local DocView = require "core.docview"
local View = require "core.view"


---@class core.commandview.input : core.doc
---@field super core.doc
local SingleLineDoc = Doc:extend()

function SingleLineDoc:__tostring() return "SingleLineDoc" end

function SingleLineDoc:insert(line, col, text)
  SingleLineDoc.super.insert(self, line, col, text:gsub("\n", ""))
end

---@class core.commandview : core.docview
---@field super core.docview
local CommandView = DocView:extend()

function CommandView:__tostring() return "CommandView" end

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
  self.suggestions_offset = 1
  self.suggestions = {}
  self.suggestions_height = 0
  self.last_change_id = 0
  self.last_text = ""
  self.gutter_width = 0
  self.gutter_text_brightness = 0
  self.selection_offset = 0
  self.state = default_state
  self.font = "font"
  self.size.y = 0
  self.label = ""
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

  local function get_suggestions_offset()
    local max_visible = math.min(max_suggestions, #self.suggestions)
    if dir > 0 then
      if self.suggestions_offset + max_visible < self.suggestion_idx + 1 then
        return self.suggestion_idx - max_visible + 1
      elseif self.suggestions_offset > self.suggestion_idx then
        return self.suggestion_idx
      end
    else
      if self.suggestions_offset > self.suggestion_idx then
        return self.suggestion_idx
      elseif self.suggestions_offset + max_visible < self.suggestion_idx + 1 then
        return self.suggestion_idx - max_visible + 1
      end
    end
    return self.suggestions_offset
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

  self.suggestions_offset = get_suggestions_offset()
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
  self.suggestions_offset = 1
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
  local dest = (self.suggestion_idx - self.suggestions_offset + 1) * self:get_suggestion_line_height()
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


local function draw_suggestions_box(self)
  local lh = self:get_suggestion_line_height()
  local dh = style.divider_size
  local x, _ = self:get_line_screen_position()
  local h = math.ceil(self.suggestions_height)
  local rx, ry, rw, rh = self.position.x, self.position.y - h - dh, self.size.x, h

  core.push_clip_rect(rx, ry, rw, rh)
  -- draw suggestions background
  if #self.suggestions > 0 then
    renderer.draw_rect(rx, ry, rw, rh, style.background3)
    renderer.draw_rect(rx, ry - dh, rw, dh, style.divider)
    local y = self.position.y - self.selection_offset - dh
    renderer.draw_rect(rx, y, rw, lh, style.line_highlight)
  end

  -- draw suggestion text
  local first = math.max(self.suggestions_offset, 1)
  local last = math.min(self.suggestions_offset + max_suggestions, #self.suggestions)
  for i=first, last do
    local item = self.suggestions[i]
    local color = (i == self.suggestion_idx) and style.accent or style.text
    local y = self.position.y - (i - first + 1) * lh - dh
    common.draw_text(self:get_font(), color, item.text, nil, x, y, 0, lh)

    if item.info then
      local w = self.size.x - x - style.padding.x
      common.draw_text(self:get_font(), style.dim, item.info, "right", x, y, w, lh)
    end
  end
  core.pop_clip_rect()
end


function CommandView:draw()
  CommandView.super.draw(self)
  if self.state.show_suggestions then
    core.root_view:defer_draw(draw_suggestions_box, self)
  end
end

return CommandView
