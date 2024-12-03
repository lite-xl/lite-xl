-- mod-version:3
local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"
local ContextMenu = require "core.contextmenu"
local RootView = require "core.rootview"
local CommandView = require "core.commandview"
local DocView = require "core.docview"

config.plugins.treeview = common.merge({
  -- Default treeview width
  size = 200 * SCALE,
  highlight_focused_file = true,
  expand_dirs_to_focused_file = false,
  scroll_to_focused_file = false,
  animate_scroll_to_focused_file = true
}, config.plugins.treeview)

local tooltip_offset = style.font:get_height()
local tooltip_border = 1
local tooltip_delay = 0.5
local tooltip_alpha = 255
local tooltip_alpha_rate = 1


local function get_depth(filename)
  local n = 1
  for _ in filename:gmatch(PATHSEP) do
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
  self.target_size = config.plugins.treeview.size
  self.cache = {}
  self.tooltip = { x = 0, y = 0, begin = 0, alpha = 0 }
  self.last_scroll_y = 0

  self.item_icon_width = 0
  self.item_text_spacing = 0
end


function TreeView:set_target_size(axis, value)
  if axis == "x" then
    self.target_size = value
    return true
  end
end


function TreeView:get_cached(dir, item, dirname)
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
  if not t or t.type ~= item.type then
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
    t.dir_name = dir.name -- points to top level "dir" item
    dir_cache[cache_name] = t
  end
  return t
end


function TreeView:get_name()
  return nil
end


function TreeView:get_item_height()
  return style.font:get_height() + style.padding.y
end


function TreeView:invalidate_cache(dirname)
  for _, v in pairs(self.cache[dirname]) do
    v.skip = nil
  end
end


function TreeView:check_cache()
  for i = 1, #core.project_directories do
    local dir = core.project_directories[i]
    -- invalidate cache's skip values if directory is declared dirty
    if dir.is_dirty and self.cache[dir.name] then
      self:invalidate_cache(dir.name)
    end
    dir.is_dirty = false
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
      local dir_cached = self:get_cached(dir, dir.item, dir.name)
      coroutine.yield(dir_cached, ox, y, w, h)
      count_lines = count_lines + 1
      y = y + h
      local i = 1
      if dir.files then -- if consumed max sys file descriptors this can be nil
        while i <= #dir.files and dir_cached.expanded do
          local item = dir.files[i]
          local cached = self:get_cached(dir, item, dir.name)

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
      end
    end -- for directories
    self.count_lines = count_lines
  end)
end


function TreeView:set_selection(selection, selection_y, center, instant)
  self.selected_item = selection
  if selection and selection_y
      and (selection_y <= 0 or selection_y >= self.size.y) then
    local lh = self:get_item_height()
    if not center and selection_y >= self.size.y - lh then
      selection_y = selection_y - self.size.y + lh
    end
    if center then
      selection_y = selection_y - (self.size.y - lh) / 2
    end
    local _, y = self:get_content_offset()
    self.scroll.to.y = selection_y - y
    self.scroll.to.y = common.clamp(self.scroll.to.y, 0, self:get_scrollable_size() - self.size.y)
    if instant then
      self.scroll.y = self.scroll.to.y
    end
  end
end

---Sets the selection to the file with the specified path.
---
---@param path string #Absolute path of item to select
---@param expand boolean #Expand dirs leading to the item
---@param scroll_to boolean #Scroll to make the item visible
---@param instant boolean #Don't animate the scroll
---@return table? #The selected item
function TreeView:set_selection_to_path(path, expand, scroll_to, instant)
  local to_select, to_select_y
  local let_it_finish, done
  ::restart::
  for item, x,y,w,h in self:each_item() do
    if not done then
      if item.type == "dir" then
        local _, to = string.find(path, item.abs_filename..PATHSEP, 1, true)
        if to and to == #item.abs_filename + #PATHSEP then
          to_select, to_select_y = item, y
          if expand and not item.expanded then
            -- Use TreeView:toggle_expand to update the directory structure.
            -- Directly using item.expanded doesn't update the cached tree.
            self:toggle_expand(true, item)
            -- Because we altered the size of the TreeView
            -- and because TreeView:get_scrollable_size uses self.count_lines
            -- which gets updated only when TreeView:each_item finishes,
            -- we can't stop here or we risk that the scroll
            -- gets clamped by View:clamp_scroll_position.
            let_it_finish = true
            -- We need to restart the process because if TreeView:toggle_expand
            -- altered the cache, TreeView:each_item risks looping indefinitely.
            goto restart
          end
        end
      else
        if item.abs_filename == path then
          to_select, to_select_y = item, y
          done = true
          if not let_it_finish then break end
        end
      end
    end
  end
  if to_select then
    self:set_selection(to_select, scroll_to and to_select_y, true, instant)
  end
  return to_select
