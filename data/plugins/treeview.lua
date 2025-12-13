-- mod-version:4
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
local Dirwatch = require "core.dirwatch"

config.plugins.treeview = common.merge({
  -- Default treeview width
  size = 200 * SCALE,
  highlight_focused_file = true,
  expand_dirs_to_focused_file = false,
  scroll_to_focused_file = false,
  animate_scroll_to_focused_file = true,
  show_hidden = false,
  show_ignored = true,
  visible = true
}, config.plugins.treeview)

local tooltip_offset = style.font:get_height()
local tooltip_border = 1
local tooltip_delay = 0.5
local tooltip_alpha = 255
local tooltip_alpha_rate = 1


local function get_depth(filename)
  if filename == "" then return 0 end
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

function TreeView:__tostring() return "TreeView" end

function TreeView:new()
  TreeView.super.new(self)
  self.scrollable = true
  self.visible = config.plugins.treeview.visible
  self.init_size = true
  self.target_size = config.plugins.treeview.size
  self.show_hidden = config.plugins.treeview.show_hidden
  self.show_ignored = config.plugins.treeview.show_ignored
  self.cache = {}
  self.expanded = {}
  self.tooltip = { x = 0, y = 0, begin = 0, alpha = 0 }
  self.last_scroll_y = 0

  self.item_icon_width = 0
  self.item_text_spacing = 0
  self.watches = { }
end


function TreeView:set_target_size(axis, value)
  if axis == "x" then
    self.target_size = value
    return true
  end
end



