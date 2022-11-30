---@meta

---Additional utf8 support not provided by lua.
---@class utf8extra
utf8extra = {}

---UTF-8 equivalent of string.byte
---@param s  string
---@param i? integer
---@param j? integer
---@return integer
---@return ...
function utf8extra.byte(s, i, j) end

---UTF-8 equivalent of string.char
---@param byte integer
---@param ... integer
---@return string
---@return ...
function utf8extra.char(byte, ...) end

---UTF-8 equivalent of string.find
---@param s       string
---@param pattern string
---@param init?   integer
---@param plain?  boolean
---@return integer start
---@return integer end
---@return ... captured
function utf8extra.find(s, pattern, init, plain) end

---UTF-8 equivalent of string.gmatch
---@param s       string
---@param pattern string
---@param init?   integer
---@return fun():string, ...
function utf8extra.gmatch(s, pattern, init) end

---UTF-8 equivalent of string.gsub
---@param s       string
---@param pattern string
---@param repl    string|table|function
---@param n       integer
---@return string
---@return integer count
function utf8extra.gsub(s, pattern, repl, n) end

---UTF-8 equivalent of string.len
---@param s string
---@return integer
function utf8extra.len(s) end

---UTF-8 equivalent of string.lower
---@param s string
---@return string
function utf8extra.lower(s) end

---UTF-8 equivalent of string.match
---@param s       string
---@param pattern string
---@param init?   integer
---@return string | number captured
function utf8extra.match(s, pattern, init) end

---UTF-8 equivalent of string.reverse
---@param s string
---@return string
function utf8extra.reverse(s) end

---UTF-8 equivalent of string.sub
---@param s  string
---@param i  integer
---@param j? integer
---@return string
function utf8extra.sub(s, i, j) end

---UTF-8 equivalent of string.upper
---@param s string
---@return string
function utf8extra.upper(s) end

---Escape a str to UTF-8 format string. It support several escape format:
---* %ddd - which ddd is a decimal number at any length: change Unicode code point to UTF-8 format.
---* %{ddd} - same as %nnn but has bracket around.
---* %uddd - same as %ddd, u stands Unicode
---* %u{ddd} - same as %{ddd}
---* %xhhh - hexadigit version of %ddd
---* %x{hhh} same as %xhhh.
---* %? - '?' stands for any other character: escape this character.
---Example:
---```lua
---local u = utf8.escape
---print(u"%123%u123%{123}%u{123}%xABC%x{ABC}")
---print(u"%%123%?%d%%u")
---```
---@param s  string
---@return string utf8_string
function utf8extra.escape(s) end

---Convert UTF-8 position to byte offset. if only index is given, return byte
---offset of this UTF-8 char index. if both charpos and index is given, a new
---charpos will be calculated, by add/subtract UTF-8 char index to current
---charpos. in all cases, it returns a new char position, and code point
---(a number) at this position.
---@param s  string
---@param charpos? integer
---@param index? integer
---@return integer charpos
---@return integer codepoint
function utf8extra.charpos(s, charpos, index) end

---Iterate though the UTF-8 string s. If only s is given, it can used as a iterator:
---```lua
--- for pos, code in utf8.next, "utf8-string" do
--- -- ...
--- end
---````
---If only charpos is given, return the next byte offset of in string. if
---charpos and index is given, a new charpos will be calculated, by add/subtract
---UTF-8 char offset to current charpos. in all case, it return a new char
---position (in bytes), and code point (a number) at this position.
---@param s  string
---@param charpos? integer
---@param index? integer
---@return integer charpos
---@return integer codepoint
function utf8extra.next(s, charpos, index) end

---Insert a substring to s. If idx is given, insert substring before char at
---this index, otherwise substring will concat to s. idx can be negative.
---@param s string
---@param idx? integer
---@param substring string
---@return string new_string
function utf8extra.insert(s, idx, substring) end

---Delete a substring in s. If neither start nor stop is given, delete the last
---UTF-8 char in s, otherwise delete char from start to end of s. if stop is
---given, delete char from start to stop (include start and stop). start and
---stop can be negative.
---@param s string
---@param start? integer
---@param stop? integer
---@return string new_string
function utf8extra.remove(s, start, stop) end

---Calculate the width of UTF-8 string s. if ambi_is_double is given, the
---ambiguous width character's width is 2, otherwise it's 1. fullwidth/doublewidth
---character's width is 2, and other character's width is 1. if default_width is
---given, it will be the width of unprintable character, used display a
---non-character mark for these characters. if s is a code point, return the
---width of this code point.
---@param s string
---@param ambi_is_double? boolean
---@param default_width? integer
---@return integer width
function utf8extra.width(s, ambi_is_double, default_width) end

---Return the character index at given location in string s. this is a reverse
---operation of utf8.width(). this function returns a index of location, and a
---offset in UTF-8 encoding. e.g. if cursor is at the second column (middle)
---of the wide char, offset will be 2. the width of character at idx is
---returned, also.
---@param s string
---@param location integer
---@param ambi_is_double? boolean
---@param default_width? integer
---@return integer idx
---@return integer offset
---@return integer width
function utf8extra.widthindex(s, location, ambi_is_double, default_width) end

---Convert UTF-8 string s to title-case, used to compare by ignore case. if s
---is a number, it's treat as a code point and return a convert code point
---(number). utf8.lower/utf8.pper has the same extension.
---@param s string
---@return string new_string
function utf8extra.title(s) end

---Convert UTF-8 string s to folded case, used to compare by ignore case. if s
---is a number, it's treat as a code point and return a convert code point
---(number). utf8.lower/utf8.pper has the same extension.
---@param s string
---@return string new_string
function utf8extra.fold(s) end

---Compare a and b without case, -1 means a < b, 0 means a == b and 1 means a > b.
---@param a string
---@param b string
---@return integer result
function utf8extra.ncasecmp(a, b) end


return utf8extra