end


function TreeView:get_text_bounding_box(item, x, y, w, h)
  local icon_width = style.icon_font:get_width("D")
  local xoffset = item.depth * style.padding.x + style.padding.x + icon_width
  x = x + xoffset
  w = style.font:get_width(item.name) + 2 * style.padding.x
  return x, y, w, h
end



function TreeView:on_mouse_moved(px, py, ...)
  if not self.visible then return end
  if TreeView.super.on_mouse_moved(self, px, py, ...) then
    -- mouse movement handled by the View (scrollbar)
    self.hovered_item = nil
    return
  end

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


function TreeView:on_mouse_left()
  TreeView.super.on_mouse_left(self)
  self.hovered_item = nil
end


function TreeView:update()
  -- update width
  local dest = self.visible and self.target_size or 0
  if self.init_size then
    self.size.x = dest
    self.init_size = false
  else
    self:move_towards(self.size, "x", dest, nil, "treeview")
  end

  if self.size.x == 0 or self.size.y == 0 or not self.visible then return end

  local duration = system.get_time() - self.tooltip.begin
  if self.hovered_item and self.tooltip.x and duration > tooltip_delay then
    self:move_towards(self.tooltip, "alpha", tooltip_alpha, tooltip_alpha_rate, "treeview")
  else
    self.tooltip.alpha = 0
  end

  self.item_icon_width = style.icon_font:get_width("D")
  self.item_text_spacing = style.icon_font:get_width("f") / 2

  -- this will make sure hovered_item is updated
  local dy = math.abs(self.last_scroll_y - self.scroll.y)
  if dy > 0 then
    self:on_mouse_moved(core.root_view.mouse.x, core.root_view.mouse.y, 0, 0)
    self.last_scroll_y = self.scroll.y
  end

  local config = config.plugins.treeview
  if config.highlight_focused_file then
    -- Try to only highlight when we actually change tabs
    local current_node = core.root_view:get_active_node()
    local current_active_view = core.active_view
    if current_node and not current_node.locked
     and current_active_view ~= self and current_active_view ~= self.last_active_view then
      self.selected_item = nil
      self.last_active_view = current_active_view
      if DocView:is_extended_by(current_active_view) then
        local abs_filename = current_active_view.doc
                             and current_active_view.doc.abs_filename or ""
        self:set_selection_to_path(abs_filename,
                                   config.expand_dirs_to_focused_file,
                                   config.scroll_to_focused_file,
                                   not config.animate_scroll_to_focused_file)
      end
    end
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


function TreeView:get_item_icon(item, active, hovered)
  local character = "f"
  if item.type == "dir" then
    character = item.expanded and "D" or "d"
  end
  local font = style.icon_font
  local color = style.text
  if active or hovered then
    color = style.accent
  end
  return character, font, color
end

function TreeView:get_item_text(item, active, hovered)
  local text = item.name
  local font = style.font
  local color = style.text
  if active or hovered then
    color = style.accent
  end
  return text, font, color
end


function TreeView:draw_item_text(item, active, hovered, x, y, w, h)
  local item_text, item_font, item_color = self:get_item_text(item, active, hovered)
  common.draw_text(item_font, item_color, item_text, nil, x, y, 0, h)
end


function TreeView:draw_item_icon(item, active, hovered, x, y, w, h)
  local icon_char, icon_font, icon_color = self:get_item_icon(item, active, hovered)
  common.draw_text(icon_font, icon_color, icon_char, nil, x, y, 0, h)
  return self.item_icon_width + self.item_text_spacing
end


function TreeView:draw_item_body(item, active, hovered, x, y, w, h)
    x = x + self:draw_item_icon(item, active, hovered, x, y, w, h)
    self:draw_item_text(item, active, hovered, x, y, w, h)
