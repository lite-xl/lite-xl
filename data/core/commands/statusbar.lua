local core = require "core"
local command = require "core.command"
local common = require "core.common"
local style = require "core.style"
local StatusView = require "core.statusview"

local function status_view_item_names(status_view)
  local items = status_view:get_items_list()
  local names = {}
  for _, item in ipairs(items) do
    table.insert(names, item.name)
  end
  return names
end

local function status_view_items_data(status_view, names)
  local data = {}
  for _, name in ipairs(names) do
    local item = status_view:get_item(name)
    table.insert(data, {
      text = command.prettify_name(item.name),
      info = item.alignment == StatusView.Item.LEFT and "Left" or "Right",
      name = item.name
    })
  end
  return data
end

local function status_view_get_items(status_view, text)
  local names = status_view_item_names(status_view)
  local results = common.fuzzy_match(names, text)
  results = status_view_items_data(status_view, results)
  return results
end

command.add(nil, {
  ["status-bar:toggle"] = function(root_view)
    root_view.status_view:toggle()
  end,
  ["status-bar:show"] = function(root_view)
    root_view.status_view:show()
  end,
  ["status-bar:hide"] = function(root_view)
    root_view.status_view:hide()
  end,
  ["status-bar:disable-messages"] = function(root_view)
    root_view.status_view:display_messages(false)
  end,
  ["status-bar:enable-messages"] = function(root_view)
    root_view.status_view:display_messages(true)
  end,
  ["status-bar:hide-item"] = function(root_view)
    root_view.command_view:enter("Status bar item to hide", {
      submit = function(text, item)
        root_view.status_view:hide_items(item.name)
      end,
      suggest = function(...) return status_view_get_items(root_view.status_view, ...) end
    })
  end,
  ["status-bar:show-item"] = function(root_view)
    root_view.command_view:enter("Status bar item to show", {
      submit = function(text, item)
        root_view.status_view:show_items(item.name)
      end,
      suggest = function(...) return status_view_get_items(root_view.status_view, ...) end
    })
  end,
  ["status-bar:reset-items"] = function(root_view)
    root_view.status_view:show_items()
  end,
})
