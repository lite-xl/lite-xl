-- mod-version:4
local core = require "core"
local config = require "core.config"
local command = require "core.command"
local Doc = require "core.doc"
local common = require "core.common"

config.plugins.autorestart = common.merge({
  
}, config.plugins.autorestart)

local save = Doc.save
Doc.save = function(self, ...)
  local res = save(self, ...)
  if self.abs_filename == USERDIR .. PATHSEP .. "init.lua" or self.abs_filename == core.project().path .. PATHSEP .. ".lite_project" then
    command.perform("core:restart")
  end
  return res
end