end


function TreeView:draw_item_chevron(item, active, hovered, x, y, w, h)
  if item.type == "dir" then
    local chevron_icon = item.expanded and "-" or "+"
    local chevron_color = hovered and style.accent or style.text
    common.draw_text(style.icon_font, chevron_color, chevron_icon, nil, x, y, 0, h)
  end
  return style.padding.x
end


function TreeView:draw_item_background(item, active, hovered, x, y, w, h)
  if hovered then
    local hover_color = { table.unpack(style.line_highlight) }
    hover_color[4] = 160
    renderer.draw_rect(x, y, w, h, hover_color)
  elseif active then
    renderer.draw_rect(x, y, w, h, style.line_highlight)
  end
end


function TreeView:draw_item(item, active, hovered, x, y, w, h)
  self:draw_item_background(item, active, hovered, x, y, w, h)

  x = x + item.depth * style.padding.x + style.padding.x
  x = x + self:draw_item_chevron(item, active, hovered, x, y, w, h)

  self:draw_item_body(item, active, hovered, x, y, w, h)
end


function TreeView:draw()
  if not self.visible then return end
  self:draw_background(style.background2)
  local _y, _h = self.position.y, self.size.y

  for item, x,y,w,h in self:each_item() do
    if y + h >= _y and y < _y + _h then
      self:draw_item(item,
        item == self.selected_item,
        item == self.hovered_item,
        x, y, w, h)
    end
  end

  self:draw_scrollbar()
  if self.hovered_item and self.tooltip.x and self.tooltip.alpha > 0 then
    core.root_view:defer_draw(self.draw_tooltip, self)
  end
end


function TreeView:get_parent(item)
  local parent_path = common.dirname(item.abs_filename)
  if not parent_path then return end
  for it, _, y in self:each_item() do
    if it.abs_filename == parent_path then
      return it, y
    end
  end
end


function TreeView:get_item(item, where)
  local last_item, last_x, last_y, last_w, last_h
  local stop = false

  for it, x, y, w, h in self:each_item() do
    if not item and where >= 0 then
      return it, x, y, w, h
    end
    if item == it then
      if where < 0 and last_item then
        break
      elseif where == 0 or (where < 0 and not last_item) then
        return it, x, y, w, h
      end
      stop = true
    elseif stop then
      item = it
      return it, x, y, w, h
    end
    last_item, last_x, last_y, last_w, last_h = it, x, y, w, h
  end
  return last_item, last_x, last_y, last_w, last_h
end

function TreeView:get_next(item)
  return self:get_item(item, 1)
end

function TreeView:get_previous(item)
  return self:get_item(item, -1)
end


function TreeView:toggle_expand(toggle, item)
  item = item or self.selected_item

  if not item then return end

  if item.type == "dir" then
    if type(toggle) == "boolean" then
      item.expanded = toggle
    else
      item.expanded = not item.expanded
    end
    local hovered_dir = core.project_dir_by_name(item.dir_name)
    if hovered_dir and hovered_dir.files_limit then
      core.update_project_subdir(hovered_dir, item.depth == 0 and "" or item.filename, item.expanded)
    end
  end
end


function TreeView:open_doc(filename)
  core.root_view:open_doc(core.open_doc(filename))
end


-- init
local view = TreeView()
local node = core.root_view:get_active_node()
view.node = node:split("left", view, {x = true}, true)

-- The toolbarview plugin is special because it is plugged inside
-- a treeview pane which is itelf provided in a plugin.
-- We therefore break the usual plugin's logic that would require each
-- plugin to be independent of each other. In addition it is not the
-- plugin module that plug itself in the active node but it is plugged here
-- in the treeview node.
local toolbar_view = nil
local toolbar_plugin, ToolbarView = pcall(require, "plugins.toolbarview")
if config.plugins.toolbarview ~= false and toolbar_plugin then
  toolbar_view = ToolbarView()
  view.node:split("down", toolbar_view, {y = true})
  local min_toolbar_width = toolbar_view:get_min_width()
  view:set_target_size("x", math.max(config.plugins.treeview.size, min_toolbar_width))
  command.add(nil, {
    ["toolbar:toggle"] = function()
      toolbar_view:toggle_visible()
    end,
  })
end

