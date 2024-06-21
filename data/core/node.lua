local core = require "core"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local Object = require "core.object"
local EmptyView = require "core.emptyview"
local View = require "core.view"

---@class core.node : core.object
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
  self.hovered_close = 0
  self.tab_shift = 0
  self.tab_offset = 1
  self.tab_width = style.tab_width
  self.move_towards = View.move_towards
  self.pocket = nil
end


function Node:propogate(fn, ...)
  if self.type ~= "leaf" then self.a:propogate(fn, ...) end
  if self.type ~= "leaf" then self.b:propogate(fn, ...) end
  fn(self, ...)
end

function Node:view_propogate(fn, ...)
  self:propogate(function(node)
    local i = 1
    while i <= #node.views do
      local view = node.views[i]
      fn(node, view)
      if view == node.views[i] then
        i = i + 1
      end
    end
  end)
end


---@deprecated
function Node:on_mouse_moved(x, y, ...)
  core.deprecation_log("Node:on_mouse_moved")
  if self.type == "leaf" then
    self.active_view:on_mouse_moved(x, y, ...)
  else
    self.a:on_mouse_moved(x, y, ...)
    self.b:on_mouse_moved(x, y, ...)
  end
end


---@deprecated
function Node:on_mouse_released(...)
  core.deprecation_log("Node:on_mouse_released")
  if self.type == "leaf" then
    self.active_view:on_mouse_released(...)
  else
    self.a:on_mouse_released(...)
    self.b:on_mouse_released(...)
  end
end


---@deprecated
function Node:on_mouse_left()
  core.deprecation_log("Node:on_mouse_left")
  if self.type == "leaf" then
    self.active_view:on_mouse_left()
  else
    self.a:on_mouse_left()
    self.b:on_mouse_left()
  end
end


---@deprecated
function Node:on_touch_moved(...)
  core.deprecation_log("Node:on_touch_moved")
  if self.type == "leaf" then
    self.active_view:on_touch_moved(...)
  else
    self.a:on_touch_moved(...)
    self.b:on_touch_moved(...)
  end
end

-- consuming does not affect pocket status; pockets can be neither created nor destroyed
function Node:consume(node)
  local pocket = self.pocket
  for k, _ in pairs(self) do self[k] = nil end
  for k, v in pairs(node) do self[k] = v   end
  self.pocket = pocket
end


local type_map = { up="vsplit", down="vsplit", left="hsplit", right="hsplit" }

-- The "pocket" argument below should indicate if this node is splitting off to form
-- an addressable pocket, and should be provided with the object as specified in `config`.
function Node:split(dir, view, pocket)
  assert(self.type == "leaf", "Tried to split non-leaf node")
  local node_type = assert(type_map[dir], "Invalid direction")
  local last_active = core.active_view
  local axis = (dir == "left" or dir == "right") and "x" or "y"
  local size = self.size[axis]
  local child = Node()
  child:consume(self)
  self:consume(Node(node_type))
  self.a = child
  self.b = Node()
  if pocket then
    self.b.pocket = pocket
    self.size[axis] = pocket.length
    self.length = pocket.length
  else
    self.length = size / 2
  end
  if view then self.b:add_view(view) end
  if dir == "up" or dir == "left" then
    self.a, self.b = self.b, self.a
    return self.a, self.b
  end
  return self.b, self.a
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
    if self.pocket then
      self.views = {}
      self:add_view(EmptyView())
    else
      parent:consume(other)
      local p = parent
      while p.type ~= "leaf" do
        p = p[is_a and "a" or "b"]
      end
      p:set_active_view(p.active_view)
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


