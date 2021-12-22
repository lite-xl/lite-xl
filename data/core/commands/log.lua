local core = require "core"
local command = require "core.command"


command.add(nil, {
  ["log:open-as-doc"] = function()
    local doc = core.open_doc("logs.txt")
    core.root_view:open_doc(doc)
    doc:insert(1, 1, core.get_log())
    doc.new_file = false
    doc:clean()
  end,
  ["log:copy-to-clipboard"] = function()
    system.set_clipboard(core.get_log())
  end
})
