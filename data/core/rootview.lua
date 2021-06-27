local core = require "core"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local keymap = require "core.keymap"
local Object = require "core.object"
local View = require "core.view"
local CommandView = require "core.commandview"
local NagView = require "core.nagview"
local DocView = require "core.docview"


local EmptyView = View:extend()

local function draw_text(x, y, color)
  local th = style.big_font:get_height()
  local dh = 2 * th + style.padding.y * 2
  local x1, y1 = x, y + (dh - th) / 2
  x = renderer.draw_text(style.big_font, "Lite XL", x1, y1, color)
  renderer.draw_text(style.font, "version " .. VERSION, x1, y1 + th, color)
  x = x + style.padding.x
  renderer.draw_rect(x, y, math.ceil(1 * SCALE), dh, color)
  local lines = {
    { fmt = "%s to run a command", cmd = "core:find-command" },
    { fmt = "%s to open a file from the project", cmd = "core:find-file" },
    { fmt = "%s to change project folder", cmd = "core:change-project-folder" },
    { fmt = "%s to open a project folder", cmd = "core:open-project-folder" },
  }
  th = style.font:get_height()
  y = y + (dh - (th + style.padding.y) * #lines) / 2
  local w = 0
  for _, line in ipairs(lines) do
    local text = string.format(line.fmt, keymap.get_binding(line.cmd))
    w = math.max(w, renderer.draw_text(style.font, text, x + style.padding.x, y, color))
    y = y + th + style.padding.y
  end
  return w, dh
end

function EmptyView:draw()
  self:draw_background(style.background)
  local w, h = draw_text(0, 0, { 0, 0, 0, 0 })
  local x = self.position.x + math.max(style.padding.x, (self.size.x - w) / 2)
  local y = self.position.y + (self.size.y - h) / 2
  draw_text(x, y, style.dim)
end



local Node = Object:extend()

function Node:new(type)
  self.type = type or "leaf"
  self.position = { x = 0, y = 0 }
  self.size = { x = 0, y = 0 }
  self.views = {}
  self.divider = 0.5
  if self.type == "leaf" then
    self:add_view(EmptyView())
  end
  self.hovered = {x = -1, y = -1 }
  self.hovered_close = 0
  self.tab_shift = 0
  self.tab_offset = 1
  self.tab_width = style.tab_width
  self.move_towards = View.move_towards
end


function Node:propagate(fn, ...)
  self.a[fn](self.a, ...)
  self.b[fn](self.b, ...)
end


function Node:on_mouse_moved(x, y, ...)
  if self.type == "leaf" then
    self.hovered.x, self.hovered.y = x, y
    self.active_view:on_mouse_moved(x, y, ...)
  else
    self:propagate("on_mouse_moved", x, y, ...)
  end
end


function Node:on_mouse_released(...)
  if self.type == "leaf" then
    self.active_view:on_mouse_released(...)
  else
    self:propagate("on_mouse_released", ...)
  end
end


function Node:consume(node)
  for k, _ in pairs(self) do self[k] = nil end
  for k, v in pairs(node) do self[k] = v   end
end


local type_map = { up="vsplit", down="vsplit", left="hsplit", right="hsplit" }

-- The "locked" argument below should be in the form {x = <boolean>, y = <boolean>}
-- and it indicates if the node want to have a fixed size along the axis where the
-- boolean is true. If not it will be expanded to take all the available space.
-- The "resizable" flag indicates if, along the "locked" axis the node can be resized
-- by the user. If the node is marked as resizable their view should provide a
-- set_target_size method.
function Node:split(dir, view, locked, resizable)
  assert(self.type == "leaf", "Tried to split non-leaf node")
  local node_type = assert(type_map[dir], "Invalid direction")
  local last_active = core.active_view
  local child = Node()
  child:consume(self)
  self:consume(Node(node_type))
  self.a = child
  self.b = Node()
  if view then self.b:add_view(view) end
  if locked then
    assert(type(locked) == 'table')
    self.b.locked = locked
    self.b.resizable = resizable or false
    core.set_active_view(last_active)
  end
  if dir == "up" or dir == "left" then
    self.a, self.b = self.b, self.a
    return self.a
  end
  return self.b
end

function Node:remove_view(root, view)
  if #self.views > 1 then
    local idx = self:get_view_idx(view)
    if idx < self.tab_offset then
      self.tab_offset = self.tab_offset - 1
    end
    table.remove(self.views, idx)
    if self.active_view == view then
      self:set_active_view(self.views[idx] or self.views[#self.views])
    end
  else
    local parent = self:get_parent_node(root)
    local is_a = (parent.a == self)
    local other = parent[is_a and "b" or "a"]
    if other:get_locked_size() then
      self.views = {}
      self:add_view(EmptyView())
    else
      parent:consume(other)
      local p = parent
      while p.type ~= "leaf" do
        p = p[is_a and "a" or "b"]
      end
      p:set_active_view(p.active_view)
      if self.is_primary_node then
        p.is_primary_node = true
      end
    end
  end
  core.last_active_view = nil
end

function Node:close_view(root, view)
  local do_close = function()
    self:remove_view(root, view)
  end
  view:try_close(do_close)
end


function Node:close_active_view(root)
  self:close_view(root, self.active_view)
end


function Node:add_view(view, idx)
  assert(self.type == "leaf", "Tried to add view to non-leaf node")
  assert(not self.locked, "Tried to add view to locked node")
  if self.views[1] and self.views[1]:is(EmptyView) then
    table.remove(self.views)
  end
  table.insert(self.views, idx or (#self.views + 1), view)
  self:set_active_view(view)
end


function Node:set_active_view(view)
  assert(self.type == "leaf", "Tried to set active view on non-leaf node")
  self.active_view = view
  core.set_active_view(view)
end


function Node:get_view_idx(view)
  for i, v in ipairs(self.views) do
    if v == view then return i end
  end
end


function Node:get_node_for_view(view)
  for _, v in ipairs(self.views) do
    if v == view then return self end
  end
  if self.type ~= "leaf" then
    return self.a:get_node_for_view(view) or self.b:get_node_for_view(view)
  end
end


function Node:get_parent_node(root)
  if root.a == self or root.b == self then
    return root
  elseif root.type ~= "leaf" then
    return self:get_parent_node(root.a) or self:get_parent_node(root.b)
  end
end


function Node:get_children(t)
  t = t or {}
  for _, view in ipairs(self.views) do
    table.insert(t, view)
  end
  if self.a then self.a:get_children(t) end
  if self.b then self.b:get_children(t) end
  return t
end


-- return the width including the padding space and separately
-- the padding space itself
local function get_scroll_button_width()
  local w = style.icon_font:get_width(">")
  local pad = w
  return w + 2 * pad, pad
end


function Node:get_divider_overlapping_point(px, py)
  if self.type ~= "leaf" then
    local p = 6
    local x, y, w, h = self:get_divider_rect()
    x, y = x - p, y - p
    w, h = w + p * 2, h + p * 2
    if px > x and py > y and px < x + w and py < y + h then
      return self
    end
    return self.a:get_divider_overlapping_point(px, py)
        or self.b:get_divider_overlapping_point(px, py)
  end
end


function Node:get_visible_tabs_number()
  return math.min(#self.views - self.tab_offset + 1, config.max_tabs)
end


function Node:get_tab_overlapping_point(px, py)
  if #self.views == 1 then return nil end
  local tabs_number = self:get_visible_tabs_number()
  local x1, y1, w, h = self:get_tab_rect(self.tab_offset)
  local x2, y2 = self:get_tab_rect(self.tab_offset + tabs_number)
  if px >= x1 and py >= y1 and px < x2 and py < y1 + h then
    return math.floor((px - x1) / w) + self.tab_offset
  end
end


local function close_button_location(x, w)
  local cw = style.icon_font:get_width("C")
  local pad = style.padding.y
  return x + w - pad - cw, cw, pad
end


function Node:get_scroll_button_index(px, py)
  if #self.views == 1 then return end
  for i = 1, 2 do
    local x, y, w, h = self:get_scroll_button_rect(i)
    if px >= x and px < x + w and py >= y and py < y + h then
      return i
    end
  end
end


function Node:tab_hovered_update(px, py)
  local tab_index = self:get_tab_overlapping_point(px, py)
  self.hovered_tab = tab_index
  self.hovered_close = 0
  self.hovered_scroll_button = 0
  if tab_index then
    local x, y, w, h = self:get_tab_rect(tab_index)
    local cx, cw = close_button_location(x, w)
    if px >= cx and px < cx + cw and py >= y and py < y + h and config.tab_close_button then
      self.hovered_close = tab_index
    end
  else
    self.hovered_scroll_button = self:get_scroll_button_index(px, py) or 0
  end
end


function Node:get_child_overlapping_point(x, y)
  local child
  if self.type == "leaf" then
    return self
  elseif self.type == "hsplit" then
    child = (x < self.b.position.x) and self.a or self.b
  elseif self.type == "vsplit" then
    child = (y < self.b.position.y) and self.a or self.b
  end
  return child:get_child_overlapping_point(x, y)
end


function Node:get_scroll_button_rect(index)
  local w, pad = get_scroll_button_width()
  local h = style.font:get_height() + style.padding.y * 2
  local x = self.position.x + (index == 1 and 0 or self.size.x - w)
  return x, self.position.y, w, h, pad
end


function Node:get_tab_rect(idx)
  local sbw = get_scroll_button_width()
  local maxw = self.size.x - 2 * sbw
  local x0 = self.position.x + sbw
  local x1 = x0 + common.clamp(self.tab_width * (idx - 1) - self.tab_shift, 0, maxw)
  local x2 = x0 + common.clamp(self.tab_width * idx - self.tab_shift, 0, maxw)
  local h = style.font:get_height() + style.padding.y * 2
  return x1, self.position.y, x2 - x1, h
end


function Node:get_divider_rect()
  local x, y = self.position.x, self.position.y
  if self.type == "hsplit" then
    return x + self.a.size.x, y, style.divider_size, self.size.y
  elseif self.type == "vsplit" then
    return x, y + self.a.size.y, self.size.x, style.divider_size
  end
end


-- Return two values for x and y axis and each of them is either falsy or a number.
-- A falsy value indicate no fixed size along the corresponding direction.
function Node:get_locked_size()
  if self.type == "leaf" then
    if self.locked then
      local size = self.active_view.size
      -- The values below should be either a falsy value or a number
      local sx = (self.locked and self.locked.x) and size.x
      local sy = (self.locked and self.locked.y) and size.y
      return sx, sy
    end
  else
    local x1, y1 = self.a:get_locked_size()
    local x2, y2 = self.b:get_locked_size()
    -- The values below should be either a falsy value or a number
    local sx, sy
    if self.type == 'hsplit' then
      if x1 and x2 then
        local dsx = (x1 < 1 or x2 < 1) and 0 or style.divider_size
        sx = x1 + x2 + dsx
      end
      sy = y1 or y2
    else
      if y1 and y2 then
        local dsy = (y1 < 1 or y2 < 1) and 0 or style.divider_size
        sy = y1 + y2 + dsy
      end
      sx = x1 or x2
    end
    return sx, sy
  end
end


local function copy_position_and_size(dst, src)
  dst.position.x, dst.position.y = src.position.x, src.position.y
  dst.size.x, dst.size.y = src.size.x, src.size.y
end


-- calculating the sizes is the same for hsplits and vsplits, except the x/y
-- axis are swapped; this function lets us use the same code for both
local function calc_split_sizes(self, x, y, x1, x2, y1, y2)
  local n
  local ds = ((x1 and x1 < 1) or (x2 and x2 < 1)) and 0 or style.divider_size
  if x1 then
    n = x1 + ds
  elseif x2 then
    n = self.size[x] - x2
  else
    n = math.floor(self.size[x] * self.divider)
  end
  self.a.position[x] = self.position[x]
  self.a.position[y] = self.position[y]
  self.a.size[x] = n - ds
  self.a.size[y] = self.size[y]
  self.b.position[x] = self.position[x] + n
  self.b.position[y] = self.position[y]
  self.b.size[x] = self.size[x] - n
  self.b.size[y] = self.size[y]
end


function Node:update_layout()
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


function Node:scroll_tabs_to_visible()
  local index = self:get_view_idx(self.active_view)
  if index then
    local tabs_number = self:get_visible_tabs_number()
    if self.tab_offset > index then
      self.tab_offset = index
    elseif self.tab_offset + tabs_number - 1 < index then
      self.tab_offset = index - tabs_number + 1
    elseif tabs_number < config.max_tabs and self.tab_offset > 1 then
      self.tab_offset = #self.views - config.max_tabs + 1
    end
  end
end


function Node:scroll_tabs(dir)
  local view_index = self:get_view_idx(self.active_view)
  if dir == 1 then
    if self.tab_offset > 1 then
      self.tab_offset = self.tab_offset - 1
      local last_index = self.tab_offset + self:get_visible_tabs_number() - 1
      if view_index > last_index then
        self:set_active_view(self.views[last_index])
      end
    end
  elseif dir == 2 then
    local tabs_number = self:get_visible_tabs_number()
    if self.tab_offset + tabs_number - 1 < #self.views then
      self.tab_offset = self.tab_offset + 1
      local view_index = self:get_view_idx(self.active_view)
      if view_index < self.tab_offset then
        self:set_active_view(self.views[self.tab_offset])
      end
    end
  end
end


function Node:target_tab_width()
  local n = self:get_visible_tabs_number()
  local w = self.size.x - get_scroll_button_width() * 2
  return common.clamp(style.tab_width, w / config.max_tabs, w / n)
end


function Node:update()
  if self.type == "leaf" then
    self:scroll_tabs_to_visible()
    for _, view in ipairs(self.views) do
      view:update()
    end
    self:tab_hovered_update(self.hovered.x, self.hovered.y)
    local tab_width = self:target_tab_width()
    self:move_towards("tab_shift", tab_width * (self.tab_offset - 1))
    self:move_towards("tab_width", tab_width)
  else
    self.a:update()
    self.b:update()
  end
end


function Node:draw_tabs()
  local x, y, w, h, scroll_padding = self:get_scroll_button_rect(1)
  local ds = style.divider_size
  local dots_width = style.font:get_width("…")
  core.push_clip_rect(x, y, self.size.x, h)
  renderer.draw_rect(x, y, self.size.x, h, style.background2)
  renderer.draw_rect(x, y + h - ds, self.size.x, ds, style.divider)

  if self.tab_offset > 1 then
    local button_style = self.hovered_scroll_button == 1 and style.text or style.dim
    common.draw_text(style.icon_font, button_style, "<", nil, x + scroll_padding, y, 0, h)
  end

  local tabs_number = self:get_visible_tabs_number()
  if #self.views > self.tab_offset + tabs_number - 1 then
    local xrb, yrb, wrb = self:get_scroll_button_rect(2)
    local button_style = self.hovered_scroll_button == 2 and style.text or style.dim
    common.draw_text(style.icon_font, button_style, ">", nil, xrb + scroll_padding, yrb, 0, h)
  end

  for i = self.tab_offset, self.tab_offset + tabs_number - 1 do
    local view = self.views[i]
    local x, y, w, h = self:get_tab_rect(i)
    local text = view:get_name()
    local color = style.dim
    local padding_y = style.padding.y
    renderer.draw_rect(x + w, y + padding_y, ds, h - padding_y * 2, style.dim)
    if view == self.active_view then
      color = style.text
      renderer.draw_rect(x, y, w, h, style.background)
      renderer.draw_rect(x + w, y, ds, h, style.divider)
      renderer.draw_rect(x - ds, y, ds, h, style.divider)
    end
    local cx, cw, cspace = close_button_location(x, w)
    local show_close_button = ((view == self.active_view or i == self.hovered_tab) and config.tab_close_button)
    if show_close_button then
      local close_style = self.hovered_close == i and style.text or style.dim
      common.draw_text(style.icon_font, close_style, "C", nil, cx, y, 0, h)
    end
    if i == self.hovered_tab then
      color = style.text
    end
    local padx = style.padding.x
    -- Normally we should substract "cspace" from text_avail_width and from the
    -- clipping width. It is the padding space we give to the left and right of the
    -- close button. However, since we are using dots to terminate filenames, we
    -- choose to ignore "cspace" accepting that the text can possibly "touch" the
    -- close button.
    local text_avail_width = cx - x - padx
    core.push_clip_rect(x, y, cx - x, h)
    x, w = x + padx, w - padx * 2
    local align = "center"
    if style.font:get_width(text) > text_avail_width then
      align = "left"
      for i = 1, #text do
        local reduced_text = text:sub(1, #text - i)
        if style.font:get_width(reduced_text) + dots_width <= text_avail_width then
          text = reduced_text .. "…"
          break
        end
      end
    end
    common.draw_text(style.font, color, text, align, x, y, w, h)
    core.pop_clip_rect()
  end

  core.pop_clip_rect()
end


function Node:draw()
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


function Node:is_empty()
  if self.type == "leaf" then
    return #self.views == 0 or (#self.views == 1 and self.views[1]:is(EmptyView))
  else
    return self.a:is_empty() and self.b:is_empty()
  end
end


function Node:close_all_docviews()
  if self.type == "leaf" then
    local i = 1
    while i <= #self.views do
      local view = self.views[i]
      if view:is(DocView) and not view:is(CommandView) then
        table.remove(self.views, i)
      else
        i = i + 1
      end
    end
    if #self.views == 0 and self.is_primary_node then
      self:add_view(EmptyView())
    end
  else
    self.a:close_all_docviews()
    self.b:close_all_docviews()
    if self.a:is_empty() and not self.a.is_primary_node then
      self:consume(self.b)
    elseif self.b:is_empty() and not self.b.is_primary_node then
      self:consume(self.a)
    end
  end
end

-- Returns true for nodes that accept either "proportional" resizes (based on the
-- node.divider) or "locked" resizable nodes (along the resize axis).
function Node:is_resizable(axis)
  if self.type == 'leaf' then
    return not self.locked or not self.locked[axis] or self.resizable
  else
    local a_resizable = self.a:is_resizable(axis)
    local b_resizable = self.b:is_resizable(axis)
    return a_resizable and b_resizable
  end
end


-- Return true iff it is a locked pane along the rezise axis and is
-- declared "resizable".
function Node:is_locked_resizable(axis)
  return self.locked and self.locked[axis] and self.resizable
end


function Node:resize(axis, value)
  if self.type == 'leaf' then
    -- If it is not locked we don't accept the
    -- resize operation here because for proportional panes the resize is
    -- done using the "divider" value of the parent node.
    if self:is_locked_resizable(axis) then
      return self.active_view:set_target_size(axis, value)
    end
  else
    if self.type == (axis == "x" and "hsplit" or "vsplit") then
      -- we are resizing a node that is splitted along the resize axis
      if self.a:is_locked_resizable(axis) and self.b:is_locked_resizable(axis) then
        local rem_value = value - self.a.size[axis]
        if rem_value >= 0 then
          return self.b.active_view:set_target_size(axis, rem_value)
        else
          self.b.active_view:set_target_size(axis, 0)
          return self.a.active_view:set_target_size(axis, value)
        end
      end
    else
      -- we are resizing a node that is splitted along the axis perpendicular
      -- to the resize axis
      local a_resizable = self.a:is_resizable(axis)
      local b_resizable = self.b:is_resizable(axis)
      if a_resizable and b_resizable then
        self.a:resize(axis, value)
        self.b:resize(axis, value)
      end
    end
  end
end


local RootView = View:extend()

function RootView:new()
  RootView.super.new(self)
  self.root_node = Node()
  self.deferred_draws = {}
  self.mouse = { x = 0, y = 0 }
end


function RootView:defer_draw(fn, ...)
  table.insert(self.deferred_draws, 1, { fn = fn, ... })
end


function RootView:get_active_node()
  return self.root_node:get_node_for_view(core.active_view)
end


local function get_primary_node(node)
  if node.is_primary_node then
    return node
  end
  if node.type ~= "leaf" then
    return get_primary_node(node.a) or get_primary_node(node.b)
  end
end


function RootView:get_active_node_default()
  local node = self.root_node:get_node_for_view(core.active_view)
  if node.locked then
    local default_view = self:get_primary_node().views[1]
    assert(default_view, "internal error: cannot find original document node.")
    core.set_active_view(default_view)
    node = self:get_active_node()
  end
  return node
end


function RootView:get_primary_node()
  return get_primary_node(self.root_node)
end


function RootView:open_doc(doc)
  local node = self:get_active_node_default()
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


function RootView:close_all_docviews()
  self.root_node:close_all_docviews()
end


-- Function to intercept mouse pressed events on the active view.
-- Do nothing by default.
function RootView.on_view_mouse_pressed(button, x, y, clicks)
end


function RootView:on_mouse_pressed(button, x, y, clicks)
  local div = self.root_node:get_divider_overlapping_point(x, y)
  if div then
    self.dragged_divider = div
    return
  end
  local node = self.root_node:get_child_overlapping_point(x, y)
  if node.hovered_scroll_button > 0 then
    node:scroll_tabs(node.hovered_scroll_button)
    return
  end
  local idx = node:get_tab_overlapping_point(x, y)
  if idx then
    if button == "middle" or node.hovered_close == idx then
      node:close_view(self.root_node, node.views[idx])
    else
      self.dragged_node = { node, idx }
      node:set_active_view(node.views[idx])
    end
  else
    core.set_active_view(node.active_view)
    if not self.on_view_mouse_pressed(button, x, y, clicks) then
      node.active_view:on_mouse_pressed(button, x, y, clicks)
    end
  end
end


function RootView:on_mouse_released(...)
  if self.dragged_divider then
    self.dragged_divider = nil
  end
  if self.dragged_node then
    self.dragged_node = nil
  end
  self.root_node:on_mouse_released(...)
end


local function resize_child_node(node, axis, value, delta)
  local accept_resize = node.a:resize(axis, value)
  if not accept_resize then
    accept_resize = node.b:resize(axis, node.size[axis] - value)
  end
  if not accept_resize then
    node.divider = node.divider + delta / node.size[axis]
  end
end


function RootView:on_mouse_moved(x, y, dx, dy)
  if core.active_view == core.nag_view then
    core.request_cursor("arrow")
    core.active_view:on_mouse_moved(x, y, dx, dy)
    return
  end

  if self.dragged_divider then
    local node = self.dragged_divider
    if node.type == "hsplit" then
      x = common.clamp(x, 0, self.root_node.size.x * 0.95)
      resize_child_node(node, "x", x, dx)
    elseif node.type == "vsplit" then
      y = common.clamp(y, 0, self.root_node.size.y * 0.95)
      resize_child_node(node, "y", y, dy)
    end
    node.divider = common.clamp(node.divider, 0.01, 0.99)
    return
  end

  self.mouse.x, self.mouse.y = x, y
  self.root_node:on_mouse_moved(x, y, dx, dy)

  local node = self.root_node:get_child_overlapping_point(x, y)
  local div = self.root_node:get_divider_overlapping_point(x, y)
  local tab_index = node and node:get_tab_overlapping_point(x, y)
  if node and node:get_scroll_button_index(x, y) then
    core.request_cursor("arrow")
  elseif div then
    local axis = (div.type == "hsplit" and "x" or "y")
    if div.a:is_resizable(axis) and div.b:is_resizable(axis) then
      core.request_cursor(div.type == "hsplit" and "sizeh" or "sizev")
    end
  elseif tab_index then
    core.request_cursor("arrow")
  elseif node then
    core.request_cursor(node.active_view.cursor)
  end
  if node and self.dragged_node and (self.dragged_node[1] ~= node or (tab_index and self.dragged_node[2] ~= tab_index))
    and node.type == "leaf" and #node.views > 0 and node.views[1]:is(DocView) then
      local tab = self.dragged_node[1].views[self.dragged_node[2]]
      if self.dragged_node[1] ~= node then
        for i, v in ipairs(node.views) do if v.doc == tab.doc then tab = nil break end end
        if tab then
          self.dragged_node[1]:remove_view(self.root_node, tab)
          node:add_view(tab, tab_index)
          self.root_node:update_layout()
          self.dragged_node = { node, tab_index or #node.views }
          core.redraw = true
        end
      else
        table.remove(self.dragged_node[1].views, self.dragged_node[2])
        table.insert(node.views, tab_index, tab)
        self.dragged_node = { node, tab_index }
      end
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


function RootView:on_focus_lost(...)
  -- We force a redraw so documents can redraw without the cursor.
  core.redraw = true
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
  if core.cursor_change_req then
    system.set_cursor(core.cursor_change_req)
    core.cursor_change_req = nil
  end
end


return RootView
