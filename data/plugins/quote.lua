-- mod-version:3
local core = require "core"
local command = require "core.command"
local keymap = require "core.keymap"


local escapes = {
  ["\\"] = "\\\\",
  ["\""] = "\\\"",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
  ["\b"] = "\\b",
}

local function replace(chr)
  return escapes[chr] or string.format("\\x%02x", chr:byte())
end


command.add("core.docview", {
  ["quote:quote"] = function(dv)
    dv.doc:replace(function(text)
      return '"' .. text:gsub("[\0-\31\\\"]", replace) .. '"'
    end)
  end,
})

keymap.add {
  ["ctrl+'"] = "quote:quote",
}
