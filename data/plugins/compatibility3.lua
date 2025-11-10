--mod-version:4 --priority:-3
local core = require "core"
local config = require "core.config"
local command = require "core.command"
local View = require "core.view"
local Node = require "core.node"
local Doc = require "core.doc"
local CommandView = require "core.commandview"
local StatusView = require "core.statusview"
local ContextMenu = require "core.contextmenu"
local TreeView = require "plugins.treeview"


---Helper function to merge deprecated items to a temp items table.
---@param destination table
---@param items core.statusview.styledtext
---@param alignment core.statusview.item.alignment
local function merge_deprecated_items(destination, items, alignment)
  local start = true
  local items_start, items_end = {}, {}
  for i, value in ipairs(items) do
    if value ~= "{:dummy:}" then
      if start then
        table.insert(items_start, i, value)
      else
        table.insert(items_end, value)
      end
    else
      start = false
    end
  end

  local position = alignment == StatusView.Item.LEFT and "left" or "right"

  local item_start = StatusView.Item({
    name = "deprecated:"..position.."-start",
    alignment = alignment,
    get_item = items_start
  })

  local item_end = StatusView.Item({
    name = "deprecated:"..position.."-end",
    alignment = alignment,
    get_item = items_end
  })

  table.insert(destination, 1, item_start)
  table.insert(destination, item_end)
end

---Older method of retrieving the status bar items and which is now
---deprecated in favour of core.status_view:add_item().
---@deprecated
---@param nowarn boolean
---@return table left
---@return table right
function StatusView:get_items(nowarn)
  if not nowarn and not self.get_items_warn then
    core.warn(
      "Overriding StatusView:get_items() is deprecated, "
      .. "use core.status_view:add_item() instead."
    )
    self.get_items_warn = true
  end
  return {"{:dummy:}"}, {"{:dummy:}"}
end


local old_get_combined_items = StatusView.get_combined_items
function StatusView:get_combined_items()
    local combined_items = old_get_combined_items(self)

    -- load deprecated items for compatibility
    local dleft, dright = self:get_items(true)
    merge_deprecated_items(combined_items, dleft, StatusView.Item.LEFT)
    merge_deprecated_items(combined_items, dright, StatusView.Item.RIGHT)
    return combined_items
end


function CommandView:set_hidden_suggestions()
  core.deprecation_log("CommandView:set_hidden_suggestions")
  self.state.show_suggestions = false
end
core.add_thread(function()
  if config.draw_whitespace ~= nil then
    core.warn("config.drawwhitespace is deprecated, use the drawwhitespace plugin instead")
  end
end)

local old_command_view_enter = CommandView.enter
function CommandView:enter(label, ...)
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
  local old_text = self:get_text()
  if old_text ~= "" then
    core.deprecation_log("CommandView:set_text")
  end
  -- We need to keep the text entered with CommandView:set_text to
  -- maintain compatibility with deprecated usage, but still allow
  -- overwriting with options.text
  if not options.text or options.select_text then
    options.text = old_text
  end
  return old_command_view_enter(self, label, options)
end
  
function Node:on_mouse_moved(x, y, ...)
  core.deprecation_log("Node:on_mouse_moved")
  if self.type == "leaf" then
    self.active_view:on_mouse_moved(x, y, ...)
  else
    self:propagate("on_mouse_moved", x, y, ...)
  end
end


function Node:on_mouse_released(...)
  core.deprecation_log("Node:on_mouse_released")
  if self.type == "leaf" then
    self.active_view:on_mouse_released(...)
  else
    self:propagate("on_mouse_released", ...)
  end
end


function Node:on_mouse_left()
  core.deprecation_log("Node:on_mouse_left")
  if self.type == "leaf" then
    self.active_view:on_mouse_left()
  else
    self:propagate("on_mouse_left")
  end
end


function Node:on_touch_moved(...)
  core.deprecation_log("Node:on_touch_moved")
  if self.type == "leaf" then
    self.active_view:on_touch_moved(...)
  else
    self:propagate("on_touch_moved", ...)
  end
end



function core.normalize_to_project_dir(path) 
  core.deprecation_log("core.normalize_to_project_dir") 
  return core.root_project():normalize_path(path) 
end

function core.project_absolute_path(path) 
  core.deprecation_log("core.project_absolute_path") 
  return core.root_project() and core.root_project():absolute_path(path) or system.absolute_path(path) 
end


function core.push_clip_rect(...)
  core.active_window():push_clip_rect(...)
end

function core.pop_clip_rect(...)
  core.active_window():pop_clip_rect(...)
end

local old_command_perform = command.perform
function command.perform(name, ...)
  if select('#', ...) == 0 then
    return old_command_perform(name, core.active_window().root_view, ...)
  end
  return old_command_perform(name, ...)
end

for _, plugin in ipairs(core.plugin_list) do
  if plugin.version and plugin.version[1] == 3 then
    plugin.version_match = true
  end
end


-- Support old method of defining context menus.
-- Added in for TreeView extender.
local old_new = View.new
function View:new()
  old_new(self)
  self.context_menu_items = {}
  self.contextmenu = {
    divider = ContextMenu.DIVIDER,
    register = function(_, predicate, items)
      table.insert(self.context_menu_items, { predicate = predicate, items = items })
    end
  }
  if getmetatable(self) == TreeView then
    TreeView.contextmenu = self.contextmenu
  end
  self.on_context_menu = function(self, x, y)
    local on_context_menu = getmetatable(self).on_context_menu
    local menu = on_context_menu(self, x, y)
    for _, group in ipairs(self.context_menu_items) do
      if group.predicate(self, x, y) then
        for _, v in ipairs(group.items) do
          table.insert(menu.items, v)
        end
      end
    end
    return menu
  end
end

local treemt = getmetatable(TreeView)
local old_treeview_index = treemt.__index
function treemt:__index(key)
  return old_treeview_index[key] or (core.active_window() and core.active_window().root_view.treeview and rawget(core.active_window().root_view.treeview, key))
end


-- Added in specifically for plugins that use old Doc selections.
-- Like LSP, Widget, etc..
local old_doc_index = Doc.__index
function Doc:__index(key) 
  local result = rawget(Doc, key)
  if result then return result end
  local view = core.get_views_referencing_doc(self)[1]
  if not view or view[key] == nil then return nil end
  core.deprecation_log("doc." .. key)
  if type(view[key]) == 'function' then
    return function(doc, ...) return view[key](view, ...) end
  end
  return view[key]
end
function Doc:__newindex(key, value) 
  local view = core.get_views_referencing_doc(self)[1]
  if view and view[key] then
    core.deprecation_log("set doc." .. key)
    view[key] = value
  else
    rawset(self, key, value)
  end
end

setmetatable(core, {
  __index = function(self, key)
    local root_view = core.active_window() and core.active_window().root_view
    if key == "root_view" then
      core.deprecation_log("core." .. key)
      return root_view
    elseif key == "project_dir" then
      core.deprecation_log("core." .. key)
      return core.projects[1].path
    elseif root_view and root_view[key] then
      core.deprecation_log("core." .. key)
      return root_view[key]
    end
    return nil
  end
});
