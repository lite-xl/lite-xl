local b05 = 'rgba(0,0,0,0.5)'   local red = '#994D4D'
local b80 = '#333333'       local orange  = '#B3661A'
local b60 = '#808080'       local green   = '#52994D'
local b40 = '#ADADAD'       local teal    = '#4D9999'
local b20 = '#CECECE'       local blue    = '#1A66B3'
local b00 = '#E6E6E6'       local magenta = '#994D99'
--------------------------=--------------------------
local style               =     require  'core.style'
local common              =     require 'core.common'
--------------------------=--------------------------
style.line_highlight      =     { common.color(b20) }
style.background          =     { common.color(b00) }
style.background2         =     { common.color(b20) }
style.background3         =     { common.color(b20) }
style.text                =     { common.color(b60) }
style.caret               =     { common.color(b80) }
style.accent              =     { common.color(b80) }
style.dim                 =     { common.color(b60) }
style.divider             =     { common.color(b40) }
style.selection           =     { common.color(b40) }
style.line_number         =     { common.color(b60) }
style.line_number2        =     { common.color(b80) }
style.scrollbar           =     { common.color(b40) }
style.scrollbar2          =     { common.color(b60) }
style.nagbar              =     { common.color(red) }
style.nagbar_text         =     { common.color(b00) }
style.nagbar_dim          =     { common.color(b05) }
--------------------------=--------------------------
style.syntax              =                        {}
style.syntax['normal']    =     { common.color(b80) }
style.syntax['symbol']    =     { common.color(b80) }
style.syntax['comment']   =     { common.color(b60) }
style.syntax['keyword']   =    { common.color(blue) }
style.syntax['keyword2']  =     { common.color(red) }
style.syntax['number']    =    { common.color(teal) }
style.syntax['literal']   =    { common.color(blue) }
style.syntax['string']    =   { common.color(green) }
style.syntax['operator']  = { common.color(magenta) }
style.syntax['function']  =    { common.color(blue) }
--------------------------=--------------------------
style.syntax.paren1       = { common.color(magenta) }
style.syntax.paren2       =  { common.color(orange) }
style.syntax.paren3       =    { common.color(teal) }
style.syntax.paren4       =    { common.color(blue) }
style.syntax.paren5       =     { common.color(red) }
--------------------------=--------------------------
style.lint                =                        {}
style.lint.info           =    { common.color(blue) }
style.lint.hint           =   { common.color(green) }
style.lint.warning        =     { common.color(red) }
style.lint.error          =  { common.color(orange) }
