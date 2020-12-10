-- put user settings here
-- this module will be loaded after everything else when the application starts
-- it will be automatically reloaded when use save it

local keymap = require "core.keymap"
local config = require "core.config"
local style = require "core.style"

-- light theme:
-- style.load("colors.summer")

-- key binding:
-- keymap.add { ["ctrl+escape"] = "core:quit" }

-- customize fonts:
-- style.font = renderer.font.load(DATADIR .. "/fonts/font.ttf", 14 * SCALE)
-- style.code_font = renderer.font.load(DATADIR .. "/fonts/monospace.ttf", 13.5 * SCALE)
--
-- fonts used by the editor:
-- style.font      : user interface
-- style.big_font  : big text in welcome screen
-- style.icon_font : icons
-- style.code_font : code

