local core = require "core"
local style = require "core.style"
local DocView = require "core.docview"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local Node = require "core.node"


local t = {
  ["root:close"] = function(node)
    node:close_active_view(node.root_view.root_node)
  end,

  ["root:close-or-quit"] = function(node)
    if node and (not node:is_empty() or not node.is_primary_node) then
      node:close_active_view(node.root_view.root_node)
    else
      core.quit()
    end
  end,

  ["root:close-all"] = function(node)
    core.confirm_close_docs(core.docs, node.root_view.close_all_docviews, node.root_view)
  end,

  ["root:close-all-others"] = function(node)
    local active_doc, docs = node.root_view.active_view and node.root_view.active_view.doc, {}
    for i, v in ipairs(core.docs) do if v ~= active_doc then table.insert(docs, v) end end
    core.confirm_close_docs(docs, node.root_view.close_all_docviews, node.root_view, true)
  end,

  ["root:move-tab-left"] = function(node)
    local idx = node:get_view_idx(node.root_view.active_view)
    if idx > 1 then
      table.remove(node.views, idx)
      table.insert(node.views, idx - 1, node.root_view.active_view)
    end
  end,

  ["root:move-tab-right"] = function(node)
    local idx = node:get_view_idx(node.root_view.active_view)
    if idx < #node.views then
      table.remove(node.views, idx)
      table.insert(node.views, idx + 1, node.root_view.active_view)
    end
  end,

  ["root:shrink"] = function(node)
    local parent = node:get_parent_node(node.root_view.root_node)
    local n = (parent.a == node) and -0.1 or 0.1
    parent.divider = common.clamp(parent.divider + n, 0.1, 0.9)
  end,

  ["root:grow"] = function(node)
    local parent = node:get_parent_node(node.root_view.root_node)
    local n = (parent.a == node) and 0.1 or -0.1
    parent.divider = common.clamp(parent.divider + n, 0.1, 0.9)
  end
}


for i = 1, 9 do
  t["root:switch-to-tab-" .. i] = function(node)
    local view = node.views[i]
    if view then
      node:set_active_view(view)
    end
  end
end


for _, dir in ipairs { "left", "right", "up", "down" } do
  t["root:split-" .. dir] = function(node)
    local av = node.active_view
    node:split(dir)
    if av:is(DocView) then
      node.root_view:open_doc(av.doc)
    end
  end

  t["root:switch-to-" .. dir] = function(node)
    local x, y
    if dir == "left" or dir == "right" then
      y = node.position.y + node.size.y / 2
      x = node.position.x + (dir == "left" and -1 or node.size.x + style.divider_size)
    else
      x = node.position.x + node.size.x / 2
      y = node.position.y + (dir == "up"   and -1 or node.size.y + style.divider_size)
    end
    local node = node.root_view.root_node:get_child_overlapping_point(x, y)
    local sx, sy = node:get_locked_size()
    if not sx and not sy then
      node.root_view:set_active_view(node.active_view)
    end
  end
end

command.add(function(root_view)
  local node = root_view:get_active_node()
  local sx, sy = node:get_locked_size()
  return not sx and not sy, node
end, t)

command.add(function(root_view, options) 
  return options.delta, root_view, options.delta
end, {
  ["root:scroll"] = function(root_view, delta)
    local view = root_view.overlapping_view or root_view.active_view
    if view and view.scrollable then
      view.scroll.to.y = view.scroll.to.y + delta * -config.mouse_wheel_scroll
      return true
    end
    return false
  end,
  ["root:horizontal-scroll"] = function(root_view, delta)
    local view = root_view.overlapping_view or root_view.active_view
    if view and view.scrollable then
      view.scroll.to.x = view.scroll.to.x + delta * -config.mouse_wheel_scroll
      return true
    end
    return false
  end
})

command.add(function(root_view, options)
  local node = options.node
  if not Node:is_extended_by(node) then node = nil end
  -- No node was specified, use the active one
  node = node or root_view:get_active_node()
  if not node then return false end
  return true, node
end,
  {
    ["root:switch-to-previous-tab"] = function(node)
      local idx = node:get_view_idx(node.active_view)
      idx = idx - 1
      if idx < 1 then idx = #node.views end
      node:set_active_view(node.views[idx])
    end,

    ["root:switch-to-next-tab"] = function(node)
      local idx = node:get_view_idx(node.active_view)
      idx = idx + 1
      if idx > #node.views then idx = 1 end
      node:set_active_view(node.views[idx])
    end,

    ["root:scroll-tabs-backward"] = function(node)
      node:scroll_tabs(1)
    end,

    ["root:scroll-tabs-forward"] = function(node)
      node:scroll_tabs(2)
    end
  }
)

command.add(function(root_view)
    local node = root_view.root_node:get_child_overlapping_point(root_view.mouse.x, root_view.mouse.y)
    if not node then return false end
    return (node.hovered_tab or node.hovered_scroll_button > 0), root_view
  end,
  {
    ["root:switch-to-hovered-previous-tab"] = function(root_view)
      root_view:perform("root:switch-to-previous-tab")
    end,

    ["root:switch-to-hovered-next-tab"] = function(root_view)
      root_view:perform("root:switch-to-next-tab")
    end,

    ["root:scroll-hovered-tabs-backward"] = function(root_view)
      root_view:perform("root:scroll-tabs-backward")
    end,

    ["root:scroll-hovered-tabs-forward"] = function(root_view)
      root_view:perform("root:scroll-tabs-forward")
    end
  }
)

-- double clicking the tab bar, or on the emptyview should open a new doc
command.add(function(root_view, options)
  local x, y = options.x, options.y
  local node = x and y and root_view.root_node:get_child_overlapping_point(x, y)
  return node and node:is_in_tab_area(x, y), root_view
end, {
  ["tabbar:new-doc"] = function(root_view)
    root_view:perform("core:new-doc", root_view)
  end
})
command.add("core.emptyview", {
  ["emptyview:new-doc"] = function(empty_view)
    empty_view:perform("core:new-doc")
  end
})
