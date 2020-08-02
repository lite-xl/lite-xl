local core = require "core"
local common = require "core.common"
local style = require "core.style"
local keymap = require "core.keymap"
local Object = require "core.object"
local View = require "core.view"
local DocView = require "core.docview"


local XEmptyView = View:extend()

function XEmptyView:draw()
  self:draw_background(style.background)
end



local ReplNode = Object:extend()

function ReplNode:new()
  -- self.type = type or "leaf"
  self.position = { x = 0, y = 0 }
  self.size = { x = 0, y = 0 }
  self.view = XEmptyView()
  -- self.views = {}
  self.divider = 0.5
  self.next = nil
  -- if self.type == "leaf" then
  --   self:add_view(EmptyView())
  -- end
end


-- TODO: check if still okay
function ReplNode:propagate(fn, ...)
  if self.next then
    self.next[fn](self.next, ...)
  end
  -- self.a[fn](self.a, ...)
  -- self.b[fn](self.b, ...)
end


-- FIXME: figure out what to do here.
function ReplNode:on_mouse_moved(x, y, ...)
  -- self.hovered_tab = self:get_tab_overlapping_point(x, y)
  -- if self.type == "leaf" then
  --   self.active_view:on_mouse_moved(x, y, ...)
  -- else
  --   self:propagate("on_mouse_moved", x, y, ...)
  -- end
end


-- FIXME: line above
function ReplNode:on_mouse_released(...)
  -- if self.type == "leaf" then
  --   self.active_view:on_mouse_released(...)
  -- else
  --   self:propagate("on_mouse_released", ...)
  -- end
end


function ReplNode:consume(node)
  for k, _ in pairs(self) do self[k] = nil end
  for k, v in pairs(node) do self[k] = v   end
end


local type_map = { up="vsplit", down="vsplit", left="hsplit", right="hsplit" }

-- function ReplNode:split(dir, view, locked)


-- function ReplNode:close_active_view(root)


function ReplNode:append_view(view)
  assert(not self.next, "Tried to add view to non-terminal node")
  local new_node = ReplNode()
  new_node:set_view(view)
  self.next = new_node
end

-- function ReplNode:add_view(view)


-- function ReplNode:set_active_view(view)

function ReplNode:set_view(view)
  self.view = view
end


-- TODO: check if needed
function ReplNode:get_view_idx(view)
  assert(false, "Not yet implemented")
end


function ReplNode:get_node_for_view(view)
  local current_node = self
  while current_node do
    if current_node.view == view then
      return self
    end
    current_node = self.next
  end
end


-- TODO: check if needed
function ReplNode:get_parent_node(root)
  assert(false, "Not yet implemented")
end


-- function ReplNode:get_children(t)
-- function ReplNode:get_divider_overlapping_point(px, py)
-- function ReplNode:get_tab_overlapping_point(px, py)
-- function ReplNode:get_child_overlapping_point(x, y)
-- function ReplNode:get_tab_rect(idx)
-- function ReplNode:get_divider_rect()
-- function ReplNode:get_locked_size()


local function copy_position_and_size(dst, src)
  dst.position.x, dst.position.y = src.position.x, src.position.y
  dst.size.x, dst.size.y = src.size.x, src.size.y
end


-- local function calc_split_sizes(self, x, y, x1, x2)


function ReplNode:update_layout()
  if self.type == "leaf" then
    local av = self.active_view
    if #self.views > 1 then
      local _, _, _, th = self:get_tab_rect(1)
      av.position.x, av.position.y = self.position.x, self.position.y + th
      av.size.x, av.size.y = self.size.x, self.size.y - th
    else
      copy_position_and_size(av, self)
    end
  else
    local x1, y1 = self.a:get_locked_size()
    local x2, y2 = self.b:get_locked_size()
    if self.type == "hsplit" then
      calc_split_sizes(self, "x", "y", x1, x2)
    elseif self.type == "vsplit" then
      calc_split_sizes(self, "y", "x", y1, y2)
    end
    self.a:update_layout()
    self.b:update_layout()
  end
end


function ReplNode:update()
  if self.type == "leaf" then
    for _, view in ipairs(self.views) do
      view:update()
    end
  else
    self.a:update()
    self.b:update()
  end
end


