-- mod-version:4
local syntax = require "core.syntax"
local style = require "core.style"
local core = require "core"

local in_squares_match = "^%[%]"
local in_parenthesis_match = "^%(%)"

syntax.add {
  name = "Markdown",
  files = { "%.md$", "%.markdown$" },
  block_comment = { "<!--", "-->" },
  space_handling = false, -- turn off this feature to handle it our selfs
  patterns = {
  ---- Place patterns that require spaces at start to optimize matching speed
  ---- and apply the %s+ optimization immediately afterwards
    -- bullets
    { pattern = "^%s*%*%s",                 type = "number" },
    { pattern = "^%s*%-%s",                 type = "number" },
    { pattern = "^%s*%+%s",                 type = "number" },
    -- numbered bullet
    { pattern = "^%s*[0-9]+[%.%)]%s",       type = "number" },
    -- blockquote
    { pattern = "^%s*>+%s",                 type = "string" },
    -- alternative bold italic formats
    { pattern = { "%s___", "___" },         type = "markdown_bold_italic" },
    { pattern = { "%s__", "__" },           type = "markdown_bold" },
    { pattern = { "%s_[%S]", "_" },         type = "markdown_italic" },
    -- reference links
    {
      pattern = "^%s*%[%^()["..in_squares_match.."]+()%]: ",
      type = { "function", "number", "function" }
    },
    {
      pattern = "^%s*%[%^?()["..in_squares_match.."]+()%]:%s+.*",
      type = { "function", "number", "function" }
    },
    -- optimization
    { pattern = "%s+",                      type = "normal" },

  ---- HTML rules imported and adapted from language_html
  ---- to not conflict with markdown rules
    -- Inline JS and CSS
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
    -- Comments
    { pattern = { "<!%-%-", "%-%->" },   type = "comment" },
    -- Tags
    { pattern = "%f[^<]![%a_][%w_]*",    type = "keyword2" },
    { pattern = "%f[^<][%a_][%w_]*",     type = "function" },
    { pattern = "%f[^<]/[%a_][%w_]*",    type = "function" },
    -- Attributes
    {
      pattern = "[a-z%-]+%s*()=%s*()\".-\"",
      type = { "keyword", "operator", "string" }
    },
    {
      pattern = "[a-z%-]+%s*()=%s*()'.-'",
      type = { "keyword", "operator", "string" }
    },
    {
      pattern = "[a-z%-]+%s*()=%s*()%-?%d[%d%.]*",
      type = { "keyword", "operator", "number" }
    },
    -- Entities
    { pattern = "&#?[a-zA-Z0-9]+;",         type = "keyword2" },

  ---- Markdown rules
    -- math
    { pattern = { "%$%$", "%$%$", "\\"  },  type = "string", syntax = ".tex"},
    { regex   = { "\\$", [[\$|(?=\\*\n)]], "\\" },  type = "string", syntax = ".tex"},
    -- code blocks
    { pattern = { "```caddyfile", "```" },  type = "string", hard_lexical_stop = true, syntax = "Caddyfile" },
    { pattern = { "```c++", "```" },        type = "string", hard_lexical_stop = true, syntax = ".cpp" },
    { pattern = { "```cpp", "```" },        type = "string", hard_lexical_stop = true, syntax = ".cpp" },
    { pattern = { "```python", "```" },     type = "string", hard_lexical_stop = true, syntax = ".py" },
    { pattern = { "```ruby", "```" },       type = "string", hard_lexical_stop = true, syntax = ".rb" },
    { pattern = { "```perl", "```" },       type = "string", hard_lexical_stop = true, syntax = ".pl" },
    { pattern = { "```php", "```" },        type = "string", hard_lexical_stop = true, syntax = ".php" },
    { pattern = { "```javascript", "```" }, type = "string", hard_lexical_stop = true, syntax = ".js" },
    { pattern = { "```json", "```" },       type = "string", hard_lexical_stop = true, syntax = ".js" },
    { pattern = { "```html", "```" },       type = "string", hard_lexical_stop = true, syntax = ".html" },
    { pattern = { "```ini", "```" },        type = "string", hard_lexical_stop = true, syntax = ".ini" },
    { pattern = { "```xml", "```" },        type = "string", hard_lexical_stop = true, syntax = ".xml" },
    { pattern = { "```css", "```" },        type = "string", hard_lexical_stop = true, syntax = ".css" },
    { pattern = { "```lua", "```" },        type = "string", hard_lexical_stop = true, syntax = ".lua" },
    { pattern = { "```bash", "```" },       type = "string", hard_lexical_stop = true, syntax = ".sh" },
    { pattern = { "```sh", "```" },         type = "string", hard_lexical_stop = true, syntax = ".sh" },
    { pattern = { "```java", "```" },       type = "string", hard_lexical_stop = true, syntax = ".java" },
    { pattern = { "```c#", "```" },         type = "string", hard_lexical_stop = true, syntax = ".cs" },
    { pattern = { "```cmake", "```" },      type = "string", hard_lexical_stop = true, syntax = ".cmake" },
    { pattern = { "```d", "```" },          type = "string", hard_lexical_stop = true, syntax = ".d" },
    { pattern = { "```glsl", "```" },       type = "string", hard_lexical_stop = true, syntax = ".glsl" },
    { pattern = { "```c", "```" },          type = "string", hard_lexical_stop = true, syntax = ".c" },
    { pattern = { "```julia", "```" },      type = "string", hard_lexical_stop = true, syntax = ".jl" },
    { pattern = { "```rust", "```" },       type = "string", hard_lexical_stop = true, syntax = ".rs" },
    { pattern = { "```dart", "```" },       type = "string", hard_lexical_stop = true, syntax = ".dart" },
    { pattern = { "```v", "```" },          type = "string", hard_lexical_stop = true, syntax = ".v" },
    { pattern = { "```toml", "```" },       type = "string", hard_lexical_stop = true, syntax = ".toml" },
    { pattern = { "```yaml", "```" },       type = "string", hard_lexical_stop = true, syntax = ".yaml" },
    { pattern = { "```nim", "```" },        type = "string", hard_lexical_stop = true, syntax = ".nim" },
    { pattern = { "```typescript", "```" }, type = "string", hard_lexical_stop = true, syntax = ".ts" },
    { pattern = { "```rescript", "```" },   type = "string", hard_lexical_stop = true, syntax = ".res" },
    { pattern = { "```moon", "```" },       type = "string", hard_lexical_stop = true, syntax = ".moon" },
    { pattern = { "```go", "```" },         type = "string", hard_lexical_stop = true, syntax = ".go" },
    { pattern = { "```lobster", "```" },    type = "string", hard_lexical_stop = true, syntax = ".lobster" },
    { pattern = { "```liquid", "```" },     type = "string", hard_lexical_stop = true, syntax = ".liquid" },
    { pattern = { "```nix", "```" },        type = "string", hard_lexical_stop = true, syntax = ".nix" },
    { pattern = { "```", "```" },           type = "string", hard_lexical_stop = true },
    { pattern = { "``", "``" },             type = "string" },
    { pattern = { "%f[\\`]%`[%S]", "`" },   type = "string" },
    -- lines
    { pattern = "^%-%-%-+\n" ,              type = "comment" },
    { pattern = "^%*%*%*+\n",               type = "comment" },
    { pattern = "^___+\n",                  type = "comment" },
    { pattern = "^===+\n",                  type = "comment" },
    -- strike
    { pattern = { "~~", "~~" },             type = "keyword2" },
    -- highlight
    { pattern = { "==", "==" },             type = "literal" },
    -- bold and italic
    { pattern = { "%*%*%*%S", "%*%*%*" },   type = "markdown_bold_italic" },
    { pattern = { "%*%*%S", "%*%*" },       type = "markdown_bold" },
    -- handle edge case where asterisk can be at end of line and not close
    {
      pattern = { "%f[\\%*]%*[%S]", "%*%f[^%*]" },
      type = "markdown_italic"
    },
    -- alternative bold italic formats
    { pattern = "^___[%s%p%w]+___" ,        type = "markdown_bold_italic" },
    { pattern = "^__[%s%p%w]+__" ,          type = "markdown_bold" },
    { pattern = "^_[%s%p%w]+_" ,            type = "markdown_italic" },
    -- heading with custom id
    {
      pattern = "^#+%s[%w%s%p]+(){()#[%w%-]+()}",
      type = { "keyword", "function", "string", "function" }
    },
    -- headings
    { pattern = "^#+%s.+\n",                type = "keyword" },
    -- superscript and subscript
    {
      pattern = "%^()%d+()%^",
      type = { "function", "number", "function" }
    },
    {
      pattern = "%~()%d+()%~",
      type = { "function", "number", "function" }
    },
    -- definitions
    { pattern = "^:%s.+",                   type = "function" },
    -- emoji
    { pattern = ":[a-zA-Z0-9_%-]+:",        type = "literal" },
    -- images and link
    {
      pattern = "!?%[!?%[()["..in_squares_match.."]+()%]%(()["..in_parenthesis_match.."]+()%)%]%(()["..in_parenthesis_match.."]+()%)",
      type = { "function", "string", "function", "number", "function", "number", "function" }
    },
    {
      pattern = "!?%[!?%[?()["..in_squares_match.."]+()%]?%]%(()["..in_parenthesis_match.."]+()%)",
      type = { "function", "string", "function", "number", "function" }
    },
    -- reference links
    {
      pattern = "%[()["..in_squares_match.."]+()%] *()%[()["..in_squares_match.."]+()%]",
      type = { "function", "string", "function", "function", "number", "function" }
    },
    {
      pattern = "!?%[%^?()["..in_squares_match.."]+()%]",
      type = { "function", "number", "function" }
    },
    -- url's and email
    {
      pattern = "<[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+%.[a-zA-Z0-9-.]+>",
      type = "function"
    },
    { pattern = "<https?://%S+>",           type = "function" },
    { pattern = "https?://%S+",             type = "function" },
    -- optimize consecutive dashes used in tables
    { pattern = "%-+",                      type = "normal" },
  },
  symbols = { },
}

