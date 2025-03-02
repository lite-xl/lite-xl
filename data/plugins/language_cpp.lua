-- mod-version:3
local syntax = require "core.syntax"

-- integer suffix combinations as a regex
local isuf = [[(?:[lL][uU]|ll[uU]|LL[uU]|[uU][lL]\b|[uU]ll|[uU]LL|[uU]|[lL]\b|ll|LL)?]]
-- float suffix combinations as a Lua pattern / regex
local fsuf = "[fFlL]?"
-- number with digit separator as a regex non-capturing group
local digitsep = [[(?:\d[\d']*)]]

syntax.add {
  name = "C++",
  files = {
    "%.h$", "%.inl$", "%.cpp$", "%.cc$", "%.C$", "%.cxx$",
    "%.c++$", "%.hh$", "%.H$", "%.hxx$", "%.hpp$", "%.h++$",
    "%.ino$", "%.cu$", "%.cuh$"
  },
  comment = "//",
  block_comment = { "/*", "*/" },
  patterns = {
    { pattern = "//.*",                                                            type = "comment"  },
    { pattern = { "/%*", "%*/" },                                                  type = "comment"  },
    { pattern = { '"', '"', '\\' },                                                type = "string"   },
    { pattern = { "'", "'", '\\' },                                                type = "string"   },
    { regex   = "0x[0-9a-fA-F][0-9a-fA-F']*"..isuf,                                type = "number"   },
    { regex   = "0b[01][01']*"..isuf,                                              type = "number"   },
    { regex   = "0()[0-7][0-7']*"..isuf,                                           type = { "keyword", "number" } },
    { regex   = digitsep.."\\.?"..digitsep.."?(?:[Ee][-+]?"..digitsep..")?"..fsuf, type = "number" },
    { regex   = "\\."..digitsep.."(?:[Ee][-+]?"..digitsep..")?"..fsuf,             type = "number" },
    { pattern = "[%+%-=/%*%^%%<>!~|:&]",                                           type = "operator" },
    { pattern = "##",                                                              type = "operator" },
    { pattern = "struct%s()[%a_][%w_]*",                                           type = {"keyword", "keyword2"} },
    { pattern = "class%s()[%a_][%w_]*",                                            type = {"keyword", "keyword2"} },
    { pattern = "union%s()[%a_][%w_]*",                                            type = {"keyword", "keyword2"} },
    { pattern = "namespace%s()[%a_][%w_]*",                                        type = {"keyword", "keyword2"} },
    -- static declarations
    { pattern = "static()%s+()inline",
      type = { "keyword", "normal", "keyword" }
    },
    { pattern = "static()%s+()constexpr",
      type = { "keyword", "normal", "keyword" }
    },
    { pattern = "static()%s+()constinit",
      type = { "keyword", "normal", "keyword" }
    },
    { pattern = "static()%s+()consteval",
      type = { "keyword", "normal", "keyword" }
    },
    { pattern = "static()%s+()const",
      type = { "keyword", "normal", "keyword" }
    },
    { pattern = "static()%s+()[%a_][%w_]*",
      type = { "keyword", "normal", "literal" }
    },
    -- match method type declarations
    { pattern = "[%a_][%w_]*()%s*()%**()%s*()[%a_][%w_]*()%s*()::",
      type = {
        "literal", "normal", "operator", "normal",
        "literal", "normal", "operator"
      }
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
    -- Match scope operator element access
    { pattern = "[%a_][%w_]*()%s*()::",
      type = { "literal", "normal", "operator" }
    },
    -- Uppercase constants of at least 2 chars in len
    { pattern = "_?%u[%u_][%u%d_]*%f[%s%+%*%-%.%)%]}%?%^%%=/<>~|&;:,!]",
      type = "number"
    },
    -- Magic constants
    { pattern = "__[%u%l]+__",              type = "number"   },
    -- all other functions
    { pattern = "[%a_][%w_]*%f[(]",         type = "function" },
    -- Macros
    { pattern = "^%s*#%s*define%s+()[%a_][%a%d_]*",
      type = { "keyword", "symbol" }
    },
    { pattern = "#%s*include%s+()<.->",
      type = { "keyword", "string" }
    },
    { pattern = "%f[#]#%s*[%a_][%w_]*",     type = "keyword"   },
    -- Everything else to make the tokenizer work properly
    { pattern = "[%a_][%w_]*",              type = "symbol"   },
  },
  symbols = {
    ["alignof"]  = "keyword",
    ["alignas"]  = "keyword",
    ["and"]      = "keyword",
    ["and_eq"]   = "keyword",
    ["not"]      = "keyword",
    ["not_eq"]   = "keyword",
    ["or"]       = "keyword",
    ["or_eq"]    = "keyword",
    ["xor"]      = "keyword",
    ["xor_eq"]   = "keyword",
    ["private"]  = "keyword",
    ["protected"] = "keyword",
    ["public"]   = "keyword",
    ["register"] = "keyword",
    ["nullptr"]  = "keyword",
    ["operator"] = "keyword",
    ["asm"]      = "keyword",
    ["bitand"]   = "keyword",
    ["bitor"]    = "keyword",
    ["catch"]    = "keyword",
    ["throw"]    = "keyword",
    ["try"]      = "keyword",
    ["class"]    = "keyword",
    ["compl"]    = "keyword",
    ["explicit"] = "keyword",
    ["export"]   = "keyword",
    ["concept"]  = "keyword",
    ["consteval"] = "keyword",
    ["constexpr"] = "keyword",
    ["constinit"] = "keyword",
    ["const_cast"] = "keyword",
    ["dynamic_cast"] = "keyword",
    ["reinterpret_cast"]   = "keyword",
    ["static_cast"]   = "keyword",
    ["static_assert"] = "keyword",
    ["template"]  = "keyword",
    ["this"]      = "keyword",
    ["thread_local"] = "keyword",
    ["requires"]  = "keyword",
    ["co_await"]   = "keyword",
    ["co_return"] = "keyword",
    ["co_yield"]  = "keyword",
    ["decltype"] = "keyword",
    ["delete"]   = "keyword",
    ["friend"]   = "keyword",
    ["typeid"]   = "keyword",
    ["typename"] = "keyword",
    ["mutable"]  = "keyword",
    ["override"] = "keyword",
    ["virtual"]  = "keyword",
    ["using"]    = "keyword",
    ["namespace"] = "keyword",
    ["new"]      = "keyword",
    ["noexcept"] = "keyword",
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
    ["struct"]   = "keyword",
    ["union"]    = "keyword",
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
    ["wchar_t"]  = "keyword2",
    ["char8_t"]  = "keyword2",
    ["char16_t"] = "keyword2",
    ["char32_t"] = "keyword2",
    ["#include"] = "keyword",
    ["#if"]      = "keyword",
    ["#ifdef"]   = "keyword",
    ["#ifndef"]  = "keyword",
    ["#elif"]    = "keyword",
    ["#else"]    = "keyword",
    ["#elseif"]  = "keyword",
    ["#endif"]   = "keyword",
    ["#define"]  = "keyword",
    ["#warning"] = "keyword",
    ["#error"]   = "keyword",
    ["#pragma"]  = "keyword",
  },
}
