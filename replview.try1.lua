local core = require "core"
local common = require "core.common"
local style = require "core.style"
local keymap = require "core.keymap"
local Object = require "core.object"
local View = require "core.view"
local DocView = require "core.docview"

local ReplNode = Object:extend()

function ReplNode:new(view)
  -- self.type = type or "leaf"
  self.position = { x = 0, y = 0 }
  self.size = { x = 0, y = 0 }
  self.view = view
  -- self.views = {}
  self.divider = 0.5
end


function ReplNode:on_mouse_moved(x, y, ...)
  self.view:on_mouse_moved(x, y, ...)
end


function ReplNode:on_mouse_released(...)
  self.view:on_mouse_released(...)
end


-- local type_map = { up="vsplit", down="vsplit", left="hsplit", right="hsplit" }

-- function Node:split(dir, view, locked)

-- function Node:close_active_view(root)

function ReplNode:set_active_view()
  -- TODO: understand what the call below actually does.
  core.set_active_view(self.view)
end


-- function Node:get_view_idx(view)


-- function Node:get_node_for_view(view)


-- function Node:get_parent_node(root)

-- function Node:get_children(t)


-- function ReplNode:get_divider_overlapping_point(px, py)

-- function Node:get_tab_overlapping_point(px, py)


-- function Node:get_child_overlapping_point(x, y)


-- function Node:get_tab_rect(idx)


-- function Node:get_divider_rect()


function ReplNode:get_locked_size()
  if self.locked then
    local size = self.view.size
    return size.x, size.y
  end
end


local function copy_position_and_size(dst, src)
  dst.position.x, dst.position.y = src.position.x, src.position.y
  dst.size.x, dst.size.y = src.size.x, src.size.y
end


-- calculating the sizes is the same for hsplits and vsplits, except the x/y
-- axis are swapped; this function lets us use the same code for both
-- local function calc_split_sizes(self, x, y, x1, x2)


function ReplNode:update_layout()
  copy_position_and_size(self.view, self)
end


function ReplNode:update()
  if self.view then
    self.view:update()
  end
end


-- function Node:draw_tabs()

function ReplNode:draw()
  local pos, size = self.view.position, self.view.size
  core.push_clip_rect(pos.x, pos.y, size.x + pos.x % 1, size.y + pos.y % 1)
  self.view:draw()
  core.pop_clip_rect()
end



local ReplView = View:extend()

function ReplView:new()
  ReplView.super.new(self)
  -- local first_node = ReplNode()
  -- self.nodes = { first_node }
  self.nodes = { }
  self.active_node_index = 0
  self.deferred_draws = {}
  self.mouse = { x = 0, y = 0 }
end


-- TODO: figure out what the deferred_draws are doing
function ReplView:defer_draw(fn, ...)
  table.insert(self.deferred_draws, 1, { fn = fn, ... })
end


function ReplView:get_active_node()
  if self.active_node_index > 0 then
    return self.nodes[self.active_node_index]
  end
end

-- FIXME: find out something better
repl_left_margin, repl_top_margin = 10, 10

function ReplView:update_layout()
  local x, y = repl_left_margin, repl_top_margin
  -- CONTINUE HERE
end


function ReplView:open_doc(doc)
--   local node = self:get_active_node()
--   if node.locked and core.last_active_view then
--     core.set_active_view(core.last_active_view)
--     node = self:get_active_node()
--   end
--   assert(not node.locked, "Cannot open doc on locked node")
  for i, node in ipairs(self.nodes) do
    local view = node.view
  -- for i, view in ipairs(node.views) do
    if view.doc == doc then
      node:set_active_view()
      return view
    end
  end
  local view = DocView(doc)
  local node = ReplNode(view)
  self.nodes[#self.nodes + 1] = node
  self.active_node_index = #self.nodes
  self:update_layout()
  -- node:add_view(view)
  -- TODO: replace the call below with something appropriate.
  -- self.root_node:update_layout()
  -- TODO: manage to assign the correct x, y position to the new node.
  view:scroll_to_line(view.doc:get_selection(), true, true)
  return view
end

-- TODO: CONTINUE HERE
function RootView:on_mouse_pressed(button, x, y, clicks)
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


function RootView:on_mouse_released(...)
  if self.dragged_divider then
    self.dragged_divider = nil
  end
  self.root_node:on_mouse_released(...)
end


function RootView:on_mouse_moved(x, y, dx, dy)
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


function RootView:on_mouse_wheel(...)
  local x, y = self.mouse.x, self.mouse.y
  local node = self.root_node:get_child_overlapping_point(x, y)
  node.active_view:on_mouse_wheel(...)
end


function RootView:on_text_input(...)
  core.active_view:on_text_input(...)
end


function RootView:update()
  copy_position_and_size(self.root_node, self)
  self.root_node:update()
  self.root_node:update_layout()
end


function RootView:draw()
  self.root_node:draw()
  while #self.deferred_draws > 0 do
    local t = table.remove(self.deferred_draws)
    t.fn(table.unpack(t))
  end
end


return RootView
