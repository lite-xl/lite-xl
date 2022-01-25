-- Based on gruvbox color theme:
-- https://github.com/morhetz/gruvbox

local style = require "core.style"
local common = require "core.common"

style.background = { common.color "#fbf1c7" }
style.background2 = { common.color "#f2e5bc" }
style.background3 = { common.color "#eddbb2" }
style.text = { common.color "#928374" }
style.caret = { common.color "#282828" }
style.accent = { common.color "#3c3836" }
style.dim = { common.color "#928374" }
style.divider = { common.color "#bdae93" }
style.selection = { common.color "#ebdbb2" }
style.line_number = { common.color "#928374" }
style.line_number2 = { common.color "#3c3836" }
style.line_highlight = { common.color "#f2e5bc" }
style.scrollbar = { common.color "#928374" }
style.scrollbar2 = { common.color "#504945" }

style.syntax["normal"] = { common.color "#3c3836" }
style.syntax["symbol"] = { common.color "#3c3836" }
style.syntax["comment"] = { common.color "#928374" }
style.syntax["keyword"] = { common.color "#cc241d" }
style.syntax["keyword2"] = { common.color "#458588" }
style.syntax["number"] = { common.color "#b16286" }
style.syntax["literal"] = { common.color "#b16286" }
style.syntax["string"] = { common.color "#98971a" }
style.syntax["operator"] = { common.color "#3c3836" }
style.syntax["function"] = { common.color "#689d6a" }
