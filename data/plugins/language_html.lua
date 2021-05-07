-- mod-version:1 -- lite-xl 1.16
local syntax = require "core.syntax"

syntax.add {
  files = { "%.html?$" },
  patterns = {
    { 
      pattern = { 
        "<%s*[sS][cC][rR][iI][pP][tT]%s+[tT][yY][pP][eE]%s*=%s*" ..
          "['\"]%a+/[jJ][aA][vV][aA][sS][cC][rR][iI][pP][tT]['\"]%s*>",
        "<%s*/[sS][cC][rR][iI][pP][tT]>" 
      },
      syntax = ".js", 
      type = "function" 
    },
    { 
      pattern = { 
        "<%s*[sS][cC][rR][iI][pP][tT]%s*>",
        "<%s*/%s*[sS][cC][rR][iI][pP][tT]>" 
      },
      syntax = ".js",
      type = "function"
    },
    { 
      pattern = { 
        "<%s*[sS][tT][yY][lL][eE][^>]*>", 
        "<%s*/%s*[sS][tT][yY][lL][eE]%s*>" 
      },
      syntax = ".css",
      type = "function"
    },
    { pattern = { "<!%-%-", "%-%->" },     type = "comment"  },
    { pattern = { '%f[^>][^<]', '%f[<]' }, type = "normal"   },
    { pattern = { '"', '"', '\\' },        type = "string"   },
    { pattern = { "'", "'", '\\' },        type = "string"   },
    { pattern = "0x[%da-fA-F]+",           type = "number"   },
    { pattern = "-?%d+[%d%.]*f?",          type = "number"   },
    { pattern = "-?%.?%d+f?",              type = "number"   },
    { pattern = "%f[^<]![%a_][%w_]*",      type = "keyword2" },
    { pattern = "%f[^<][%a_][%w_]*",       type = "function" },
    { pattern = "%f[^<]/[%a_][%w_]*",      type = "function" },
    { pattern = "[%a_][%w_]*",             type = "keyword"  },
    { pattern = "[/<>=]",                  type = "operator" },
  },
  symbols = {},
}
