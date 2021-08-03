local core = require "core"
local command = require "core.command"


command.add(nil, {
  ["context-menu:show"] = function()
    core.context_menu:show(core.active_view.position.x, core.active_view.position.y)
  end
})
