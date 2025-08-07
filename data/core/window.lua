local core = require "core"
local Object = require "core.object"
local RootView = require "core.rootview"
local config = require "core.config"
local keymap = require "core.keymap"
local ime = require "core.ime"

local Window = Object:extend()

function Window:new(renwindow)
  self.renwindow = renwindow
  self.id = renwindow:get_id()
  self.mode = "normal"
  self.title = nil
  self.borderless = nil
  self.scale = { x = 1.0, y = 1.0 }
  self.clip_rect_stack = {{ 0,0,0,0 }}
  ---@type core.rootview
  self.root_view = RootView(self)
end


local function get_title_filename(view)
  local doc_filename = view.get_filename and view:get_filename() or view:get_name()
  if doc_filename ~= "---" then return doc_filename end
  return ""
end

function Window:has_focus()
  return self.renwindow:has_focus()
end

function Window:compose_window_title(title)
  return (title == "" or title == nil) and "Lite XL" or title .. " - Lite XL"
end

function Window:show_title_bar(show)
  self.title_view.visible = show
end

function Window:get_views_referencing_doc(doc)
  local res = {}
  local views = self.root_view.root_node:get_children()
  for _, view in ipairs(views) do
    if view.doc == doc then table.insert(res, view) end
  end
  return res
end


function Window:push_clip_rect(x, y, w, h)
  local x2, y2, w2, h2 = table.unpack(self.clip_rect_stack[#self.clip_rect_stack])
  local r, b, r2, b2 = x+w, y+h, x2+w2, y2+h2
  x, y = math.max(x, x2), math.max(y, y2)
  b, r = math.min(b, b2), math.min(r, r2)
  w, h = r-x, b-y
  table.insert(self.clip_rect_stack, { x, y, w, h })
  renderer.set_clip_rect(x, y, w, h)
end


function Window:pop_clip_rect()
  table.remove(self.clip_rect_stack)
  local x, y, w, h = table.unpack(self.clip_rect_stack[#self.clip_rect_stack])
  renderer.set_clip_rect(x, y, w, h)
end


function Window:update()
  local width, height = self.renwindow:get_size()
  -- update
  self.root_view.size.x, self.root_view.size.y = width, height
  self.root_view:update()
end

function Window:step()
  -- update window title
  local current_title = get_title_filename(self.root_view.active_view)
  if current_title ~= nil and current_title ~= self.title then
    self.renwindow:set_title(self.compose_window_title(current_title))
    self.title = current_title
  end
  -- draw
  renderer.begin_frame(self.renwindow)
  local width, height = self.renwindow:get_size()
  self.clip_rect_stack[1] = { 0, 0, width, height }
  renderer.set_clip_rect(table.unpack(self.clip_rect_stack[1]))
  self.root_view:draw()
  renderer.end_frame()
end

function Window:configure_borderless_window(borderless)
  self.borderless = borderless
  self.renwindow:set_bordered(not borderless)
  self.root_view.title_view:configure_hit_test(borderless)
  self.root_view.title_view.visible = borderless
end

function Window:on_event(type, ...)
  local did_keymap = false

  if type == "textinput" then
    self.root_view:on_text_input(...)
  elseif type == "textediting" then
    ime.on_text_editing(...)
  elseif type == "keypressed" then
    -- In some cases during IME composition input is still sent to us
    -- so we just ignore it.
    if ime.editing then return false end
    did_keymap = keymap.on_key_pressed(self, ...)
  elseif type == "keyreleased" then
    keymap.on_key_released(self, ...)
  elseif type == "mousemoved" then
    local x1, y1, x2, y2 = ...
    self.root_view:on_mouse_moved(x1 * self.scale.x, y1 * self.scale.y, x2 * self.scale.x, y2 * self.scale.y)
  elseif type == "mousepressed" then
    local bname, x, y, clicks = ...
    if not self.root_view:on_mouse_pressed(bname, x * self.scale.x, y * self.scale.y, clicks) then
      did_keymap = keymap.on_mouse_pressed(self, bname, x * self.scale.x, y * self.scale.y, clicks)
    end
  elseif type == "mousereleased" then
    local bname, x, y = ...
    self.root_view:on_mouse_released(bname, x * self.scale.x, y * self.scale.y)
  elseif type == "mouseleft" then
    self.root_view:on_mouse_left()
  elseif type == "mousewheel" then
    if not self.root_view:on_mouse_wheel(...) then
      did_keymap = keymap.on_mouse_wheel(self, ...)
    end
  elseif type == "touchpressed" then
    self.root_view:on_touch_pressed(...)
  elseif type == "touchreleased" then
    self.root_view:on_touch_released(...)
  elseif type == "touchmoved" then
    self.root_view:on_touch_moved(...)
  elseif type == "resized" then
    self.mode = self.renwindow:get_mode()
  elseif type == "minimized" or type == "maximized" or type == "restored" then
    self.mode = type == "restored" and "normal" or type
  elseif type == "filedropped" then
    self.root_view:on_file_dropped(...)
  elseif type == "focuslost" then
    self.root_view:on_focus_lost(...)
  elseif type == "closed" then
    if #core.windows > 1 then
      self.renwindow = nil
      collectgarbage("collect")
      core.remove_window(self)
    else
      core.quit()
    end
  end
  return did_keymap
end

return Window
