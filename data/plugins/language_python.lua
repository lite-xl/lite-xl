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
    ["except"]   = "keyword",
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
      { pattern = {"{", "}"},  type = "normal", syntax = ".py" },
      { pattern = "\\.",       type = "string"                 },
      { pattern = '[^"\\{}]+', type = "string"                 }

    },

    symbols = {}
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
    { pattern = { 'f"', '"', "\\"},              type = "string", syntax = python_fstring },
    { pattern = { "f'", "'", "\\"},              type = "string", syntax = python_fstring },
    { pattern = "-?0[xboXBO][%da-fA-F_]+",       type = "number"                          },
    { pattern = "-?%d+[%d%.eE_]*",               type = "number"                          },
    { pattern = "-?%.?%d+",                      type = "number"                          },
    { pattern = "[%+%-=/%*%^%%<>!~|&]",          type = "operator"                        },
    { pattern = "[%a_][%w_]*%f[(]",              type = "function"                        },

    { pattern = "%a%a+",                         type = "symbol"                          },
  },

  symbols = python_symbols
}

table.insert(not_python_type.patterns, 1, { pattern = { "%[", "%]" }, syntax = not_python_type })
table.insert(not_python_type.patterns, 1, { pattern = { "{", "}" },   syntax = not_python_type })


syntax.add {
  name = "Python",
  files = { "%.py$", "%.pyw$", "%.rpy$", "%.pyi$" },
  headers = "^#!.*[ /]python",
  comment = "#",
  block_comment = { '"""', '"""' },
  patterns = {
    { pattern = "#.*",                           type = "comment"                         },
    { pattern = { '^%s*"""', '"""' },            type = "comment"                         },
    { pattern = '[uUrR]%f["]',                   type = "keyword"                         },
    { pattern = "class%s+()[%a_][%w_]*",         type = { "keyword", "keyword2"}          },
    { pattern = { "%[", "%]" },                                  syntax = not_python_type },
    { pattern = { "{", "}" },                                    syntax = not_python_type },
    { pattern = "lambda().-:",                   type = { "keyword, normal"}              },
    { pattern = ":%s*\n",                        type = "normal"                          },
    { pattern = { ":%s*", "%f[=,%)%s]"},                           syntax = python_type     },
    { pattern = { "->()", ":" },                 type = { "operator", "normal" }, syntax = python_type },
    { pattern = { '[ruU]?"""', '"""'; '\\' },    type = "string"                          },
    { pattern = { "[ruU]?'''", "'''", '\\' },    type = "string"                          },
    { pattern = { '[ruU]?"', '"', '\\' },        type = "string"                          },
    { pattern = { "[ruU]?'", "'", '\\' },        type = "string"                          },
    { pattern = { 'f"', '"', "\\"},              type = "string", syntax = python_fstring },
    { pattern = { "f'", "'", "\\"},              type = "string", syntax = python_fstring },
    { pattern = "-?0[xboXBO][%da-fA-F_]+",       type = "number"                          },
    { pattern = "-?%d+[%d%.eE_]*",               type = "number"                          },
    { pattern = "-?%.?%d+",                      type = "number"                          },
    { pattern = "[%+%-=/%*%^%%<>!~|&]",          type = "operator"                        },
    { pattern = "[%a_][%w_]*%f[(]",              type = "function"                        },

    { pattern = "%a%a+",                         type = "symbol"                          },


  },
  symbols = python_symbols
}
