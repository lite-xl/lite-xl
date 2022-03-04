-- mod-version:2 -- lite-xl 2.0
local syntax = require "core.syntax"
local style = require "core.style"
local core = require "core"

local initial_scale = SCALE
local initial_color = style.syntax["keyword2"]

-- Add 3 type of font styles for use on markdown files
for _, attr in pairs({"bold", "italic", "bold_italic"}) do
  local attributes = {}
  if attr ~= "bold_italic" then
    attributes[attr] = true
  else
    attributes["bold"] = true
    attributes["italic"] = true
  end
  -- no way to copy user custom font with additional attributes :(
  style.syntax_fonts["markdown_"..attr] = renderer.font.load(
    DATADIR .. "/fonts/JetBrainsMono-Regular.ttf",
    style.code_font:get_size(),
    attributes
  )
  -- also add a color for it
  style.syntax["markdown_"..attr] = style.syntax["keyword2"]
end

local in_squares_match = "^%[%]"
local in_parenthesis_match = "^%(%)"

syntax.add {
  name = "Markdown",
  files = { "%.md$", "%.markdown$" },
  block_comment = { "<!--", "-->" },
  patterns = {
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
    -- code blocks
    { pattern = { "```c++", "```" },        type = "string", syntax = ".cpp" },
    { pattern = { "```cpp", "```" },        type = "string", syntax = ".cpp" },
    { pattern = { "```python", "```" },     type = "string", syntax = ".py" },
    { pattern = { "```ruby", "```" },       type = "string", syntax = ".rb" },
    { pattern = { "```perl", "```" },       type = "string", syntax = ".pl" },
    { pattern = { "```php", "```" },        type = "string", syntax = ".php" },
    { pattern = { "```javascript", "```" }, type = "string", syntax = ".js" },
    { pattern = { "```json", "```" },       type = "string", syntax = ".js" },
    { pattern = { "```html", "```" },       type = "string", syntax = ".html" },
    { pattern = { "```ini", "```" },        type = "string", syntax = ".ini" },
    { pattern = { "```xml", "```" },        type = "string", syntax = ".xml" },
    { pattern = { "```css", "```" },        type = "string", syntax = ".css" },
    { pattern = { "```lua", "```" },        type = "string", syntax = ".lua" },
    { pattern = { "```bash", "```" },       type = "string", syntax = ".sh" },
    { pattern = { "```sh", "```" },         type = "string", syntax = ".sh" },
    { pattern = { "```java", "```" },       type = "string", syntax = ".java" },
    { pattern = { "```c#", "```" },         type = "string", syntax = ".cs" },
    { pattern = { "```cmake", "```" },      type = "string", syntax = ".cmake" },
    { pattern = { "```d", "```" },          type = "string", syntax = ".d" },
    { pattern = { "```glsl", "```" },       type = "string", syntax = ".glsl" },
    { pattern = { "```c", "```" },          type = "string", syntax = ".c" },
    { pattern = { "```julia", "```" },      type = "string", syntax = ".jl" },
    { pattern = { "```rust", "```" },       type = "string", syntax = ".rs" },
    { pattern = { "```dart", "```" },       type = "string", syntax = ".dart" },
    { pattern = { "```v", "```" },          type = "string", syntax = ".v" },
    { pattern = { "```toml", "```" },       type = "string", syntax = ".toml" },
    { pattern = { "```yaml", "```" },       type = "string", syntax = ".yaml" },
    { pattern = { "```nim", "```" },        type = "string", syntax = ".nim" },
    { pattern = { "```typescript", "```" }, type = "string", syntax = ".ts" },
    { pattern = { "```rescript", "```" },   type = "string", syntax = ".res" },
    { pattern = { "```moon", "```" },       type = "string", syntax = ".moon" },
    { pattern = { "```go", "```" },         type = "string", syntax = ".go" },
    { pattern = { "```lobster", "```" },    type = "string", syntax = ".lobster" },
    { pattern = { "```liquid", "```" },     type = "string", syntax = ".liquid" },
    { pattern = { "```", "```" },           type = "string" },
    { pattern = { "``", "``" },             type = "string" },
    { pattern = { "`", "`" },               type = "string" },
    -- strike
    { pattern = { "~~", "~~" },             type = "keyword2" },
    -- highlight
    { pattern = { "==", "==" },             type = "literal" },
    -- lines
    { regex = "^\\-{2,}\\-$",               type = "comment" },
    { regex = "^\\*{2,}\\*$",               type = "comment" },
    { regex = "^\\_{2,}_$",                 type = "comment" },
    -- bullets
    { regex = "^\\s*\\*\\s",                type = "number" },
    { regex = "^\\s*-\\s",                  type = "number" },
    { regex = "^\\s*\\+\\s",                type = "number" },
    -- numbered bullet
    { regex = "^\\s*[0-9]+\\.\\s",          type = "number" },
    -- blockquote
    { regex = "^\\s*>{1,}\\s",              type = "string" },
    -- bold and italic
    { pattern = { "%*%*%*", "%*%*%*" },     type = "markdown_bold_italic" },
    { pattern = { "%*%*", "%*%*" },         type = "markdown_bold" },
    -- handle edge case where asterisk can be at end of line and not close
    { pattern = { "%*[%S]", "%*" },         type = "markdown_italic" },
    -- alternative bold italic formats
    {
      regex = "^_{3}[\\s[:punct:]A-Za-z0-9]+_{3}\\s" ,
      type = "markdown_bold_italic"
    },
    {
      regex = "^_{2}[\\s[:punct:]A-Za-z0-9]+_{2}\\s" ,
      type = "markdown_bold"
    },
    {
      regex = "^_{1}[\\s[:punct:]A-Za-z0-9]+_{1}\\s" ,
      type = "markdown_italic"
    },
    { pattern = { "%s___", "___%f[%s]" },   type = "markdown_bold_italic" },
    { pattern = { "%s__", "__%f[%s]" },     type = "markdown_bold" },
    { pattern = { "%s_[%S]", "_%f[%s]" },   type = "markdown_italic" },
    -- headings
    { regex = "^#{1,6}.+",                  type = "keyword" },
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
    { regex = "^:\\s.+",                    type = "function" },
    -- emoji
    { pattern = ":[a-zA-Z0-9_%-]+:",        type = "literal" },
    -- images and links
    {
      pattern = "!?%[()["..in_squares_match.."]+()%]()%(()["..in_parenthesis_match.."]+()%)",
      type = { "function", "string", "function", "function", "number", "function" }
    },
    -- reference links
    {
      pattern = "%[()["..in_squares_match.."]+()%] *()%[()["..in_squares_match.."]+()%]",
      type = { "function", "string", "function", "function", "number", "function" }
    },
    {
      pattern = "%[%^?()["..in_squares_match.."]+()%]: ",
      type = { "function", "number", "function" }
    },
    {
      pattern = "%[%^?()["..in_squares_match.."]+()%]",
      type = { "function", "number", "function" }
    },
    -- url's and email
    {
      pattern = "<[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+%.[a-zA-Z0-9-.]+>",
      type = "function"
    },
    { pattern = "<https?://%S+>",           type = "function" },
    { pattern = "https?://%S+",             type = "function" }
  },
  symbols = { },
}

-- Adjust markdown fonts on scale changes.
-- Note: this should be performed by lite-xl it self to all style.syntax_fonts
core.add_thread(function()
  while true do
    if initial_scale ~= SCALE then
      for _, attr in pairs({"bold", "italic", "bold_italic"}) do
        style.syntax_fonts["markdown_"..attr] =
          style.syntax_fonts["markdown_"..attr]:copy(
            style.code_font:get_size()
        )
      end
      initial_scale = SCALE
    end
    -- we also adjust the color on theme changes
    if initial_color ~= style.syntax["keyword2"] then
      for _, attr in pairs({"bold", "italic", "bold_italic"}) do
        style.syntax["markdown_"..attr] = style.syntax["keyword2"]
      end
      initial_color = style.syntax["keyword2"]
    end
    coroutine.yield(1)
  end
end)
