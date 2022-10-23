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
    { pattern = "%-%-.-\n",                  type = "comment" },
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
    -- Function parameters
    {
      regex = {
        "(?="
          .. "(?:local)?\\s*"
          .. "(?:function\\s*)"
          .. "(?:[a-zA-Z_][a-zA-Z0-9_\\.\\:]*\\s*)?"
          .. "\\("
        .. ")",
        "\\)"
      },
      type = "normal",
      syntax = {
        patterns = {
          { pattern = "%.%.%.", type = "operator" },
          { pattern = "[%a_][%w_]*%s*(),%s*",
            type = { "operator", "normal" }
          },
          { pattern = "[%a_][%w_]*%s*%f[%s)]",
            type = "operator"
          },
          { pattern = "%.()[%a_][%w_]*()%s*%f[(]",
            type = { "normal", "function", "normal" }
          },
          { pattern = "[%a_][%w_]*()%s*%f[(]",
            type = { "function", "normal" }
          },
          { pattern = "%.()[%a_][%w_]*",
            type = { "normal", "symbol" }
          },
          { pattern = "[%a_][%w_]*",
            type = "symbol"
          },
        },
        symbols = {
          ["local"] = "keyword",
          ["function"] = "keyword",
          ["self"] = "keyword2"
        }
      }
    },
    -- require statements
    { pattern = "local()%s+()[%a_][%w_]*()%s*()=()%s*()require",
      type = { "keyword", "normal", "keyword2", "normal", "operator", "normal", "function" }
    },
    -- Placeholder
    { pattern = "_%s*(),",
      type = { "operator", "normal" }
    },
    -- Function calls
    { pattern = "[%a_][%w_]+()%s*%f[(\"'{]", type = { "function", "normal" } },
    { pattern = "[%a_][%w_%.]+()%.()[%a_][%w_]+()%s*%f[(\"'{]",
      type = { "normal", "normal", "function", "normal" }
    },
    -- Sub fields
    { pattern = "%.()[%a_][%w_]*",
      type = { "normal", "symbol" }
    },
    -- Uppercase constants of at least 2 chars in len
    {
        pattern = "%u[%u_][%u%d_]*%f[%s%+%*%-%.%(%)%?%^%%=/<>~|&:,~]",
        type = "number"
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

