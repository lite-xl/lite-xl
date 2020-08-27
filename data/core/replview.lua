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
      return current_node
    end
    current_node = current_node.next
  end
end

function ReplNode:get_last_node()
  local current_node = self
  while current_node do
    if current_node.next == nil then
      return current_node
    end
    current_node = current_node.next
  end
end


-- TODO: check if needed
function ReplNode:get_parent_node(root)
  assert(false, "Not yet implemented")
end


-- function ReplNode:get_children(t)
-- function ReplNode:get_divider_overlapping_point(px, py)
-- function ReplNode:get_tab_overlapping_point(px, py)

function ReplNode:get_child_overlapping_point(x, y)
  if (y >= self.position.y) and (y <= self.position.y + self.size.y) then
    return self
  else
    if self.next then
      return self.next:get_child_overlapping_point(x, y)
    end
  end
end

-- function ReplNode:get_tab_rect(idx)
-- function ReplNode:get_divider_rect()
-- function ReplNode:get_locked_size()


local function copy_position_and_size(dst, src)
  dst.position.x, dst.position.y = src.position.x, src.position.y
  dst.size.x, dst.size.y = src.size.x, src.size.y
end


-- local function calc_split_sizes(self, x, y, x1, x2)

-- FIXME: do not hard code values. Figure out a more correct way. May be use SCALE.
local left_margin, top_margin = 20, 20
local spacing = { x = 20, y = 20 }

function ReplNode:update_layout(x, y, w)
  -- we assume below that self.view is a DocView
  local doc_size = self.view:get_content_size()
  self.position.x = x
  self.position.y = y
  self.size.x = w
  self.size.y = doc_size
  if self.next then
    self.next:update_layout(x, y + doc_size + spacing.y, w)
  end
end


function ReplNode:update()
  self.view:update()
  if self.next then
    self.next:update()
  end
end


-- function ReplNode:draw_tabs()


function ReplNode:draw()
  local pos, size = self.view.position, self.view.size
  core.push_clip_rect(pos.x, pos.y, size.x + pos.x % 1, size.y + pos.y % 1)
  self.view:draw()
  core.pop_clip_rect()

  if self.next then
    self.next:draw()
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

-- FIXME: this function should be remove because it is needed only
-- for a RootView.
function ReplView:get_active_node()
  return self.root_node:get_node_for_view(core.active_view)
end


-- Previously named "open_doc"
function ReplView:append_doc(doc)
  local node = self.root_node:get_last_node()
  local view = DocView(doc)
  node:add_view(view)
  self.root_node:update_layout()
  view:scroll_to_line(view.doc:get_selection(), true, true)
  return view
end


function ReplView:on_mouse_pressed(button, x, y, clicks)
  local node = self.root_node:get_child_overlapping_point(x, y)

  -- FIXME: Should not be called, it is only for RootView.
  -- Verify is set_active_view below whould be removed.
  core.set_active_view(node.view)

  node.view:on_mouse_pressed(button, x, y, clicks)
end


function ReplView:on_mouse_released(...)
  self.root_node:on_mouse_released(...)
end


-- CONTINUE FROM HERE:

function ReplView:on_mouse_moved(x, y, dx, dy)
  self.mouse.x, self.mouse.y = x, y
  -- CONTINUE HERE: implement the on_mouse_moved for ReplNode
  self.root_node:on_mouse_moved(x, y, dx, dy)

  local node = self.root_node:get_child_overlapping_point(x, y)
  if node then
    system.set_cursor(node.active_view.cursor)
  else
    system.set_cursor("arrow")
  endif
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
