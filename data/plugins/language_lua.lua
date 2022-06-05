-- mod-version:3
local syntax = require "core.syntax"

syntax.add {
  name = "Lua",
  files = "%.lua$",
  headers = "^#!.*[ /]lua",
  comment = "--",
  block_comment = { "--[[", "]]" },
  patterns = {
    { pattern = { '"', '"', '\\' },          type = "string" },
    { pattern = { "'", "'", '\\' },          type = "string" },
    { pattern = { "%[%[", "%]%]" },          type = "string" },
    { pattern = { "%-%-%[%[", "%]%]"},       type = "comment" },
    { pattern = "%-%-.*",                    type = "comment" },
    { pattern = "0x%x+%.%x*[pP][-+]?%d+",    type = "number" },
    { pattern = "0x%x+%.%x*",                type = "number" },
    { pattern = "0x%.%x+[pP][-+]?%d+",       type = "number" },
    { pattern = "0x%.%x+",                   type = "number" },
    { pattern = "0x%x+[pP][-+]?%d+",         type = "number" },
    { pattern = "0x%x+",                     type = "number" },
    { pattern = "%d%.%d*[eE][-+]?%d+",       type = "number" },
    { pattern = "%d%.%d*",                   type = "number" },
    { pattern = "%.?%d*[eE][-+]?%d+",        type = "number" },
    { pattern = "%.?%d+",                    type = "number" },
    { pattern = "<%a+>",                     type = "keyword2" },
    { pattern = "%.%.%.?",                   type = "operator" },
    { pattern = "[<>~=]=",                   type = "operator" },
    { pattern = "[%+%-=/%*%^%%#<>]",         type = "operator" },
    -- Metamethods
    { pattern = "__[%a][%w_]*",              type = "function" },
    { pattern = "%.()__[%a][%w_]*",
      type = { "normal", "function" }
    },
    -- function declarations to prevent matching as variables
    { pattern = "local()%s+()function()%s+()[%a_][%w_]*",
      type = { "keyword", "normal", "keyword", "normal", "function" }
    },
    { pattern = "local()%s+()function",
      type = { "keyword", "normal", "keyword" }
    },
    -- Placeholder
    { pattern = "_(),",
      type = { "operator", "normal" }
    },
    -- Variable declarations
    { pattern = {"local", "[=\n]"},
      syntax = {
        patterns = {
          {
            pattern = "[%a_][%w_]*()%s*,?%s*",
            type = {"keyword2", "normal"}
          }
        },
        symbols = {}
      },
      type = "normal"
    },
    -- Function calls
    { pattern = "[%a_][%w_]+()%s*%f[(\"'{]", type = {"function", "normal"} },
    { pattern = "[%a_][%w_%.]+()%.()[%a_][%w_]+()%s*%f[(\"'{]",
      type = { "normal", "normal", "function", "normal"} },
    -- Sub fields
    { pattern = "%.()[%a_][%w_]*",
      type = { "normal", "literal" }
    },
    -- Uppercase constants of at least 2 chars in len
    {
        pattern = "%u[%u_][%u%d_]*%f[%s%+%*%-%.%(%)%?%^%%=/<>~|&:,~]",
        type = "number"
    },
    -- Variable assignments
    { pattern = "%a[%w_]*() *= *%f[^=]",
      type = { "keyword2", "operator" }
    },
    -- Labels
    { pattern = "::[%a_][%w_]*::",           type = "function" },
    -- Other text
    { pattern = "[%a_][%w_]*",               type = "normal" },
  },
  symbols = {
    ["if"]       = "keyword",
    ["then"]     = "keyword",
    ["else"]     = "keyword",
    ["elseif"]   = "keyword",
    ["end"]      = "keyword",
    ["do"]       = "keyword",
    ["function"] = "keyword",
    ["repeat"]   = "keyword",
    ["until"]    = "keyword",
    ["while"]    = "keyword",
    ["for"]      = "keyword",
    ["break"]    = "keyword",
    ["return"]   = "keyword",
    ["local"]    = "keyword",
    ["in"]       = "keyword",
    ["not"]      = "keyword",
    ["and"]      = "keyword",
    ["or"]       = "keyword",
    ["goto"]     = "keyword",
    ["self"]     = "keyword2",
    ["true"]     = "literal",
    ["false"]    = "literal",
    ["nil"]      = "literal",
  },
}