function Node:add_view(view, idx, layout)
  local leaf = self
  if self.pocket then
    layout = layout or self.pocket.layout
    if layout == "primary" then
      while leaf.type ~= "leaf" do leaf = leaf.a end
    else
      while leaf.type ~= "leaf" do leaf = leaf.b end
    end
    local view_count = #leaf.views - (#leaf.views > 0 and leaf.views[1]:is(EmptyView) and 1 or 0)
    if view_count > 0 and layout == "hsplit" then
      return leaf:split("right", view)
    elseif view_count > 0 and layout == "vsplit" then
      return leaf:split("down", view)
    end
  end
  assert(leaf.type == "leaf", "Tried to add view to non-leaf node")
  if leaf.views[1] and leaf.views[1]:is(EmptyView) then
    table.remove(leaf.views)
    if idx and idx > 1 then
      idx = idx - 1
    end
  end
  assert(not leaf.pocket or leaf.pocket.layout ~= "single" or #leaf.views == 0, "Tried to add secondary view to single pocket.")
  idx = common.clamp(idx or (#leaf.views + 1), 1, (#leaf.views + 1))
  table.insert(leaf.views, idx, view)
  leaf:set_active_view(view)
end


function Node:set_active_view(view)
  assert(self.type == "leaf", "Tried to set active view on non-leaf node")
  local last_active_view = self.active_view
  self.active_view = view
  core.set_active_view(view)
  if last_active_view and last_active_view ~= view then
    last_active_view:on_mouse_left()
  end
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


function Node:get_pocket(root)
  if self.pocket then return self end
  local parent = self:get_parent_node(root)
  return parent and parent:get_pocket(root)
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
    local axis = self.type == "hsplit" and "x" or "y"
    if self.a:is_resizable(axis) and self.b:is_resizable(axis) then
      local p = 6
      local x, y, w, h = self:get_divider_rect()
      x, y = x - p, y - p
      w, h = w + p * 2, h + p * 2
      if px > x and py > y and px < x + w and py < y + h then
        return self
      end
    end
    return self.a:get_divider_overlapping_point(px, py)
        or self.b:get_divider_overlapping_point(px, py)
  end
end

function Node:accepts(node, mode)
  if self.parent_pocket and self.parent_pocket.pocket.layout == "primary" then return mode == "tab" end
  return true
end

function Node:get_visible_tabs_number()
  return math.min(#self.views - self.tab_offset + 1, config.max_tabs)
end


function Node:get_tab_overlapping_point(px, py)
  if not self:should_show_tabs() then return nil end
  local tabs_number = self:get_visible_tabs_number()
  local x1, y1, w, h = self:get_tab_rect(self.tab_offset)
  local x2, y2 = self:get_tab_rect(self.tab_offset + tabs_number)
  if px >= x1 and py >= y1 and px < x2 and py < y1 + h then
    return math.floor((px - x1) / w) + self.tab_offset
  end
end

-- Determines whether this node is "thin", i.e. it's entirely controlled by the single view within it.
function Node:is_thin()
  return (self.pocket and self.pocket.layout == "single") or
    (self.parent_pocket and self.parent_pocket.pocket.layout == "primary" and self ~= self.parent_pocket.a)
end


function Node:should_show_tabs()
  local always_show_tabs = config.always_show_tabs
  if self:is_thin() then return false end
  if self.parent_pocket and self.parent_pocket.pocket.always_show_tabs ~= nil then
    always_show_tabs = self.parent_pocket.pocket.always_show_tabs
  end
  local dn = core.root_view.dragged_node
  if #self.views > 1
     or (dn and dn.dragging) then -- show tabs while dragging
    return true
  elseif always_show_tabs then
    return not self.views[1]:is(EmptyView)
  end
  return false
end


local function close_button_location(x, w)
  local cw = style.icon_font:get_width("C")
  local pad = style.padding.x / 2
  return x + w - cw - pad, cw, pad
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
    if px >= cx and px < cx + cw and py >= y and py < y + h and config.tab_close_button and self.active_view.closable then
      self.hovered_close = tab_index
    end
  elseif #self.views > self:get_visible_tabs_number() then
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

-- returns: total height, text padding, top margin
local function get_tab_y_sizes()
  local height = style.font:get_height()
  local padding = style.padding.y
  local margin = style.margin.tab.top
  return height + (padding * 2) + margin, padding, margin
end

function Node:get_scroll_button_rect(index)
  local w, pad = get_scroll_button_width()
  local h = get_tab_y_sizes()
  local x = self.position.x + (index == 1 and self.size.x - w * 2 or self.size.x - w)
  return x, self.position.y, w, h, pad
end


function Node:get_tab_rect(idx)
  local maxw = self.size.x
  local x0 = self.position.x
  local x1 = x0 + common.clamp(self.tab_width * (idx - 1) - self.tab_shift, 0, maxw)
  local x2 = x0 + common.clamp(self.tab_width * idx - self.tab_shift, 0, maxw)
  local h, pad_y, margin_y = get_tab_y_sizes()
  return x1, self.position.y, x2 - x1, h, margin_y
end


function Node:get_divider_rect()
  local x, y = self.position.x, self.position.y
  if self.type == "hsplit" then
    return x + self.a.size.x, y, style.divider_size, self.size.y
  elseif self.type == "vsplit" then
    return x, y + self.a.size.y, self.size.x, style.divider_size
  end
end


-- Only certain nodes will know the length perpendicular to their parent split.
-- nil is the default here for something that doesn't have a well-defined size.
function Node:known_length(parent, pocket)
  if self.pocket then pocket = self end
  if not pocket then return nil end
  if self == pocket then
    if pocket.pocket.layout == "single" then
      local axis = (pocket.pocket.direction == "left" or pocket.pocket.direction == "right") and "x" or "y"
      return self.active_view.size[axis]
    else
      if self.type == "leaf" and pocket.pocket.layout ~= "root" and self:is_empty() then return 0 end
      return nil -- pockets are always resizable, and have no known length
    end
  end
  -- If we're in a pocket that is a "primary" pocket, all subsequent splits are assumed to be "single" splits, where the view controls the height.
  -- The first split will be of variable height.
  if pocket and pocket.pocket.layout == "primary" and self ~= pocket.a then
    local axis = parent.type == "hsplit" and "x" or "y"
    if self.type == "leaf" then return self.active_view.size[axis] end
    local ka, kb = self.a:known_length(self, pocket), self.b:known_length(self, pocket)
    if not ka or not kb then return nil end
    return ka + kb
  end
  return nil
end

-- The process for determining view size is like so.
-- This function is where all layout computations go.
function Node:update_layout(root, pocket)
  self.parent_pocket = pocket
  if self.type == "leaf" then
    local av = self.active_view
    local th = self:should_show_tabs() and select(4, self:get_tab_rect(1)) or 0
    av.position.x, av.position.y = self.position.x, self.position.y + th
    av.size.x, av.size.y = self.size.x, self.size.y - th
  else
    if self.pocket then pocket = self end
    local a_length = self.a:known_length(self, pocket)
    local b_length = self.b:known_length(self, pocket)
    -- in this case, this node decides, based on where it's resizable slider is
    local axis = self.type == "hsplit" and "x" or "y"
    local divider_size = a_length ~= 0 and b_length ~= 0 and style.divider_size or 0
    if a_length then
      self.length = a_length
    elseif b_length then
      self.length = self.size[axis] - b_length - divider_size
    end
    if self.length then
      self.a.position.x, self.a.position.y = self.position.x, self.position.y
      if self.type == "hsplit" then
        self.a.size.x = self.length
        self.b.size.x = self.size.x - self.length - divider_size
        self.a.size.y, self.b.size.y = self.size.y, self.size.y

        self.b.position.y = self.position.y
        self.b.position.x = self.position.x + self.a.size.x + divider_size
      else
        self.a.size.y = self.length
        self.b.size.y = self.size.y - self.length - divider_size
        self.a.size.x, self.b.size.x = self.size.x, self.size.x

        self.b.position.x = self.position.x 
        self.b.position.y = self.position.y + self.a.size.y + divider_size
      end
    else

    end
    self.a:update_layout(root, pocket)
    self.b:update_layout(root, pocket)
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
  local w = self.size.x
  if #self.views > n then
    w = self.size.x - get_scroll_button_width() * 2
  end
  return common.clamp(style.tab_width, w / config.max_tabs, w / n)
end


function Node:update()
  if self.type == "leaf" then
    self:scroll_tabs_to_visible()
    for _, view in ipairs(self.views) do
      view:update()
    end
    self:tab_hovered_update(core.root_view.mouse.x, core.root_view.mouse.y)
    local tab_width = self:target_tab_width()
    self:move_towards("tab_shift", tab_width * (self.tab_offset - 1), nil, "tabs")
    self:move_towards("tab_width", tab_width, nil, "tabs")
  else
    self.a:update()
    self.b:update()
  end
end

function Node:draw_tab_title(view, font, is_active, is_hovered, x, y, w, h)
  local text = view and view:get_name() or ""
  local dots_width = font:get_width("…")
  local align = "center"
  if font:get_width(text) > w then
    align = "left"
    for i = 1, #text do
      local reduced_text = text:sub(1, #text - i)
      if font:get_width(reduced_text) + dots_width <= w then
        text = reduced_text .. "…"
        break
      end
    end
  end
  local color = style.dim
  if is_active then color = style.text end
  if is_hovered then color = style.text end
  common.draw_text(font, color, text, align, x, y, w, h)
end

function Node:draw_tab_borders(view, is_active, is_hovered, x, y, w, h, standalone)
  -- Tabs deviders
  local ds = style.divider_size
  local color = style.dim
  local padding_y = style.padding.y
  renderer.draw_rect(x + w, y + padding_y, ds, h - padding_y*2, style.dim)
  if standalone then
    renderer.draw_rect(x-1, y-1, w+2, h+2, style.background2)
  end
  -- Full border
  if is_active then
    color = style.text
    renderer.draw_rect(x, y, w, h, style.background)
    renderer.draw_rect(x, y, w, ds, style.divider)
    renderer.draw_rect(x + w, y, ds, h, style.divider)
    renderer.draw_rect(x - ds, y, ds, h, style.divider)
  end
  return x + ds, y, w - ds*2, h
end

function Node:draw_tab(view, is_active, is_hovered, is_close_hovered, x, y, w, h, standalone)
  local _, padding_y, margin_y = get_tab_y_sizes()
  x, y, w, h = self:draw_tab_borders(view, is_active, is_hovered, x, y + margin_y, w, h - margin_y, standalone)
  -- Close button
  local cx, cw, cpad = close_button_location(x, w)
  local show_close_button = ((is_active or is_hovered) and not standalone and config.tab_close_button)
  if show_close_button and view.closable then
    local close_style = is_close_hovered and style.text or style.dim
    common.draw_text(style.icon_font, close_style, "C", nil, cx, y, cw, h)
  end
  if view.closable then
    x = x + cpad
    w = cx - x
  end
  core.push_clip_rect(x, y, w, h)
  self:draw_tab_title(view, style.font, is_active, is_hovered, x, y, w, h)
  core.pop_clip_rect()
end

function Node:draw_tabs()
  local _, y, w, h, scroll_padding = self:get_scroll_button_rect(1)
  local x = self.position.x
  local ds = style.divider_size
  local dots_width = style.font:get_width("…")
  core.push_clip_rect(x, y, self.size.x, h)
  renderer.draw_rect(x, y, self.size.x, h, style.background2)
  renderer.draw_rect(x, y + h - ds, self.size.x, ds, style.divider)
  local tabs_number = self:get_visible_tabs_number()

  for i = self.tab_offset, self.tab_offset + tabs_number - 1 do
    local view = self.views[i]
    local x, y, w, h = self:get_tab_rect(i)
    self:draw_tab(view, view == self.active_view,
                  i == self.hovered_tab, i == self.hovered_close,
                  x, y, w, h)
  end

  if #self.views > tabs_number then
    local _, pad = get_scroll_button_width()
    local xrb, yrb, wrb, hrb = self:get_scroll_button_rect(1)
    renderer.draw_rect(xrb + pad, yrb, wrb * 2, hrb, style.background2)
    local left_button_style = (self.hovered_scroll_button == 1 and self.tab_offset > 1) and style.text or style.dim
    common.draw_text(style.icon_font, left_button_style, "<", nil, xrb + scroll_padding, yrb, 0, h)

    xrb, yrb, wrb = self:get_scroll_button_rect(2)
    local right_button_style = (self.hovered_scroll_button == 2 and #self.views > self.tab_offset + tabs_number - 1) and style.text or style.dim
    common.draw_text(style.icon_font, right_button_style, ">", nil, xrb + scroll_padding, yrb, 0, h)
  end

  core.pop_clip_rect()
end


function Node:draw()
  if self.type == "leaf" then
    if self:should_show_tabs() then
      self:draw_tabs()
    end
    local pos, size = self.active_view.position, self.active_view.size
    core.push_clip_rect(pos.x, pos.y, size.x, size.y)
    self.active_view:draw()
    core.pop_clip_rect()
  else
    local x, y, w, h = self:get_divider_rect()
    renderer.draw_rect(x, y, w, h, style.divider)
    self.a:draw()
    self.b:draw()
  end
end


function Node:is_empty()
  if self.type == "leaf" then
    return #self.views == 0 or (#self.views == 1 and self.views[1]:is(EmptyView))
  else
    return self.a:is_empty() and self.b:is_empty()
  end
end


function Node:is_in_tab_area(x, y)
  if not self:should_show_tabs() then return false end
  local _, ty, _, th = self:get_scroll_button_rect(1)
  return y >= ty and y < ty + th
end



-- Nodes are resizable only exactly any of the following conditions.
-- 1. The node is under, or is the root pocket.
-- 2. The node is in a pocket that does not have a layout of "primary" or "single".
-- 3. The node is a pocket that does not have a layout of "single".
function Node:is_resizable(axis)
  if self:is_thin() then return false end
  if self.pocket then
    if self.pocket.layout == "root" then return true end
    return (axis == "x" and (self.pocket.direction == "left" or self.pocket.direction == "right")) or
      (axis == "y" and (self.pocket.direction == "top" or self.pocket.direction == "bottom"))
  end
  return not self.parent_pocket or (self.parent_pocket and self.parent_pocket.layout == "root" or (self.type ~= 'leaf' and (self.a:is_resizable(axis) and self.b:is_resizable(axis))))
end


function Node:get_split_type(mouse_x, mouse_y)
  local x, y = self.position.x, self.position.y
  local w, h = self.size.x, self.size.y
  local _, _, _, tab_h = self:get_scroll_button_rect(1)
  y = y + tab_h
  h = h - tab_h

  local local_mouse_x = mouse_x - x
  local local_mouse_y = mouse_y - y

  if local_mouse_y < 0 then
    return "tab"
  else
    local left_pct = local_mouse_x * 100 / w
    local top_pct = local_mouse_y * 100 / h
    if left_pct <= 30 then
      return "left"
    elseif left_pct >= 70 then
      return "right"
    elseif top_pct <= 30 then
      return "up"
    elseif top_pct >= 70 then
      return "down"
    end
    return "middle"
  end
end


function Node:get_drag_overlay_tab_position(x, y, dragged_node, dragged_index)
  local tab_index = self:get_tab_overlapping_point(x, y)
  if not tab_index then
    local first_tab_x = self:get_tab_rect(1)
    if x < first_tab_x then
      -- mouse before first visible tab
      tab_index = self.tab_offset or 1
    else
      -- mouse after last visible tab
      tab_index = self:get_visible_tabs_number() + (self.tab_offset - 1 or 0)
    end
  end
  local tab_x, tab_y, tab_w, tab_h, margin_y = self:get_tab_rect(tab_index)
  if x > tab_x + tab_w / 2 and tab_index <= #self.views then
    -- use next tab
    tab_x = tab_x + tab_w
    tab_index = tab_index + 1
  end
  if self == dragged_node and dragged_index and tab_index > dragged_index then
    -- the tab we are moving is counted in tab_index
    tab_index = tab_index - 1
    tab_x = tab_x - tab_w
  end
  return tab_index, tab_x, tab_y + margin_y, tab_w, tab_h - margin_y
end

return Node
