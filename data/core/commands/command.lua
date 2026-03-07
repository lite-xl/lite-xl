local core = require "core"
local command = require "core.command"

command.add("core.commandview", {
  ["command:submit"] = function(cv)
    cv:submit()
  end,

  ["command:complete"] = function(cv)
    cv:complete()
  end,

  ["command:escape"] = function(cv)
    cv:exit()
  end,

  ["command:select-previous"] = function(cv)
    cv:move_suggestion_idx(1)
  end,

  ["command:select-next"] = function(cv)
    cv:move_suggestion_idx(-1)
  end,
})
