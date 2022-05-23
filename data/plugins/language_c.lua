-- mod-version:3 -- lite-xl 2.1
local syntax = require "core.syntax"

syntax.add {
  name = "C",
  files = { "%.c$" },
  comment = "//",
  block_comment = { "/*", "*/" },
  patterns = {
    { pattern = "//.-\n",                type = "comment" },
    { pattern = { "/%*", "%*/" },        type = "comment" },
    { pattern = { '"', '"', '\\' },      type = "string"  },
    { pattern = { "'", "'", '\\' },      type = "string"  },
    { pattern = "0x%x+",                 type = "number"  },
    { pattern = "%d+[%d%.eE]*f?",        type = "number"  },
    { pattern = "%.?%d+f?",              type = "number"  },
    { pattern = "[%+%-=/%*%^%%<>!~|&]",  type = "operator" },
    { pattern = "##",                    type = "operator" },
    { pattern = "struct%s()[%a_][%w_]*", type = {"keyword", "keyword2"} },
    { pattern = "union%s()[%a_][%w_]*",  type = {"keyword", "keyword2"} },
    -- static declarations
    { pattern = "static()%s+()inline",
      type = { "keyword", "normal", "keyword" }
    },
    { pattern = "static()%s+()const",
      type = { "keyword", "normal", "keyword" }
    },
    { pattern = "static()%s+()[%a_][%w_]*",
      type = { "keyword", "normal", "literal" }
    },
    -- match function type declarations
    { pattern = "[%a_][%w_]*()%*+()%s+()[%a_][%w_]*%f[%(]",
      type = { "literal", "operator", "normal", "function" }
    },
    { pattern = "[%a_][%w_]*()%s+()%*+()[%a_][%w_]*%f[%(]",
      type = { "literal", "normal", "operator", "function" }
    },
    { pattern = "[%a_][%w_]*()%s+()[%a_][%w_]*%f[%(]",
      type = { "literal", "normal", "function" }
    },
    -- match variable type declarations
    { pattern = "[%a_][%w_]*()%*+()%s+()[%a_][%w_]*",
      type = { "literal", "operator", "normal", "normal" }
    },
    { pattern = "[%a_][%w_]*()%s+()%*+()[%a_][%w_]*",
      type = { "literal", "normal", "operator", "normal" }
    },
    { pattern = "[%a_][%w_]*()%s+()[%a_][%w_]*()%s*()[;,%[%)]",
      type = { "literal", "normal", "normal", "normal", "normal" }
    },
    { pattern = "[%a_][%w_]*()%s+()[%a_][%w_]*()%s*()=",
      type = { "literal", "normal", "normal", "normal", "operator" }
    },
    { pattern = "[%a_][%w_]*()&()%s+()[%a_][%w_]*",
      type = { "literal", "operator", "normal", "normal" }
    },
    { pattern = "[%a_][%w_]*()%s+()&()[%a_][%w_]*",
      type = { "literal", "normal", "operator", "normal" }
    },
    -- Uppercase constants of at least 2 chars in len
    { pattern = "_?%u[%u_][%u%d_]*%f[%s%+%*%-%.%)%]}%?%^%%=/<>~|&;:,!]",
      type = "number"
    },
     -- Magic constants
    { pattern = "__[%u%l]+__",           type = "number"   },
    -- all other functions
    { pattern = "[%a_][%w_]*%f[(]",      type = "function" },
     -- Macros
    { pattern = "^%s*#%s*define%s+()[%a_][%a%d_]*",
      type = { "keyword", "symbol" }
    },
    { pattern = "#%s*include%s()<.->",   type = {"keyword", "string"} },
    { pattern = "%f[#]#%s*[%a_][%w_]*",  type = "keyword"   },
    -- Everything else to make the tokenizer work properly
    { pattern = "[%a_][%w_]*",           type = "symbol" },
  },
  symbols = {
    ["if"]       = "keyword",
    ["then"]     = "keyword",
    ["else"]     = "keyword",
    ["elseif"]   = "keyword",
    ["do"]       = "keyword",
    ["while"]    = "keyword",
    ["for"]      = "keyword",
    ["break"]    = "keyword",
    ["continue"] = "keyword",
    ["return"]   = "keyword",
    ["goto"]     = "keyword",
    ["typedef"]  = "keyword",
    ["enum"]     = "keyword",
    ["extern"]   = "keyword",
    ["static"]   = "keyword",
    ["volatile"] = "keyword",
    ["const"]    = "keyword",
    ["inline"]   = "keyword",
    ["switch"]   = "keyword",
    ["case"]     = "keyword",
    ["default"]  = "keyword",
    ["auto"]     = "keyword",
    ["struct"]   = "keyword",
    ["union"]    = "keyword",
    ["void"]     = "keyword2",
    ["int"]      = "keyword2",
    ["short"]    = "keyword2",
    ["long"]     = "keyword2",
    ["float"]    = "keyword2",
    ["double"]   = "keyword2",
    ["char"]     = "keyword2",
    ["unsigned"] = "keyword2",
    ["bool"]     = "keyword2",
    ["true"]     = "literal",
    ["false"]    = "literal",
    ["NULL"]     = "literal",
    ["#include"] = "keyword",
    ["#if"] = "keyword",
    ["#ifdef"] = "keyword",
    ["#ifndef"] = "keyword",
    ["#elif"]    = "keyword",
    ["#else"] = "keyword",
    ["#elseif"] = "keyword",
    ["#endif"] = "keyword",
    ["#define"] = "keyword",
    ["#warning"] = "keyword",
    ["#error"] = "keyword",
    ["#pragma"] = "keyword",
  },
}

