local core = require "core"
local command = require "core.command"
local common = require "core.common"
local style = require "core.style"
local StatusView = require "core.statusview"

local function status_view_item_names()
  local items = core.status_view:get_items_list()
  local names = {}
  for _, item in ipairs(items) do
    table.insert(names, item.name)
  end
  return names
end

local function status_view_items_data(names)
  local data = {}
  for _, name in ipairs(names) do
    local item = core.status_view:get_item(name)
    table.insert(data, {
      text = command.prettify_name(item.name),
      info = item.alignment == StatusView.Item.LEFT and "Left" or "Right",
      name = item.name
    })
  end
  return data
end

local function status_view_get_items(text)
  local names = status_view_item_names()
  local results = common.fuzzy_match(names, text)
  results = status_view_items_data(results)
  return results
end

command.add(nil, {
  ["status-bar:toggle"] = function()
    core.status_view:toggle()
  end,
  ["status-bar:show"] = function()
    core.status_view:show()
  end,
  ["status-bar:hide"] = function()
    core.status_view:hide()
  end,
  ["status-bar:disable-messages"] = function()
    core.status_view:display_messages(false)
  end,
  ["status-bar:enable-messages"] = function()
    core.status_view:display_messages(true)
  end,
  ["status-bar:hide-item"] = function()
    core.command_view:enter("Status bar item to hide", {
      submit = function(text, item)
        core.status_view:hide_items(item.name)
      end,
      suggest = status_view_get_items
    })
  end,
  ["status-bar:show-item"] = function()
    core.command_view:enter("Status bar item to show", {
      submit = function(text, item)
        core.status_view:show_items(item.name)
      end,
      suggest = status_view_get_items
    })
  end,
  ["status-bar:reset-items"] = function()
    core.status_view:show_items()
  end,
})
