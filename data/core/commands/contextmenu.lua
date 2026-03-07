local core = require "core"
local command = require "core.command"
local ContextMenu = require "core.contextmenu"

command.add(function(root_view, options)
  local x, y = options.x, options.y
  if not x and not y then x, y = root_view.mouse.x, root_view.mouse.y end
  local view = x and y and type(x) == 'number' and type(y) == 'number' and root_view.root_node:get_child_overlapping_point(x, y).active_view
  local results = view and view:on_context_menu(x, y)
  if not results then return nil end
  return #results.items > 0, root_view, x, y, results.items
end, {
  ['context-menu:show'] = function(root_view, x, y, items)
    root_view.context_menu:show(x, y, items)
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

command.add(function(root_view)
  local item = root_view.active_view:is(ContextMenu) and root_view.active_view:get_item_selected()
  return item, root_view.context_menu, item
end, {
  ['context-menu:submit'] = function(context_menu, item)
    if item.command then
      context_menu:on_selected(item)
      context_menu:hide()
    end
  end
})

