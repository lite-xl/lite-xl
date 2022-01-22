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

if require("plugins.scale") then
  menu:register("core.docview", {
    { text = "Cut",         command = "doc:cut" },
    { text = "Copy",        command = "doc:copy" },
    { text = "Paste",       command = "doc:paste" },
    { text = "Font +",      command = "scale:increase" },
    { text = "Font -",      command = "scale:decrease" },
    { text = "Font Reset",  command = "scale:reset"    },
    ContextMenu.DIVIDER,
    { text = "Find",        command = "find-replace:find"    },
    { text = "Replace",     command = "find-replace:replace" }
  })
end

return menu
