local style = require "core.style"
local common = require "core.common"

style.background = { common.color "#f9fafa" } -- 249 250 250
style.background2 = { common.color "#ebedef" } -- 235 237 239
style.background3 = { common.color "#2c2a2b" } -- A FAIRE
style.text = { common.color "#404040" }-- A FAIRE
style.caret = { common.color "#fc1785" }-- A FAIRE
style.accent = { common.color "#fc1785" }-- A FAIRE
style.dim = { common.color "#b0b0b0" }-- A FAIRE
style.divider = { common.color "#e8e8e8" }-- A FAIRE
style.selection = { common.color "#b7dce8" }-- A FAIRE
style.line_number = { common.color "#d0d0d0" }-- A FAIRE
style.line_number2 = { common.color "#808080" }-- A FAIRE
style.line_highlight = { common.color "#e3e6e8" }-- 227 230 232 --"#c7cbd1" }
style.scrollbar = { common.color "#e0e0e0" }-- A FAIRE
style.scrollbar2 = { common.color "#c0c0c0" }-- A FAIRE


style.syntax["normal"] = { common.color "#323232" } -- 50 50 50
style.syntax["symbol"] = { common.color "#323232" } -- 50 50 50
style.syntax["comment"] = { common.color "#999999" } -- 153 153 153
style.syntax["keyword"] = { common.color "#c695c6" } -- 198 149 198
style.syntax["keyword2"] = { common.color "#ec6066" } -- 236 96 102 red-like
style.syntax["number"] = { common.color "#f9ae57" } -- 249 174 87
style.syntax["literal"] = { common.color "#60b4b4" } -- 96 180 180
style.syntax["string"] = { common.color "#99c794" } -- 153 199 148
style.syntax["operator"] = { common.color "#f97b57" } -- 249 123 87 red-like operator
style.syntax["function"] = { common.color "#6699cc" } -- 102 153 204 blue-like
