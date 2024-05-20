-- mod-version:3
local syntax = require "core.syntax"


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


local python_type = {

  patterns = {
    { pattern = "|",          type = "operator"  },
    { pattern = "[%w_]+",     type = "keyword2"  },
    { pattern = "%a%a+",      type = "symbol"    },
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
  patterns = {
    { pattern = { '[ruU]?"""', '"""'; '\\' },    type = "string"                          },
    { pattern = { "[ruU]?'''", "'''", '\\' },    type = "string"                          },
    { pattern = { '[ruU]?"', '"', '\\' },        type = "string"                          },
    { pattern = { "[ruU]?'", "'", '\\' },        type = "string"                          },

    { pattern = "0[xboXBO][%da-fA-F_]+",         type = "number"                          },
    { pattern = "%d+[%d%.eE_]*",                 type = "number"                          },
    { pattern = "%.?%d+",                        type = "number"                          },
    { pattern = "%f[-%w]-%f[%d]",                type = "number"                          },

    { pattern = "[%+%-=/%*%^%%<>!~|&]",          type = "operator"                        },
    { pattern = "[%a_][%w_]*%f[(]",              type = "function"                        },

    { pattern = "%f[%a_]%a%a+%f[^%a_]",          type = "symbol"                          },
  },

  symbols = python_symbols
}

table.insert(not_python_type.patterns, 1, { pattern = { "%[", "%]" }, syntax = not_python_type })
table.insert(not_python_type.patterns, 1, { pattern = { "{",  "}"  }, syntax = not_python_type })



local python_fstring = {

    patterns = {
      { pattern = {"{", "}"},    type = "normal", syntax = not_python_type },
      { pattern = "\\.",         type = "string"                 },
      { pattern = '[^"\\{}\']+', type = "string"                 }

    },

    symbols = {}
}

table.insert(not_python_type.patterns, 3, { pattern = { 'f"', '"', "\\"}, type = "string", syntax = python_fstring })
table.insert(not_python_type.patterns, 3, { pattern = { "f'", "'", "\\"}, type = "string", syntax = python_fstring })



syntax.add {
  name = "Python",
  files = { "%.py$", "%.pyw$", "%.rpy$", "%.pyi$" },
  headers = "^#!.*[ /]python",
  comment = "#",
  block_comment = { '"""', '"""' },

  patterns = {

    { pattern = "#.*",                         type = "comment"                           },
    { pattern = { '^%s*"""', '"""' },          type = "comment"                           },
    { pattern = '[uUrR]%f["]',                 type = "keyword"                           },
    { pattern = "class%s+()[%a_][%w_]*():",    type = { "keyword", "keyword2", "normal" } },

    { pattern = { "%[", "%]" },                                  syntax = not_python_type },
    { pattern = { "{",  "}"  },                                  syntax = not_python_type },
    { pattern = { "%(", "%)" },                                  syntax = ".py"           },

    { pattern = "lambda().-:",                 type = { "keyword", "normal" }             },

    { pattern = { "def",     "[:\n]" },                          syntax = ".py"           }, -- this and the following prevent one-liner highlight bugs

    { pattern = { "for",     "[:\n]" },                          syntax = not_python_type },
    { pattern = { "if",      "[:\n]" },                          syntax = not_python_type },
    { pattern = { "elif",    "[:\n]" },                          syntax = not_python_type },
    { pattern = { "while",   "[:\n]" },                          syntax = not_python_type },
    { pattern = { "match",   "[:\n]" },                          syntax = not_python_type },
    { pattern = { "case",    "[:\n]" },                          syntax = not_python_type },
    { pattern = { "except",  "[:\n]" },                          syntax = not_python_type },

    { pattern =  "else():",                    type = { "keyword", "normal" }             },
    { pattern =  "try():",                     type = { "keyword", "normal" }             },

    { pattern = ":%s*\n",                      type = "normal"                            },

    { pattern = { ":%s*", "%f[^%[%]%w_]"},                        syntax = python_type    },
    { pattern = { "->()", "%f[:]" },           type = { "operator", "normal" }, syntax = python_type },

    { pattern = { '[ruU]?"""', '"""'; '\\' },  type = "string"                            },
    { pattern = { "[ruU]?'''", "'''", '\\' },  type = "string"                            },
    { pattern = { '[ruU]?"', '"', '\\' },      type = "string"                            },
    { pattern = { "[ruU]?'", "'", '\\' },      type = "string"                            },
    { pattern = { 'f"', '"', "\\"},            type = "string", syntax = python_fstring   },
    { pattern = { "f'", "'", "\\"},            type = "string", syntax = python_fstring   },

    { pattern = "%f[%w_]0[xboXBO][%da-fA-F_]+%f[^%w_]",         type = "number"           },
    { pattern = "%f[%w_]%d+[%d%.eE_]*%f[^%w_]",                 type = "number"           },
    { pattern = "%f[%w_]%.?%d+%f[^%w_]",                        type = "number"           },
    { pattern = "%f[-%w_]-%f[%d%.]",           type = "number"                            },

    { pattern = "[%+%-=/%*%^%%<>!~|&]",        type = "operator"                          },
    { pattern = "[%a_][%w_]*%f[(]",            type = "function"                          },

    { pattern = "%f[%w_]%a%a+%f[^%w_]",        type = "symbol"                            },

  },

  symbols = python_symbols
}
