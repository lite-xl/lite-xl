-- mod-version:2 -- lite-xl 2.0
local syntax = require "core.syntax"



syntax.add {
  name = "Markdown",
  files = { "%.md$", "%.markdown$" },
  patterns = {
    { pattern = "\\.",                      type = "normal"   },
    { pattern = { "<!%-%-", "%-%->" },      type = "comment"  },
    { pattern = { "```c", "```" },          type = "string", syntax = ".c" },
    { pattern = { "```c++", "```" },        type = "string", syntax = ".cpp" },
    { pattern = { "```python", "```" },     type = "string", syntax = ".py" },
    { pattern = { "```ruby", "```" },       type = "string", syntax = ".rb" },
    { pattern = { "```perl", "```" },       type = "string", syntax = ".pl" },
    { pattern = { "```php", "```" },        type = "string", syntax = ".php" },
    { pattern = { "```javascript", "```" }, type = "string", syntax = ".js" },
    { pattern = { "```html", "```" },       type = "string", syntax = ".html" },
    { pattern = { "```xml", "```" },        type = "string", syntax = ".xml" },
    { pattern = { "```css", "```" },        type = "string", syntax = ".css" },
    { pattern = { "```lua", "```" },        type = "string", syntax = ".lua" },
    { pattern = { "```bash", "```" },       type = "string", syntax = ".sh" },
    { pattern = { "```java", "```" },       type = "string", syntax = ".java" },
    { pattern = { "```c#", "```" },         type = "string", syntax = ".cs" },
    { pattern = { "```cmake", "```" },      type = "string", syntax = ".cmake" },
    { pattern = { "```d", "```" },          type = "string", syntax = ".d" },
    { pattern = { "```glsl", "```" },       type = "string", syntax = ".glsl" },
    { pattern = { "```", "```" },           type = "string"   },
    { pattern = { "``", "``", "\\" },       type = "string"   },
    { pattern = { "`", "`", "\\" },         type = "string"   },
    { pattern = { "~~", "~~", "\\" },       type = "keyword2" },
    { pattern = "%-%-%-+",                  type = "comment" },
    { pattern = "%*%s+",                    type = "operator" },
    { pattern = { "%*", "[%*\n]", "\\" },   type = "operator" },
    { pattern = { "%_", "[%_\n]", "\\" },   type = "keyword2" },
    { pattern = "#.-\n",                    type = "keyword"  },
    { pattern = "!?%[.-%]%(.-%)",           type = "function" },
    { pattern = "https?://%S+",             type = "function" },
  },
  symbols = { },
}
