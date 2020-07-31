local core = require "core"
local keymap = require "core.keymap"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local View = require "core.view"


local function new_node() {
  return { input = "" }
}

local nodes = {
  new_node()
}

local ReplView = View:extend()

function ReplView:new()
  ReplView.super.new(self)
  self.scrollable = true
  self.brightness = 0
  -- self:begin_search(text, fn)
end

local function begin_repl()
  local rv = ReplView()
  core.root_view:get_active_node():add_view(rv)
end

command.add(nil, {
  ["repl:open"] = function()
    begin_repl()
  end
})

