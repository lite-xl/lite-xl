-- mod-version:3
local syntax = require "core.syntax"

-- Regex pattern explanation:
-- This will match / and will look ahead for something that looks like a regex.
--
-- (?!/) Don't match empty regexes.
--
-- (?>[^\\[\/]*) is an atomic group, this matches anything that's not "special";
--               this is using an atomic group to minimize backtracking,
--               as that'd cause "Catastrophic Backtracking" in some cases.
--
-- \\(?:\\{2})*. will match anything that's escaped, so that we can ignore it.
--
-- (?:\\{2})*\[.*?(?<!\\)(?:\\{2})*\] will match character classes.
--
-- /[gmiyuvsd]*\s*[\n,;\)]) will match the end of pattern delimiter, optionally
--                          followed by pattern options, and anything that can
--                          be after a pattern.
--
-- Demo with some unit tests (click on the Unit Tests entry): https://regex101.com/r/EDgjPH/1
-- Note that it has a couple of changes to make it work on that platform.
local regex_pattern = {
  [=[/(?=(?!/)(?:(?>[^\\[\/]*)(?:\\(?:\\{2})*.|(?:\\{2})*\[.*?(?<!\\)(?:\\{2})*\])*)+/[gmiyuvsd]*\s*[\n,;\)])()]=],
  "/()[gmiyuvsd]*", "\\"
}

-- For the moment let's not actually differentiate the insides of the regex,
-- as this will need new token types...
local inner_regex_syntax = {
  patterns = {
    { pattern = "%(()%?[:!=><]", type = { "string", "string" } },
    { pattern = "[.?+*%(%)|]", type = "string" },
    { pattern = "{%d*,?%d*}", type = "string" },
    { regex = { [=[\[()\^?]=], [=[(?:\]|(?=\n))()]=], "\\" },
      type = { "string", "string" },
      syntax = { -- Inside character class
        patterns = {
          { pattern = "\\\\", type = "string" },
          { pattern = "\\%]", type = "string" },
          { pattern = "[^%]\n]", type = "string" }
        },
        symbols = {}
      }
    },
    { regex = "\\/", type = "string" },
    { regex = "[^/\n]", type = "string" },
  },
  symbols = {}
}

syntax.add {
  name = "JavaScript",
  files = { "%.js$", "%.json$", "%.cson$", "%.mjs$", "%.cjs$" },
  comment = "//",
  block_comment = { "/*", "*/" },
  patterns = {
    { pattern = "//.*",                      type = "comment"  },
    { pattern = { "/%*", "%*/" },            type = "comment"  },
    { regex = regex_pattern, syntax = inner_regex_syntax, type = {"string", "string"}  },
    { pattern = { '"', '"', '\\' },          type = "string"   },
    { pattern = { "'", "'", '\\' },          type = "string"   },
    { pattern = { "`", "`", '\\' },          type = "string"   },
    { pattern = "0x[%da-fA-F_]+n?()%s*()/?", type = {"number", "normal", "operator"}   },
    { pattern = "-?%d+[%d%.eE_n]*()%s*()/?", type = {"number", "normal", "operator"}   },
    { pattern = "-?%.?%d+()%s*()/?",         type = {"number", "normal", "operator"}   },
    { pattern = "[%+%-=/%*%^%%<>!~|&]",      type = "operator" },
    { pattern = "[%a_][%w_]*%f[(]",          type = "function" },
    { pattern = "[%a_][%w_]*()%s*()/?",      type = {"symbol", "normal", "operator"}   },
  },
  symbols = {
    ["async"]      = "keyword",
    ["await"]      = "keyword",
    ["break"]      = "keyword",
    ["case"]       = "keyword",
    ["catch"]      = "keyword",
    ["class"]      = "keyword",
    ["const"]      = "keyword",
    ["continue"]   = "keyword",
    ["debugger"]   = "keyword",
    ["default"]    = "keyword",
    ["delete"]     = "keyword",
    ["do"]         = "keyword",
    ["else"]       = "keyword",
    ["export"]     = "keyword",
    ["extends"]    = "keyword",
    ["finally"]    = "keyword",
    ["for"]        = "keyword",
    ["function"]   = "keyword",
    ["get"]        = "keyword",
    ["if"]         = "keyword",
    ["import"]     = "keyword",
    ["in"]         = "keyword",
    ["of"]         = "keyword",
    ["instanceof"] = "keyword",
    ["let"]        = "keyword",
    ["new"]        = "keyword",
    ["return"]     = "keyword",
    ["set"]        = "keyword",
    ["static"]     = "keyword",
    ["super"]      = "keyword",
    ["switch"]     = "keyword",
    ["throw"]      = "keyword",
    ["try"]        = "keyword",
    ["typeof"]     = "keyword",
    ["var"]        = "keyword",
    ["void"]       = "keyword",
    ["while"]      = "keyword",
    ["with"]       = "keyword",
    ["yield"]      = "keyword",
    ["true"]       = "literal",
    ["false"]      = "literal",
    ["null"]       = "literal",
    ["undefined"]  = "literal",
    ["arguments"]  = "keyword2",
    ["Infinity"]   = "keyword2",
    ["NaN"]        = "keyword2",
    ["this"]       = "keyword2",
  },
}
