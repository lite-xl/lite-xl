local core = require "core"
local command = require "core.command"

command.add("core.logview", {
  ["log:expand-item"] = function()
    if core.active_view.hovered_item then
      core.active_view:expand_item(core.active_view.hovered_item)
    end
  end,
  ["log:copy-entry"] = function()
    if core.active_view.hovered_item then
      system.set_clipboard(core.get_log(core.active_view.hovered_item))
    end
  end
})

command.add(nil, {
  ["log:open-as-doc"] = function()
    local doc = core.open_doc("logs.txt")
    core.root_view:open_doc(doc)
    doc:insert(1, 1, core.get_log())
  end,
  ["log:copy-to-clipboard"] = function()
    system.set_clipboard(core.get_log())
  end
})
