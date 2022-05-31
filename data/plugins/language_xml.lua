-- mod-version:3
local syntax = require "core.syntax"

syntax.add {
  name = "XML",
  files = { "%.xml$" },
  headers = "<%?xml",
  block_comment = { "<!--", "-->" },
  patterns = {
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
