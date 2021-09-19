local core = require "core"
local keymap = require "core.keymap"
local command = require "core.command"
local common = require "core.common"
local console = require "plugins.console"

local last_build = ""

-- Used to inject into the command anything needed to execute
-- into the appropriate environment.
-- Below is for lhelper but other settings may be used.
-- If not needed just return the command itself without modifications.
local function bake_command(cmd)
  return "source $(lhelper env-source lite-xl); " .. cmd
end

command.add(nil, {
  ["lite-xl:run"] = function()
    core.command_view:set_text(last_build, true)
    core.command_view:enter("Run Lite XL build", function(build)
      console.run {
        command = bake_command("scripts/run-local " .. build),
        file_pattern = "([^?:%s]+%.[^?:%s]+):([1-9]%d*):([1-9]%d*):",
        file_prefix = build,
      }
      last_build = build
    end)
  end,

  ["lite-xl:build"] = function()
    core.command_view:set_text(last_build, true)
    core.command_view:enter("Run Lite XL build", function(build)
      console.run {
        command = bake_command("ninja -C " .. build),
        file_pattern = "([^?:%s]+%.[^?:%s]+):([1-9]%d*):([1-9]%d*):",
        file_prefix = build,
      }
      last_build = build
    end)
  end,

  ["lite-xl:meson-setup"] = function()
    core.command_view:set_text(last_build, true)
    core.command_view:enter("Meson setup", function(build)
      console.run {
        command = bake_command("rm -fr " .. build .. " && meson setup " .. build),
        file_pattern = "([^?:%s]+%.[^?:%s]+):([1-9]%d*):([1-9]%d*):",
      }
      last_build = build
    end)
  end,
})

keymap.add {
  ["ctrl+b"] = "lite-xl:build",
  ["alt+!"]  = "lite-xl:run",
}

