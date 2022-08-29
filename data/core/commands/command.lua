local core = require "core"
local command = require "core.command"

command.add("core.commandview", {
  ["command:submit"] = function(active_view)
    active_view:submit()
  end,

  ["command:complete"] = function(active_view)
    active_view:complete()
  end,

  ["command:escape"] = function(active_view)
    active_view:exit()
  end,

  ["command:select-previous"] = function(active_view)
    active_view:move_suggestion_idx(1)
  end,

  ["command:select-next"] = function(active_view)
    active_view:move_suggestion_idx(-1)
  end,
})
