-- mod-version:1 -- lite-xl 1.16
local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"

local default_treeview_size = 200 * SCALE
local tooltip_offset = style.font:get_height("A")
local tooltip_border = 1
local tooltip_delay = 0.5
local tooltip_alpha = 255
local tooltip_alpha_rate = 1


local function get_depth(filename)
  local n = 1
  for sep in filename:gmatch("[\\/]") do
    n = n + 1
  end
  return n
end

local function replace_alpha(color, alpha)
  local r, g, b = table.unpack(color)
  return { r, g, b, alpha }
end


local TreeView = View:extend()

function TreeView:new()
  TreeView.super.new(self)
  self.scrollable = true
  self.visible = true
  self.init_size = true
  self.target_size = default_treeview_size
  self.cache = {}
  self.last = {}
  self.tooltip = { x = 0, y = 0, begin = 0, alpha = 0 }
end


function TreeView:set_target_size(axis, value)
  if axis == "x" then
    self.target_size = value
    return true
  end
end


function TreeView:get_cached(item, dirname)
  local dir_cache = self.cache[dirname]
  if not dir_cache then
    dir_cache = {}
    self.cache[dirname] = dir_cache
  end
  -- to discriminate top directories from regular files or subdirectories
  -- we add ':' at the end of the top directories' filename. it will be
  -- used only to identify the entry into the cache.
  local cache_name = item.filename .. (item.topdir and ":" or "")
  local t = dir_cache[cache_name]
  if not t then
    t = {}
    local basename = common.basename(item.filename)
    if item.topdir then
      t.filename = basename
      t.expanded = true
      t.depth = 0
      t.abs_filename = dirname
    else
      t.filename = item.filename
      t.depth = get_depth(item.filename)
      t.abs_filename = dirname .. PATHSEP .. item.filename
    end
    t.name = basename
    t.type = item.type
    dir_cache[cache_name] = t
  end
  return t
end


function TreeView:get_name()
  return "Project"
end


function TreeView:get_item_height()
  return style.font:get_height() + style.padding.y
end


function TreeView:check_cache()
  -- invalidate cache's skip values if project_files has changed
  for i = 1, #core.project_directories do
    local dir = core.project_directories[i]
    local last_files = self.last[dir.name]
    if not last_files then
      self.last[dir.name] = dir.files
    else
      if dir.files ~= last_files then
        for _, v in pairs(self.cache[dir.name]) do
          v.skip = nil
        end
        self.last[dir.name] = dir.files
      end
    end
  end
end


function TreeView:each_item()
  return coroutine.wrap(function()
    self:check_cache()
    local count_lines = 0
    local ox, oy = self:get_content_offset()
    local y = oy + style.padding.y
    local w = self.size.x
    local h = self:get_item_height()

    for k = 1, #core.project_directories do
      local dir = core.project_directories[k]
      local dir_cached = self:get_cached(dir.item, dir.name)
      coroutine.yield(dir_cached, ox, y, w, h)
      count_lines = count_lines + 1
      y = y + h
      local i = 1
      while i <= #dir.files and dir_cached.expanded do
        local item = dir.files[i]
        local cached = self:get_cached(item, dir.name)

        coroutine.yield(cached, ox, y, w, h)
        count_lines = count_lines + 1
        y = y + h
        i = i + 1

        if not cached.expanded then
          if cached.skip then
            i = cached.skip
          else
            local depth = cached.depth
            while i <= #dir.files do
              if get_depth(dir.files[i].filename) <= depth then break end
              i = i + 1
            end
            cached.skip = i
          end
        end
      end -- while files
    end -- for directories
    self.count_lines = count_lines
  end)
end


function TreeView:get_text_bounding_box(item, x, y, w, h)
  local icon_width = style.icon_font:get_width("D")
  local xoffset = item.depth * style.padding.x + style.padding.x + icon_width
  x = x + xoffset
  w = style.font:get_width(item.name) + 2 * style.padding.x
  return x, y, w, h
end


function TreeView:on_mouse_moved(px, py, ...)
  TreeView.super.on_mouse_moved(self, px, py, ...)
  if self.dragging_scrollbar then return end
  
  local item_changed, tooltip_changed
  for item, x,y,w,h in self:each_item() do
    if px > x and py > y and px <= x + w and py <= y + h then
      item_changed = true
      self.hovered_item = item
      
      x,y,w,h = self:get_text_bounding_box(item, x,y,w,h)
      if px > x and py > y and px <= x + w and py <= y + h then
        tooltip_changed = true
        self.tooltip.x, self.tooltip.y = px, py
        self.tooltip.begin = system.get_time()
      end
      break
    end
  end
  if not item_changed then self.hovered_item = nil end
  if not tooltip_changed then self.tooltip.x, self.tooltip.y = nil, nil end
end


local function create_directory_in(item)
  local path = item.abs_filename
  core.command_view:enter("Create directory in " .. path, function(text)
    local dirname = path .. PATHSEP .. text
    local success, err = system.mkdir(dirname)
    if not success then
      core.error("cannot create directory %q: %s", dirname, err)
    end
    item.expanded = true
    core.reschedule_project_scan()
  end)