-- Add a context menu to the treeview
local menu = ContextMenu()

local on_view_mouse_pressed = RootView.on_view_mouse_pressed
local on_mouse_moved = RootView.on_mouse_moved
local root_view_update = RootView.update
local root_view_draw = RootView.draw

function RootView:on_mouse_moved(...)
  if menu:on_mouse_moved(...) then return end
  on_mouse_moved(self, ...)
end

function RootView.on_view_mouse_pressed(button, x, y, clicks)
  -- We give the priority to the menu to process mouse pressed events.
  if button == "right" then
    view.tooltip.alpha = 0
    view.tooltip.x, view.tooltip.y = nil, nil
  end
  local handled = menu:on_mouse_pressed(button, x, y, clicks)
  return handled or on_view_mouse_pressed(button, x, y, clicks)
end

function RootView:update(...)
  root_view_update(self, ...)
  menu:update()
end

function RootView:draw(...)
  root_view_draw(self, ...)
  menu:draw()
end

local on_quit_project = core.on_quit_project
function core.on_quit_project()
  view.cache = {}
  on_quit_project()
end

local function is_project_folder(path)
  for _,dir in pairs(core.project_directories) do
    if dir.name == path then
      return true
    end
  end
  return false
end

local function is_primary_project_folder(path)
  return core.project_dir == path
end


local function treeitem() return view.hovered_item or view.selected_item end


menu:register(function() return core.active_view:is(TreeView) and treeitem() end, {
  { text = "Open in System", command = "treeview:open-in-system" },
  ContextMenu.DIVIDER
})

menu:register(
  function()
    local item = treeitem()
    return core.active_view:is(TreeView) and item and not is_project_folder(item.abs_filename)
  end,
  {
    { text = "Rename", command = "treeview:rename" },
    { text = "Delete", command = "treeview:delete" },
  }
)

menu:register(
  function()
    local item = treeitem()
    return core.active_view:is(TreeView) and item and item.type == "dir"
  end,
  {
    { text = "New File", command = "treeview:new-file" },
    { text = "New Folder", command = "treeview:new-folder" },
  }
)

menu:register(
  function()
    local item = treeitem()
    return core.active_view:is(TreeView) and item
      and not is_primary_project_folder(item.abs_filename)
      and is_project_folder(item.abs_filename)
  end,
  {
    { text = "Remove directory", command = "treeview:remove-project-directory" },
  }
)

local previous_view = nil

-- Register the TreeView commands and keymap
command.add(nil, {
  ["treeview:toggle"] = function()
    view.visible = not view.visible
  end,

  ["treeview:toggle-focus"] = function()
    if not core.active_view:is(TreeView) then
      if core.active_view:is(CommandView) then
        previous_view = core.last_active_view
      else
        previous_view = core.active_view
      end
      if not previous_view then
        previous_view = core.root_view:get_primary_node().active_view
      end
      core.set_active_view(view)
      if not view.selected_item then
        for it, _, y in view:each_item() do
          view:set_selection(it, y)
          break
        end
      end

    else
      core.set_active_view(
        previous_view or core.root_view:get_primary_node().active_view
      )
    end
  end
})

command.add(
  function()
    return not menu.show_context_menu and core.active_view:extends(TreeView), TreeView
  end, {
  ["treeview:next"] = function()
    local item, _, item_y = view:get_next(view.selected_item)
    view:set_selection(item, item_y)
  end,

  ["treeview:previous"] = function()
    local item, _, item_y = view:get_previous(view.selected_item)
    view:set_selection(item, item_y)
  end,

  ["treeview:open"] = function()
    local item = view.selected_item
    if not item then return end
    if item.type == "dir" then
      view:toggle_expand()
    else
      core.try(function()
        if core.last_active_view and core.active_view == view then
          core.set_active_view(core.last_active_view)
        end
        view:open_doc(core.normalize_to_project_dir(item.abs_filename))
      end)
    end
  end,

  ["treeview:deselect"] = function()
    view.selected_item = nil
  end,

  ["treeview:select"] = function()
    view:set_selection(view.hovered_item)
  end,

  ["treeview:select-and-open"] = function()
    if view.hovered_item then
      view:set_selection(view.hovered_item)
      command.perform "treeview:open"
    end
  end,

  ["treeview:collapse"] = function()
    if view.selected_item then
      if view.selected_item.type == "dir" and view.selected_item.expanded then
        view:toggle_expand(false)
      else
        local parent_item, y = view:get_parent(view.selected_item)
        if parent_item then
          view:set_selection(parent_item, y)
        end
      end
    end
  end,

  ["treeview:expand"] = function()
    local item = view.selected_item
    if not item or item.type ~= "dir" then return end

    if item.expanded then
      local next_item, _, next_y = view:get_next(item)
      if next_item.depth > item.depth then
        view:set_selection(next_item, next_y)
      end
    else
      view:toggle_expand(true)
    end
  end,

  ["treeview-context:show"] = function()
    if view.hovered_item then
      menu:show(core.root_view.mouse.x, core.root_view.mouse.y)
      return
    end

    local item = view.selected_item
    if not item then return end

    local x, y
    for _i, _x, _y, _w, _h in view:each_item() do
      if _i == item then
        x = _x + _w / 2
        y = _y + _h / 2
        break
      end
    end
    menu:show(x, y)
  end
})


