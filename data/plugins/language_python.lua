-- mod-version:3
local syntax = require "core.syntax"

local function table_merge(a, b)
    local t = {}
    for _, v in pairs(a) do table.insert(t, v) end
    for _, v in pairs(b) do table.insert(t, v) end

    return t
end


local python_symbols = {

  ["class"]    = "keyword",
  ["finally"]  = "keyword",
  ["is"]       = "keyword",
  ["return"]   = "keyword",
  ["continue"] = "keyword",
  ["for"]      = "keyword",
  ["lambda"]   = "keyword",
  ["try"]      = "keyword",
  ["except"]   = "keyword",
  ["def"]      = "keyword",
  ["async"]    = "keyword",
  ["await"]    = "keyword",
  ["from"]     = "keyword",
  ["nonlocal"] = "keyword",
  ["while"]    = "keyword",
  ["and"]      = "keyword",
  ["global"]   = "keyword",
  ["not"]      = "keyword",
  ["with"]     = "keyword",
  ["as"]       = "keyword",
  ["elif"]     = "keyword",
  ["if"]       = "keyword",
  ["or"]       = "keyword",
  ["else"]     = "keyword",
  ["match"]    = "keyword",
  ["case"]     = "keyword",
  ["import"]   = "keyword",
  ["pass"]     = "keyword",
  ["break"]    = "keyword",
  ["in"]       = "keyword",
  ["del"]      = "keyword",
  ["raise"]    = "keyword",
  ["yield"]    = "keyword",
  ["assert"]   = "keyword",

  ["self"]     = "keyword2",

  ["None"]     = "literal",
  ["True"]     = "literal",
  ["False"]    = "literal",

}



local python_fstring = {

  patterns = {
    { pattern = "\\.",         type = "string" },
    { pattern = '[^"\\{}\']+', type = "string" }

  },

  symbols = {}
}



local python_patterns = {

  { pattern = '[uUrR]%f["]',                 type = "keyword"                         },

  { pattern = { '[ruU]?"""', '"""', '\\' },  type = "string"                          },
  { pattern = { "[ruU]?'''", "'''", '\\' },  type = "string"                          },
  { pattern = { '[ruU]?"',   '"',   '\\' },  type = "string"                          },
  { pattern = { "[ruU]?'",   "'",   '\\' },  type = "string"                          },
  { pattern = { 'f"',        '"',   "\\" },  type = "string", syntax = python_fstring },
  { pattern = { "f'",        "'",   "\\" },  type = "string", syntax = python_fstring },

  { pattern = "%d+[%d%.eE_]*",               type = "number"                          },
  { pattern = "0[xboXBO][%da-fA-F_]+",       type = "number"                          },
  { pattern = "%.?%d+",                      type = "number"                          },
  { pattern = "%f[-%w_]-%f[%d%.]",           type = "number"                          },

  { pattern = "[%+%-=/%*%^%%<>!~|&]",        type = "operator"                        },
  { pattern = "[%a_][%w_]*%f[(]",            type = "function"                        },

  { pattern = "[%a_][%w_]+",                 type = "symbol"                          },

}



local python_type = {

  patterns = {
    { pattern = "|",            type = "operator"  },
    { pattern = "[%w_]+",       type = "keyword2"  },
    { pattern = "[%a_][%w_]+",  type = "symbol"    },
  },

  symbols = {
    ["None"] = "literal"
  }
}
-- Add this line after in order for the recursion to work.
-- Makes sure that the square brackets are well balanced when capturing the syntax
-- (in order to make something like this work: Tuple[Tuple[int, str], float])
table.insert(python_type.patterns, 1, { pattern = { "%[", "%]" }, syntax = python_type })



-- For things like this_list = other_list[a:b:c]
local not_python_type = {

  patterns = python_patterns,

  symbols = python_symbols

}

table.insert(not_python_type.patterns, 1, { pattern = { "%[", "%]" }, syntax = not_python_type })
table.insert(not_python_type.patterns, 1, { pattern = { "{",  "}"  }, syntax = not_python_type })

table.insert(python_fstring.patterns,  1, { pattern = { "{",  "}"  }, syntax = not_python_type })



local python_func = {

  patterns = table_merge({

    { pattern = { "->",   "%f[:]"        }, type = "operator", syntax = python_type  },
    { pattern = { ":%s*", "%f[^%[%]%w_]" },                    syntax = python_type  },

  }, python_patterns),

  symbols = python_symbols
}

table.insert(python_func.patterns, 1, { pattern = { "%(", "%)" }, syntax = python_func })



syntax.add {
  name = "Python",
  files = { "%.py$", "%.pyw$", "%.rpy$", "%.pyi$" },
  headers = "^#!.*[ /]python",
  comment = "#",
  block_comment = { '"""', '"""' },

  patterns = table_merge({

    { pattern = "#.*",                         type = "comment"                                         },
    { pattern = { '^%s*"""', '"""' },          type = "comment"                                         },

    { pattern = { "%[", "%]" },                                                syntax = not_python_type },
    { pattern = { "{",  "}"  },                                                syntax = not_python_type },

    { pattern = { "^%s*()def%f[%s]",    ":" }, type = { "normal", "keyword" }, syntax = python_func     }, -- this and the following prevent one-liner highlight bugs

    { pattern = { "^%s*()for%f[%s]",    ":" }, type = { "normal", "keyword" }, syntax = not_python_type },
    { pattern = { "^%s*()if%f[%s]",     ":" }, type = { "normal", "keyword" }, syntax = not_python_type },
    { pattern = { "^%s*()elif%f[%s]",   ":" }, type = { "normal", "keyword" }, syntax = not_python_type },
    { pattern = { "^%s*()while%f[%s]",  ":" }, type = { "normal", "keyword" }, syntax = not_python_type },
    { pattern = { "^%s*()match%f[%s]",  ":" }, type = { "normal", "keyword" }, syntax = not_python_type },
    { pattern = { "^%s*()case%f[%s]",   ":" }, type = { "normal", "keyword" }, syntax = not_python_type },
    { pattern = { "^%s*()except%f[%s]", ":" }, type = { "normal", "keyword" }, syntax = not_python_type },

    { pattern =  "else():",                    type = { "keyword", "normal" }                           },
    { pattern =  "try():",                     type = { "keyword", "normal" }                           },

    { pattern = "lambda()%s.+:",               type = { "keyword", "normal" }                           },
    { pattern = "class%s+()[%a_][%w_]+().*:",  type = { "keyword", "keyword2", "normal" }               },


    { pattern = { ":%s*", "%f[^%[%]%w_]"},                                     syntax = python_type     },

  }, python_patterns),

  symbols = python_symbols

}