end


function TreeView:on_mouse_pressed(button, x, y, clicks)
  local caught = TreeView.super.on_mouse_pressed(self, button, x, y, clicks)
  if caught then
    return
  end
  if not self.hovered_item then
    return
  elseif self.hovered_item.type == "dir" then
    if keymap.modkeys["ctrl"] and button == "left" then
      create_directory_in(self.hovered_item)
    else
      self.hovered_item.expanded = not self.hovered_item.expanded
    end
  else
    core.try(function()
      local doc_filename = common.relative_path(core.project_dir, self.hovered_item.abs_filename)
      core.root_view:open_doc(core.open_doc(doc_filename))
    end)
  end
end


function TreeView:update()
  -- update width
  local dest = self.visible and self.target_size or 0
  if self.init_size then
    self.size.x = dest
    self.init_size = false
  else
    self:move_towards(self.size, "x", dest)
  end
  
  local duration = system.get_time() - self.tooltip.begin
  if self.hovered_item and self.tooltip.x and duration > tooltip_delay then
    self:move_towards(self.tooltip, "alpha", tooltip_alpha, tooltip_alpha_rate)
  else
    self.tooltip.alpha = 0
  end

  TreeView.super.update(self)
end


function TreeView:get_scrollable_size()
  return self.count_lines and self:get_item_height() * (self.count_lines + 1) or math.huge
end


function TreeView:draw_tooltip()
  local text = common.home_encode(self.hovered_item.abs_filename)
  local w, h = style.font:get_width(text), style.font:get_height(text)

  local x, y = self.tooltip.x + tooltip_offset, self.tooltip.y + tooltip_offset
  w, h = w + style.padding.x, h + style.padding.y

  if x + w > core.root_view.root_node.size.x then -- check if we can span right
    x = x - w -- span left instead
  end

  local bx, by = x - tooltip_border, y - tooltip_border
  local bw, bh = w + 2 * tooltip_border, h + 2 * tooltip_border
  renderer.draw_rect(bx, by, bw, bh, replace_alpha(style.text, self.tooltip.alpha))
  renderer.draw_rect(x, y, w, h, replace_alpha(style.background2, self.tooltip.alpha))
  common.draw_text(style.font, replace_alpha(style.text, self.tooltip.alpha), text, "center", x, y, w, h)
end


function TreeView:draw()
  self:draw_background(style.background2)

  local icon_width = style.icon_font:get_width("D")
  local spacing = style.icon_font:get_width("f") / 2

  local doc = core.active_view.doc
  local active_filename = doc and system.absolute_path(doc.filename or "")

  for item, x,y,w,h in self:each_item() do
    local color = style.text

    -- highlight active_view doc
    if item.abs_filename == active_filename then
      color = style.accent
    end

    -- hovered item background
    if item == self.hovered_item then
      renderer.draw_rect(x, y, w, h, style.line_highlight)
      color = style.accent
    end

    -- icons
    x = x + item.depth * style.padding.x + style.padding.x
    if item.type == "dir" then
      local icon1 = item.expanded and "-" or "+"
      local icon2 = item.expanded and "D" or "d"
      common.draw_text(style.icon_font, color, icon1, nil, x, y, 0, h)
      x = x + style.padding.x
      common.draw_text(style.icon_font, color, icon2, nil, x, y, 0, h)
      x = x + icon_width
    else
      x = x + style.padding.x
      common.draw_text(style.icon_font, color, "f", nil, x, y, 0, h)
      x = x + icon_width
    end

    -- text
    x = x + spacing
    x = common.draw_text(style.font, color, item.name, nil, x, y, 0, h)
  end

  self:draw_scrollbar()
  if self.hovered_item and self.tooltip.alpha > 0 then
    core.root_view:defer_draw(self.draw_tooltip, self)
  end
end


-- init
local view = TreeView()
local node = core.root_view:get_active_node()
local treeview_node = node:split("left", view, {x = true}, true)

-- The toolbarview plugin is special because it is plugged inside
-- a treeview pane which is itelf provided in a plugin.
-- We therefore break the usual plugin's logic that would require each
-- plugin to be independent of each other. In addition it is not the
-- plugin module that plug itself in the active node but it is plugged here
-- in the treeview node.
local toolbar_plugin, ToolbarView = core.try(require, "plugins.toolbarview")
if config.toolbarview ~= false and toolbar_plugin then
  local toolbar_view = ToolbarView()
  treeview_node:split("down", toolbar_view, {y = true})
  local min_toolbar_width = toolbar_view:get_min_width()
  view:set_target_size("x", math.max(default_treeview_size, min_toolbar_width))
  command.add(nil, {
    ["toolbar:toggle"] = function()
      toolbar_view:toggle_visible()
    end,
  })
end


-- register commands and keymap
command.add(nil, {
  ["treeview:toggle"] = function()
    view.visible = not view.visible
  end,
})

keymap.add { ["ctrl+\\"] = "treeview:toggle" }
