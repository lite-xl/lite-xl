local core = require "core"
local command = require "core.command"
local ContextMenu = require "core.contextmenu"

command.add(function(x, y)
  local view = x and y and type(x) == 'number' and type(y) == 'number' and core.root_view.root_node:get_child_overlapping_point(x, y).active_view
  if not view then return nil end
  local results = { view:on_context_menu() }
  return results and results[1] and #results[1] > 0, x, y, table.unpack(results)
end, {
  ['context-menu:show'] = function(x, y, items, ...)
    core.root_view.context_menu:show(x, y, items, ...)
  end
})

command.add(ContextMenu, {
  ['context-menu:focus-previous'] = function(context_menu)
    context_menu:focus_previous()
  end,
  ['context-menu:focus-next'] = function(context_menu)
    context_menu:focus_next()
  end,
  ['context-menu:hide'] = function(context_menu)
    context_menu:hide()
  end
})

command.add(function()
  local item = core.active_view:is(ContextMenu) and core.active_view:get_item_selected()
  return item, core.root_view.context_menu
end, {
  ['context-menu:select'] = function(context_menu)
    if item.command then
      context_menu:on_selected(context_menu:get_item_selected())
      context_menu:hide()
    end
  end
})