command.add(
  function()
    local item = treeitem()
    return item ~= nil and (core.active_view == view or menu.show_context_menu), item
  end, {
  ["treeview:delete"] = function(item)
    local filename = item.abs_filename
    local relfilename = item.filename
    if item.dir_name ~= core.project_dir then
      -- add secondary project dirs names to the file path to show
      relfilename = common.basename(item.dir_name) .. PATHSEP .. relfilename
    end
    local file_info = system.get_file_info(filename)
    local file_type = file_info.type == "dir" and "Directory" or "File"
    -- Ask before deleting
    local opt = {
      { text = "Yes", default_yes = true },
      { text = "No", default_no = true }
    }
    core.nag_view:show(
      string.format("Delete %s", file_type),
      string.format(
        "Are you sure you want to delete the %s?\n%s: %s",
        file_type:lower(), file_type, relfilename
      ),
      opt,
      function(item)
        if item.text == "Yes" then
          if file_info.type == "dir" then
            local deleted, error, path = common.rm(filename, true)
            if not deleted then
              core.error("Error: %s - \"%s\" ", error, path)
              return
            end
          else
            local removed, error = os.remove(filename)
            if not removed then
              core.error("Error: %s - \"%s\"", error, filename)
              return
            end
          end
          core.log("Deleted \"%s\"", filename)
        end
      end
    )
  end,

  ["treeview:rename"] = function(item)
    local old_filename = item.filename
    local old_abs_filename = item.abs_filename
    core.command_view:enter("Rename", {
      text = old_filename,
      submit = function(filename)
        local abs_filename = filename
        if not common.is_absolute_path(filename) then
          abs_filename = item.dir_name .. PATHSEP .. filename
        end
        local res, err = os.rename(old_abs_filename, abs_filename)
        if res then -- successfully renamed
          for _, doc in ipairs(core.docs) do
            if doc.abs_filename and old_abs_filename == doc.abs_filename then
              doc:set_filename(filename, abs_filename) -- make doc point to the new filename
              doc:reset_syntax()
              break -- only first needed
            end
          end
          core.log("Renamed \"%s\" to \"%s\"", old_filename, filename)
        else
          core.error("Error while renaming \"%s\" to \"%s\": %s", old_abs_filename, abs_filename, err)
        end
      end,
      suggest = function(text)
        return common.path_suggest(text, item.dir_name)
      end
    })
  end,

  ["treeview:new-file"] = function(item)
    local text
    if not is_project_folder(item.abs_filename) then
      if item.type == "dir" then
        text = item.filename .. PATHSEP
      elseif item.type == "file" then
        local parent_dir = common.dirname(item.filename)
        text = parent_dir and parent_dir .. PATHSEP
      end
    end
    core.command_view:enter("Filename", {
      text = text,
      submit = function(filename)
        local doc_filename = item.dir_name .. PATHSEP .. filename
        core.log(doc_filename)
        local file = io.open(doc_filename, "a+")
        file:write("")
        file:close()
        view:open_doc(doc_filename)
        core.log("Created %s", doc_filename)
      end,
      suggest = function(text)
        return common.path_suggest(text, item.dir_name)
      end
    })
  end,

  ["treeview:new-folder"] = function(item)
    local text
    if not is_project_folder(item.abs_filename) then
      if item.type == "dir" then
        text = item.filename .. PATHSEP
      elseif item.type == "file" then
        local parent_dir = common.dirname(item.filename)
        text = parent_dir and parent_dir .. PATHSEP
      end
    end
    core.command_view:enter("Folder Name", {
      text = text,
      submit = function(filename)
        local dir_path = item.dir_name .. PATHSEP .. filename
        common.mkdirp(dir_path)
        core.log("Created %s", dir_path)
      end,
      suggest = function(text)
        return common.path_suggest(text, item.dir_name)
      end
    })
  end,

  ["treeview:open-in-system"] = function(item)
    if PLATFORM == "Windows" then
      system.exec(string.format("start \"\" %q", item.abs_filename))
    elseif string.find(PLATFORM, "Mac") then
      system.exec(string.format("open %q", item.abs_filename))
    elseif PLATFORM == "Linux" or string.find(PLATFORM, "BSD") then
      system.exec(string.format("xdg-open %q", item.abs_filename))
    end
  end
})