-- Adjust the color on theme changes
core.add_thread(function()
  local custom_fonts = { bold = {font = nil, color = nil}, italic = {}, bold_italic = {} }
  local initial_color
  local last_code_font

  local function set_font(attr)
    local attributes = {}
    if attr ~= "bold_italic" then
      attributes[attr] = true
    else
      attributes["bold"] = true
      attributes["italic"] = true
    end
    local font = style.code_font:copy(
      style.code_font:get_size(),
      attributes
    )
    custom_fonts[attr].font = font
    style.syntax_fonts["markdown_"..attr] = font
  end

  local function set_color(attr)
    custom_fonts[attr].color = style.syntax["keyword2"]
    style.syntax["markdown_"..attr] = style.syntax["keyword2"]
  end

  -- Add 3 type of font styles for use on markdown files
  for attr, _ in pairs(custom_fonts) do
    -- Only set it if the font wasn't manually customized
    if not style.syntax_fonts["markdown_"..attr] then
      set_font(attr)
    end

    -- Only set it if the color wasn't manually customized
    if not style.syntax["markdown_"..attr] then
      set_color(attr)
    end
  end

  while true do
    if last_code_font ~= style.code_font then
      last_code_font = style.code_font
      for attr, _ in pairs(custom_fonts) do
        -- Only set it if the font wasn't manually customized
        if style.syntax_fonts["markdown_"..attr] == custom_fonts[attr].font then
          set_font(attr)
        end
      end
    end

    if initial_color ~= style.syntax["keyword2"] then
      initial_color = style.syntax["keyword2"]
      for attr, _ in pairs(custom_fonts) do
        -- Only set it if the color wasn't manually customized
        if style.syntax["markdown_"..attr] == custom_fonts[attr].color then
          set_color(attr)
        end
      end
    end
    coroutine.yield(1)
  end
end)
