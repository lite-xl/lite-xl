local style = require "core.style"
local common = require "core.common"

style.background = { common.color "#2e2e32" }  -- Docview
style.background2 = { common.color "#252529" } -- Treeview
style.background3 = { common.color "#252529" } -- Command view
style.text = { common.color "#97979c" }
style.caret = { common.color "#93DDFA" }
style.accent = { common.color "#e1e1e6" }
-- style.dim - text color for nonactive tabs, tabs divider, prefix in log and
-- search result, hotkeys for context menu and command view
style.dim = { common.color "#525257" }
style.divider = { common.color "#202024" } -- Line between nodes
style.selection = { common.color "#48484f" }
style.line_number = { common.color "#525259" }
style.line_number2 = { common.color "#83838f" } -- With cursor
style.line_highlight = { common.color "#343438" }
style.scrollbar = { common.color "#414146" }
style.scrollbar2 = { common.color "#4b4b52" } -- Hovered
style.scrollbar_track = { common.color "#252529" }
style.nagbar = { common.color "#FF0000" }
style.nagbar_text = { common.color "#FFFFFF" }
style.nagbar_dim = { common.color "rgba(0, 0, 0, 0.45)" }
style.drag_overlay = { common.color "rgba(255,255,255,0.1)" }
style.drag_overlay_tab = { common.color "#93DDFA" }
style.good = { common.color "#72b886" }
style.warn = { common.color "#FFA94D" }
style.error = { common.color "#FF3333" }
style.modified = { common.color "#1c7c9c" }

style.syntax["normal"] = { common.color "#e1e1e6" }
style.syntax["symbol"] = { common.color "#e1e1e6" }
style.syntax["comment"] = { common.color "#676b6f" }
style.syntax["keyword"] = { common.color "#E58AC9" }  -- local function end if case
style.syntax["keyword2"] = { common.color "#F77483" } -- self int float
style.syntax["number"] = { common.color "#FFA94D" }
style.syntax["literal"] = { common.color "#FFA94D" }  -- true false nil
style.syntax["string"] = { common.color "#f7c95c" }
style.syntax["operator"] = { common.color "#93DDFA" } -- = + - / < >
style.syntax["function"] = { common.color "#93DDFA" }

style.log["INFO"]  = { icon = "i", color = style.text }
style.log["WARN"]  = { icon = "!", color = style.warn }
style.log["ERROR"] = { icon = "!", color = style.error }

return style
