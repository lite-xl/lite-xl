-- mod-version:3
local syntax = require "core.syntax"


local python_fstring = {

    patterns = {
      { pattern = {"{", "}"}, type = "normal", syntax = ".py" },
      { pattern = ".",        type = "string"                 }
    },

    symbols = {}
}

local python_type = {

    patterns = {
      { pattern = "[%[%],%s]", type = "normal"     },
      { pattern = "|",          type = "operator"   },
      { pattern = ".",          type = "keyword2"   }
    },

    symbols = {}
}

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
    { pattern = "class%s+()[%a_][%w_]*",         type = {"keyword", "keyword2"}           },
    { pattern = "%f[^:]%s*[%a_][%w_]*%s*%b[]",   type = "keyword2",                       },
    { pattern = "%f[^:]%s*[%a_][%w_]*[:%]]",     type = "normal"                          },
    { pattern = "lambda().*:[%s%a_]",            type = {"keyword, normal"}               },
    { pattern = "%f[^:]%s*[%a_][%w_]*",          type = "keyword2"                        },
    { pattern = {"->()", ":"},                   type = {"operator", "normal"},           syntax = python_type },
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
    { pattern = "[%a_][%w_]*",                   type = "symbol"                          },

  },
  symbols = {
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
}