function ReplNode:draw_tabs()
  local x, y, _, h = self:get_tab_rect(1)
  local ds = style.divider_size
  core.push_clip_rect(x, y, self.size.x, h)
  renderer.draw_rect(x, y, self.size.x, h, style.background2)
  renderer.draw_rect(x, y + h - ds, self.size.x, ds, style.divider)

  for i, view in ipairs(self.views) do
    local x, y, w, h = self:get_tab_rect(i)
    local text = view:get_name()
    local color = style.dim
    if view == self.active_view then
      color = style.text
      renderer.draw_rect(x, y, w, h, style.background)
      renderer.draw_rect(x + w, y, ds, h, style.divider)
      renderer.draw_rect(x - ds, y, ds, h, style.divider)
    end
    if i == self.hovered_tab then
      color = style.text
    end
    core.push_clip_rect(x, y, w, h)
    x, w = x + style.padding.x, w - style.padding.x * 2
    local align = style.font:get_width(text) > w and "left" or "center"
    common.draw_text(style.font, color, text, align, x, y, w, h)
    core.pop_clip_rect()
  end

  core.pop_clip_rect()
end


function ReplNode:draw()
  if self.type == "leaf" then
    if #self.views > 1 then
      self:draw_tabs()
    end
    local pos, size = self.active_view.position, self.active_view.size
    core.push_clip_rect(pos.x, pos.y, size.x + pos.x % 1, size.y + pos.y % 1)
    self.active_view:draw()
    core.pop_clip_rect()
  else
    local x, y, w, h = self:get_divider_rect()
    renderer.draw_rect(x, y, w, h, style.divider)
    self:propagate("draw")
  end
end



local ReplView = View:extend()

function ReplView:new()
  ReplView.super.new(self)
  self.root_node = ReplNode()
  self.deferred_draws = {}
  self.mouse = { x = 0, y = 0 }
end


function ReplView:defer_draw(fn, ...)
  table.insert(self.deferred_draws, 1, { fn = fn, ... })
end


function ReplView:get_active_node()
  return self.root_node:get_node_for_view(core.active_view)
end


function ReplView:open_doc(doc)
  local node = self:get_active_node()
  if node.locked and core.last_active_view then
    core.set_active_view(core.last_active_view)
    node = self:get_active_node()
  end
  assert(not node.locked, "Cannot open doc on locked node")
  for i, view in ipairs(node.views) do
    if view.doc == doc then
      node:set_active_view(node.views[i])
      return view
    end
  end
  local view = DocView(doc)
  node:add_view(view)
  self.root_node:update_layout()
  view:scroll_to_line(view.doc:get_selection(), true, true)
  return view
end


function ReplView:on_mouse_pressed(button, x, y, clicks)
  local div = self.root_node:get_divider_overlapping_point(x, y)
  if div then
    self.dragged_divider = div
    return
  end
  local node = self.root_node:get_child_overlapping_point(x, y)
  local idx = node:get_tab_overlapping_point(x, y)
  if idx then
    node:set_active_view(node.views[idx])
    if button == "middle" then
      node:close_active_view(self.root_node)
    end
  else
    core.set_active_view(node.active_view)
    node.active_view:on_mouse_pressed(button, x, y, clicks)
  end
end


function ReplView:on_mouse_released(...)
  if self.dragged_divider then
    self.dragged_divider = nil
  end
  self.root_node:on_mouse_released(...)
end


function ReplView:on_mouse_moved(x, y, dx, dy)
  if self.dragged_divider then
    local node = self.dragged_divider
    if node.type == "hsplit" then
      node.divider = node.divider + dx / node.size.x
    else
      node.divider = node.divider + dy / node.size.y
    end
    node.divider = common.clamp(node.divider, 0.01, 0.99)
    return
  end

  self.mouse.x, self.mouse.y = x, y
  self.root_node:on_mouse_moved(x, y, dx, dy)

  local node = self.root_node:get_child_overlapping_point(x, y)
  local div = self.root_node:get_divider_overlapping_point(x, y)
  if div then
    system.set_cursor(div.type == "hsplit" and "sizeh" or "sizev")
  elseif node:get_tab_overlapping_point(x, y) then
    system.set_cursor("arrow")
  else
    system.set_cursor(node.active_view.cursor)
  end
end


function ReplView:on_mouse_wheel(...)
  local x, y = self.mouse.x, self.mouse.y
  local node = self.root_node:get_child_overlapping_point(x, y)
  node.active_view:on_mouse_wheel(...)
end


function ReplView:on_text_input(...)
  core.active_view:on_text_input(...)
end


function ReplView:update()
  copy_position_and_size(self.root_node, self)
  self.root_node:update()
  self.root_node:update_layout()
end


function ReplView:draw()
  self.root_node:draw()
  while #self.deferred_draws > 0 do
    local t = table.remove(self.deferred_draws)
    t.fn(table.unpack(t))
  end
end


return ReplView