local projectsearch = pcall(require, "plugins.projectsearch")
if projectsearch then
  menu:register(function()
    local item = treeitem()
    return item and item.type == "dir"
  end, {
    { text = "Find in directory", command = "treeview:search-in-directory" }
  })
  command.add(function()
    return view.hovered_item and view.hovered_item.type == "dir"
  end, {
    ["treeview:search-in-directory"] = function(item)
      command.perform("project-search:find", view.hovered_item.abs_filename)
    end
  })
end

command.add(function()
    local item = treeitem()
    return item
           and not is_primary_project_folder(item.abs_filename)
           and is_project_folder(item.abs_filename), item
  end, {
  ["treeview:remove-project-directory"] = function(item)
    core.remove_project_directory(item.dir_name)
  end,
})


command.add(
  function()
    return menu.show_context_menu == true and core.active_view:is(TreeView)
  end, {
  ["treeview-context:focus-previous"] = function()
    menu:focus_previous()
  end,
  ["treeview-context:focus-next"] = function()
    menu:focus_next()
  end,
  ["treeview-context:hide"] = function()
    menu:hide()
  end,
  ["treeview-context:on-selected"] = function()
    menu:call_selected_item()
  end,
})


keymap.add {
  ["ctrl+\\"]     = "treeview:toggle",
  ["up"]          = "treeview:previous",
  ["down"]        = "treeview:next",
  ["left"]        = "treeview:collapse",
  ["right"]       = "treeview:expand",
  ["return"]      = "treeview:open",
  ["escape"]      = "treeview:deselect",
  ["delete"]      = "treeview:delete",
  ["ctrl+return"] = "treeview:new-folder",
  ["lclick"]      = "treeview:select-and-open",
  ["mclick"]      = "treeview:select",
  ["ctrl+lclick"] = "treeview:new-folder"
}

keymap.add {
  ["menu"]   = "treeview-context:show",
  ["return"] = "treeview-context:on-selected",
  ["up"]     = "treeview-context:focus-previous",
  ["down"]   = "treeview-context:focus-next",
  ["escape"] = "treeview-context:hide"
}


-- The config specification used by gui generators
config.plugins.treeview.config_spec = {
  name = "Treeview",
  {
    label = "Size",
    description = "Default treeview width.",
    path = "size",
    type = "number",
    default = toolbar_view and math.ceil(toolbar_view:get_min_width() / SCALE)
      or 200 * SCALE,
    min = toolbar_view and toolbar_view:get_min_width() / SCALE
      or 200 * SCALE,
    get_value = function(value)
      return value / SCALE
    end,
    set_value = function(value)
      return value * SCALE
    end,
    on_apply = function(value)
      view:set_target_size("x", math.max(
        value, toolbar_view and toolbar_view:get_min_width() or 200 * SCALE
      ))
    end
  },
  {
    label = "Hide on Startup",
    description = "Show or hide the treeview on startup.",
    path = "visible",
    type = "toggle",
    default = false,
    on_apply = function(value)
      view.visible = not value
    end
  }
}

-- Return the treeview with toolbar and contextmenu to allow
-- user or plugin modifications
view.toolbar = toolbar_view
view.contextmenu = menu

return view
