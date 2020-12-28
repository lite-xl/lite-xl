local core = require "core"
local command = require "core.command"

command.add(nil, {
  ["files:create-directory"] = function()
    core.command_view:enter("New directory name", function(text)
      local success, err = system.mkdir(text)
      if not success then
        core.error("cannot create directory %q: %s", text, err)
      end
    end)
  end,
})
