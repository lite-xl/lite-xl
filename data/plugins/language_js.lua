-- mod-version:3
local syntax = require "core.syntax"

-- Regex pattern explanation:
-- This will match / and will look ahead for something that looks like a regex.
--
-- (?!/) Don't match empty regexes.
--
-- (?>...) this is using an atomic group to minimize backtracking, as that'd
--         cause "Catastrophic Backtracking" in some cases.
--
-- [^\\[\/]++ will match anything that's isn't an escape, a start of character
--           class or an end of pattern, without backtracking (the second +).
--
-- \\. will match anything that's escaped.
--
-- \[(?:[^\\\]++]|\\.)*+\] will match character classes.
--
-- /[gmiyuvsd]*\s*[\n,;\)\]\}\.]) will match the end of pattern delimiter, optionally
--                                followed by pattern options, and anything that can
--                                be after a pattern.
--
-- Demo with some unit tests (click on the Unit Tests entry): https://regex101.com/r/Vx5L5V/1
-- Note that it has a couple of changes to make it work on that platform.
local regex_pattern = {
  [=[\/(?=(?!\/)(?:(?>[^\\[\/]++|\\.|\[(?:[^\\\]]++|\\.)*+\])*+)++\/[gmiyuvsd]*\s*(?:[\n,;\)\]\}\.]|\/[\/*]))()]=],
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
    { pattern = "//.*",                                               type = "comment"  },
    { pattern = { "/%*", "%*/" },                                     type = "comment"  },
    { regex = regex_pattern, syntax = inner_regex_syntax,             type = {"string", "string"}  },
    { pattern = { '"', '"', '\\' },                                   type = "string"   },
    { pattern = { "'", "'", '\\' },                                   type = "string"   },
    { pattern = { "`", "`", '\\' },                                   type = "string"   },
    -- Use (?:\/(?!\/|\*))? to avoid that a regex can start after a number, while also allowing // and /* comments
    { regex   = [[-?0[xXbBoO][\da-fA-F_]+n?()\s*()(?:\/(?!\/|\*))?]], type = {"number", "normal", "operator"}   },
    { regex   = [[-?\d+[0-9.eE_n]*()\s*()(?:\/(?!\/|\*))?]],          type = {"number", "normal", "operator"}   },
    { regex   = [[-?\.?\d+()\s*()(?:\/(?!\/|\*))?]],                  type = {"number", "normal", "operator"}   },
    { pattern = "[%+%-=/%*%^%%<>!~|&]",                               type = "operator" },
    { pattern = "[%a_][%w_]*%f[(]",                                   type = "function" },
    { pattern = "[%a_][%w_]*",                                        type = "symbol"   },
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
    ["from"]       = "keyword",    
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
