local core = require "core"
local command = require "core.command"

command.add("core.commandview", {
  ["command:submit"] = function()
    core.active_view:submit()
  end,

  ["command:complete"] = function()
    core.active_view:complete()
  end,

  ["command:escape"] = function()
    core.active_view:exit()
  end,

  ["command:select-previous"] = function()
    core.active_view:move_suggestion_idx(1)
  end,

  ["command:select-next"] = function()
    core.active_view:move_suggestion_idx(-1)
  end,
})
