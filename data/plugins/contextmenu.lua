-- mod-version:2 -- lite-xl 2.0
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"
local ContextMenu = require "core.contextmenu"
local RootView = require "core.rootview"

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

command.add(nil, {
  ["context:show"] = function()
    menu:show(core.active_view.position.x, core.active_view.position.y)
  end
})

keymap.add {
  ["menu"] = "context:show"
}

local function copy_log()
  local item = core.active_view.hovered_item
  if item then
    system.set_clipboard(core.get_log(item))
  end
end

local function open_as_doc()
  local doc = core.open_doc("logs.txt")
  core.root_view:open_doc(doc)
  doc:insert(1, 1, core.get_log())
end

menu:register("core.logview", {
  { text = "Copy entry", command = copy_log },
  { text = "Open as file", command = open_as_doc }
})

if require("plugins.scale") then
  menu:register("core.docview", {
    { text = "Font +",     command = "scale:increase" },
    { text = "Font -",     command = "scale:decrease" },
    { text = "Font Reset", command = "scale:reset"    },
    ContextMenu.DIVIDER,
    { text = "Find",       command = "find-replace:find"    },
    { text = "Replace",    command = "find-replace:replace" },
    ContextMenu.DIVIDER,
    { text = "Find Pattern",    command = "find-replace:find-pattern"    },
    { text = "Replace Pattern", command = "find-replace:replace-pattern" },
  })
end

return menu