function TreeView:get_cached(project, path)
  local t = self.cache[path]
  if not t then
    if not self.watches[project] then self.watches[project] = Dirwatch.new() end
    local truncated = path:sub(#project.path + 2)
    local basename = common.basename(path)
    local info
    if self.show_ignored then
      info = system.get_file_info(path)
    else
      info = project:get_file_info(path)
    end
    if not info then return nil end
    t = {
      filename = basename,
      depth = get_depth(truncated),
      abs_filename = path,
      project = project,
      name = basename,
      type = info.type,
      project = project,
      ignored = self.show_ignored and project:is_ignored(info, path)
    }
    if self.expanded[path] ~= nil then 
      t.expanded = self.expanded[path]
    else 
      t.expanded = (info.type == "dir" and #truncated <= 1) 
    end
    if t.expanded then self.watches[project]:watch(path) end
    self.cache[path] = t
  end
  if t.expanded and t.type == "dir" and not t.files then
    t.files = {}
    for i, file in ipairs(system.list_dir(path)) do
      local l = path .. PATHSEP .. file
      local f
      if self.show_ignored then
        f = system.get_file_info(l)
      else
        f = project:get_file_info(l)
      end
      if f and f.type then
        f.name = file
        f.abs_filename = l
        f.ignored = self.show_ignored and project:is_ignored(f, l)
        table.insert(t.files, f)
      end
      self.cache[l] = nil
    end
    table.sort(t.files, function(a, b) return system.path_compare(a.name, a.type, b.name, b.type) end)
  end
  return t
end


function TreeView:get_name()
  return nil
end


function TreeView:get_item_height()
  return style.font:get_height() + style.padding.y
end


function TreeView:get_items(project, path, x, y, w, h)
  local dir = self:get_cached(project, path)
  coroutine.yield(dir, x, y, w, h)
  local count_lines = 1
  if dir and dir.files and dir.expanded then
    for i, file in ipairs(dir.files) do
      if self.show_hidden or not file.name:find("^%.") then
        count_lines = count_lines + self:get_items(project, path .. PATHSEP .. file.name, x, y + count_lines * h, w, h)
      end
    end
  end
  return count_lines
end


function TreeView:each_item()
  return coroutine.wrap(function()
    local count_lines = 0
    local ox, oy = self:get_content_offset()
    local h = self:get_item_height()
    for k, project in ipairs(core.projects) do
      count_lines = count_lines + self:get_items(project, project.path, ox, oy + style.padding.y + h * count_lines, self.size.x, h)
    end
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
  elseif item.ignored then
    color = style.dim
  end
  return character, font, color
end

function TreeView:get_item_text(item, active, hovered)
  local text = item.name
  local font = style.font
  local color = style.text
  if active or hovered then
    color = style.accent
  elseif item.ignored then
    color = style.dim
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
    self.expanded[item.abs_filename] = item.expanded
    if self.watches[item.project] then
      self.watches[item.project]:watch(item.abs_filename, item.expanded)
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


local old_remove_project = core.remove_project
function core.remove_project(project, force)
  local project = old_remove_project(project, force)
  view.cache = {}
  view.watches[project] = nil
end

core.add_thread(function()
  while true do
    for k,v in pairs(view.watches) do
      v:check(function(directory)
        view.cache[directory] = nil
      end)
    end
    coroutine.yield(0.01)
  end
end)

local on_quit_project = core.on_quit_project
function core.on_quit_project()
  view.cache = {}
  on_quit_project()
end

local function is_project_folder(item)
  return item.abs_filename == item.project.path
end

local function is_primary_project_folder(path)
  return core.root_project().path == path
end


local function treeitem() return view.hovered_item or view.selected_item end

function TreeView:on_context_menu()
  return { items = {
    { text = "Open in System", command = "treeview:open-in-system" },
    ContextMenu.DIVIDER,
    { text = "Rename", command = "treeview:rename" },
    { text = "Delete", command = "treeview:delete" },
    { text = "New File", command = "treeview:new-file" },
    { text = "New Folder", command = "treeview:new-folder" },
    { text = "Remove directory", command = "treeview:remove-project-directory" },
    { text = "Find in Directory", command = "treeview:search-in-directory" }
  } }, self
end

local projectsearch = pcall(require, "plugins.projectsearch")
if projectsearch then
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
  return not is_project_folder(item), item
end, {
  ["treeview:delete"] = function(item)
    local filename = item.abs_filename
    local relfilename = item.filename
    if item.project ~= core.root_project() then
      -- add secondary project dirs names to the file path to show
      relfilename = common.basename(item.abs_filename) .. PATHSEP .. relfilename
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
    local old_filename = core.normalize_to_project_dir(item.abs_filename)
    local old_abs_filename = item.abs_filename
    core.command_view:enter("Rename", {
      text = old_filename,
      submit = function(filename)
        local abs_filename = item.project:absolute_path(filename)
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
        return common.path_suggest(text, item.project and item.project.path)
      end
    })
  end
})

local previous_view = nil

-- Register the TreeView commands and keymap
command.add(nil, {
  ["treeview:toggle"] = function()
    view.visible = not view.visible
  end,

  ["treeview:toggle-hidden"] = function()
    view.show_hidden = not view.show_hidden
    view.cache = {}
  end,

  ["treeview:toggle-ignored"] = function()
    view.show_ignored = not view.show_ignored
    view.cache = {}
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

command.add(TreeView, {
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
})


command.add(
  function(active_view)
    local item = treeitem()
    return item ~= nil and (active_view or core.active_view) == view, item
  end, {

  ["treeview:new-file"] = function(item)
    local text
    if not is_project_folder(item) then
      if item.type == "dir" then
        text = item.project:normalize_path(item.abs_filename) .. PATHSEP
      elseif item.type == "file" then
        text = item.project:normalize_path(common.dirname(item.abs_filename)) .. PATHSEP
      end
    end
    core.command_view:enter("Filename", {
      text = text,
      submit = function(filename)
        local doc_filename = item.project:absolute_path(filename)
        local file, err = io.open(doc_filename, "a+")
        if not file then
          core.error("Error: unable to create a new file in \"%s\": %s", doc_filename, err)
          return
        end
        file:close()
        view:open_doc(doc_filename)
        core.log("Created %s", doc_filename)
      end,
      suggest = function(text)
        return common.path_suggest(text, item.project and item.project.path)
      end
    })
  end,

  ["treeview:new-folder"] = function(item)
    local text
    if not is_project_folder(item) then
      if item.type == "dir" then
        text = item.project:normalize_path(item.abs_filename) .. PATHSEP
      elseif item.type == "file" then
        text = item.project:normalize_path(common.dirname(item.abs_filename)) .. PATHSEP
      end
    end
    core.command_view:enter("Folder Name", {
      text = text,
      submit = function(filename)
        local dir_path = item.project:absolute_path(filename)
        common.mkdirp(dir_path)
        core.log("Created %s", dir_path)
      end,
      suggest = function(text)
        return common.path_suggest(text, item.project and item.project.path)
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

command.add(function()
    local item = treeitem()
    return item
      and not is_primary_project_folder(item.abs_filename)
      and is_project_folder(item), item
  end, {
  ["treeview:remove-project-directory"] = function(item)
    core.remove_project(item.project)
  end,
})



keymap.add {
  ["ctrl+\\"]     = "treeview:toggle",
  ["ctrl+h"]      = "treeview:toggle-hidden",
  ["ctrl+i"]      = "treeview:toggle-ignored",
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

return view
