-- mod-version:3
local common = require "core.common"
local config = require "core.config"
local syntax = require "core.syntax"

-- Documentation for annotations:
-- https://github.com/sumneko/lua-language-server/wiki/Annotations
local annotations_syntax = {
  patterns = {
    -- look-aheads for table and function types
    { regex = [[@[\w_]+()\s+(?=(?:table\s*<|fun\s*\())]],
      type = { "keyword", "comment" }
    },
    { regex = [[@[\w_]+\s+()[\w\._]+()\??()\s*(?=(?:table\s*<|fun\s*\())]],
      type = { "keyword", "symbol", "operator", "comment" }
    },
    { regex = "@field"
        .. [[()\s+(?:protected|public|private|package)\s+]]
        .. [[()[\w\._]+]]
        .. [[()\??]]
        .. [[()\s*(?=(?:table\s*<|fun\s*\())]],
      type = { "keyword", "keyword", "symbol", "operator", "comment" }
    },
    -- table and function types
    { pattern = "table%s*%b<>", type = "keyword2" },
    { pattern = "fun%s*%b()%s*:%s*[%S]+", type = "keyword2" },
    { pattern = "fun%s*%b()", type = "keyword2" },
    -- @alias with string type
    { pattern = "@alias%s+()[%w%._]+()%s+%b''",
      type = { "keyword", "symbol", "string" }
    },
    { pattern = "@alias%s+()[%w%._]+()%s+%b\"\"",
      type = { "keyword", "symbol", "string" }
    },
    -- @alias with type
    { pattern = "@alias%s+()[%w%._]+()%s+[%S]+",
      type = { "keyword", "symbol", "keyword2" }
    },
    -- @alias without type
    { pattern = "@alias%s+()[%w%._]+", type = { "keyword", "symbol" } },
    -- @cast with type
    { pattern = "@cast%s+()[%w%._]+%s+()[%w%.%[%]_]+()%??",
      type = { "keyword", "symbol", "keyword2", "operator" }
    },
    -- @cast without type
    { pattern = "@cast%s+()[%w%._]+", type = { "keyword", "symbol" } },
    -- @class with parent
    { pattern = "@class%s+()[%w%._]+%s*():()%s*[%S]+",
      type = { "keyword", "symbol", "operator", "keyword2"}
    },
    -- @class without parent
    { pattern = "@class%s+()[%S]+", type = { "keyword", "symbol" } },
    -- @diagnostic with state and diagnostic type
    { pattern = "@diagnostic%s+()[%S]+()%s*:%s*()[%S]+",
      type = { "keyword", "function", "operator", "string" }
    },
    -- @diagnostic with state only
    { pattern = "@diagnostic%s+()[%S]+", type = { "keyword", "function" } },
    -- @enum doc type
    { pattern = "@enum%s+()[%S]+", type = { "keyword", "symbol" } },
    -- @field with access specifier
    { regex = "@field"
        .. [[()\s+(?:protected|public|private|package)\s+]]
        .. [[()[\w\._]+]]
        .. [[()\??]]
        .. [[()\s*'[^']*']],
      type = { "keyword", "keyword", "symbol", "operator", "string" }
    },
    { regex = "@field"
        .. [[()\s+(?:protected|public|private|package)\s+]]
        .. [[()[\w\._]+]]
        .. [[()\??]]
        .. [[()\s*"[^"]*"]],
      type = { "keyword", "keyword", "symbol", "operator", "string" }
    },
    { regex = "@field"
        .. [[()\s+(?:protected|public|private|package)\s+]]
        .. [[()[\w\._]+]]
        .. [[()\??]]
        .. [[()\s*[\w\.\[\]_]+]]
        .. [[()\??]],
      type = {
        "keyword", "keyword", "symbol", "operator", "keyword2", "operator"
      }
    },
    -- @field with type
    { pattern = "@field%s+()[%w%._]+()%??()%s+[%w%.%[%]_]+()%??",
      type = { "keyword", "symbol", "operator", "keyword2", "operator" }
    },
    -- @field with string types
    { pattern = "@field%s+()[%w%._]+()%??()%s+%b''",
      type = { "keyword", "symbol", "operator", "string" }
    },
    { pattern = "@field%s+()[%w%._]+()%??()%s+%b\"\"",
      type = { "keyword", "symbol", "operator", "string" }
    },
    -- @generic with single type
    { pattern = "@generic%s+()[%w%._]+%s*():()%s*[%w%._]+",
      type = { "keyword", "symbol", "operator", "keyword2" }
    },
    -- @generic without type
    { pattern = "@generic%s+()[%w%._]+", type = { "keyword", "symbol" } },
    -- @module doc type
    { pattern = "@module%s+()%b''", type = { "keyword", "string" } },
    { pattern = "@module%s+()%b\"\"", type = { "keyword", "string" } },
    -- @operator doc type
    { pattern = "@operator%s+()[%w_]+", type = { "keyword", "function" } },
    -- @param doc type
    { pattern = "@param%s+()[%w%._]+()%??()%s+%b''",
      type = { "keyword", "symbol", "operator", "string" }
    },
    { pattern = "@param%s+()[%w%._]+()%??()%s+%b\"\"",
      type = { "keyword", "symbol", "operator", "string" }
    },
    { pattern = "@param%s+()[%w%._]+()%??()%s+[%w%.%[%]_]+",
      type = { "keyword", "symbol", "operator", "keyword2" }
    },
    -- @return with name
    { pattern = "@return%s+()[%w%.%[%]_]+()%??()%s+[%w%.%[%]_]+",
      type = { "keyword", "keyword2", "operator", "symbol" }
    },
    -- @return with string
    { pattern = "@return%s+()%b''",   type = { "keyword", "string" } },
    { pattern = "@return%s+()%b\"\"", type = { "keyword", "string" } },
    -- @return without name
    { pattern = "@return%s+()[%w%.%[%]_]+()%??",
      type = { "keyword", "keyword2", "operator" }
    },
    -- type doc tag
    { pattern = "@type%s+()%b''",     type = { "keyword", "string" } },
    { pattern = "@type%s+()%b\"\"",   type = { "keyword", "string" } },
    { pattern = "@type%s+()[%w%._%[%]]+()%??",
      type = { "keyword", "keyword2", "operator" }
    },
    -- @vararg doc type (deprecated)
    { pattern = "@vararg%s+()[%w%.%[%]_]+()%??",
      type = { "keyword", "keyword2", "operator" }
    },
    -- match additional types
    { pattern = "|>?%s*()%b``",       type = { "operator", "string" } },
    { pattern = "|>?%s*()%b\"\"",     type = { "operator", "string" } },
    { pattern = "|>?%s*()%b''",       type = { "operator", "string" } },
    { pattern = "|%s*()table%s*%b<>", type = { "operator", "keyword2" } },
    { pattern = "|%s*()fun%s*%b()%s*:%s*[^%s|]+",
      type = { "operator", "keyword2" }
    },
    { pattern = "|%s*()fun%s*%b()",   type = { "operator", "keyword2" } },
    { pattern = "|%s*()[^%s|?]+()%??",
      type = { "operator", "keyword2", "operator" }
    },
    -- match doc tags syntax for symbols table to properly work
    { pattern = "@[%a_]+%w*",         type = "comment" },
    -- match everything else as normal comment
    { pattern = "[%w%p]+",            type = "comment" },
    -- just in case, prevent the subsyntax from getting outside
    { pattern = "%f[\n]",             type = "comment" }
  },
  symbols = {
    ["@alias"] = "keyword",
    ["@async"] = "keyword",
    ["@class"] = "keyword",
    ["@cast"] = "keyword",
    ["@deprecated"] = "keyword",
    ["@diagnostic"] = "keyword",
    ["@enum"] = "keyword",
    ["@field"] = "keyword",
    ["@generic"] = "keyword",
    ["@meta"] = "keyword",
    ["@module"] = "keyword",
    ["@nodiscard"] = "keyword",
    ["@operator"] = "keyword",
    ["@overload"] = "keyword",
    ["@package"] = "keyword",
    ["@param"] = "keyword",
    ["@private"] = "keyword",
    ["@protected"] = "keyword",
    ["@return"] = "keyword",
    ["@see"] = "keyword",
    ["@source"] = "keyword",
    ["@type"] = "keyword",
    ["@vararg"] = "keyword",
    ["@version"] = "keyword"
  }
}

local annotations_pattern = {
  pattern = { "%-%-%-%s*%f[@|]", "\n" },
  syntax = annotations_syntax,
  type = "comment"
}

config.plugins.language_lua = common.merge({
  annotations = true,
  -- The config specification used by the settings gui
  config_spec = {
    name = "Language Lua",
    {
      label = "Annotations",
      description = "Toggle highlighting of annotation comments.",
      path = "annotations",
      type = "toggle",
      default = true,
      on_apply = function(enabled)
        local syntax_lua = syntax.get("file.lua")
        if enabled then
          if not syntax_lua.patterns[4].syntax then
            table.insert(syntax_lua.patterns, 4, annotations_pattern)
          end
        elseif syntax_lua.patterns[4].syntax then
          table.remove(syntax_lua.patterns, 4)
        end
      end
    }
  }
}, config.plugins.language_lua)

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
        pattern = "%u[%u_][%u%d_]*%f[%s%[%+%*%-%.%(%)%?%^%%=/<>~|&:,~]",
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

-- insert annotations rule after "%[%[", "%]%]"
if config.plugins.language_lua.annotations then
  local syntax_lua = syntax.get("file.lua")
  table.insert(syntax_lua.patterns, 4, annotations_pattern)
end

