local command = require "core.command"
local config = require "core.config"

command.add(nil, {
  ["draw-whitespace:toggle"]  = function()
    config.draw_whitespace = not config.draw_whitespace
  end,

  ["draw-whitespace:disable"] = function()
    config.draw_whitespace = false
  end,

  ["draw-whitespace:enable"]  = function()
    config.draw_whitespace = true
  end,
})
