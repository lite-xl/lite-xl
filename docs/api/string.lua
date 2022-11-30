---@meta

---UTF-8 equivalent of string.byte
---@param s  string
---@param i? integer
---@param j? integer
---@return integer
---@return ...
function string.ubyte(s, i, j) end

---UTF-8 equivalent of string.char
---@param byte integer
---@param ... integer
---@return string
---@return ...
function string.uchar(byte, ...) end

---UTF-8 equivalent of string.find
---@param s       string
---@param pattern string
---@param init?   integer
---@param plain?  boolean
---@return integer start
---@return integer end
---@return ... captured
function string.ufind(s, pattern, init, plain) end

---UTF-8 equivalent of string.gmatch
---@param s       string
---@param pattern string
---@param init?   integer
---@return fun():string, ...
function string.ugmatch(s, pattern, init) end

---UTF-8 equivalent of string.gsub
---@param s       string
---@param pattern string
---@param repl    string|table|function
---@param n       integer
---@return string
---@return integer count
function string.ugsub(s, pattern, repl, n) end

---UTF-8 equivalent of string.len
---@param s string
---@return integer
function string.ulen(s) end

---UTF-8 equivalent of string.lower
---@param s string
---@return string
function string.ulower(s) end

---UTF-8 equivalent of string.match
---@param s       string
---@param pattern string
---@param init?   integer
---@return string | number captured
function string.umatch(s, pattern, init) end

---UTF-8 equivalent of string.reverse
---@param s string
---@return string
function string.ureverse(s) end

---UTF-8 equivalent of string.sub
---@param s  string
---@param i  integer
---@param j? integer
---@return string
function string.usub(s, i, j) end

---UTF-8 equivalent of string.upper
---@param s string
---@return string
function string.uupper(s) end

---Equivalent to utf8.escape()
---@param s  string
---@return string utf8_string
function string.uescape(s) end


---Equivalent to utf8.charpos()
---@param s  string
---@param charpos? integer
---@param index? integer
---@return integer charpos
---@return integer codepoint
function string.ucharpos(s, charpos, index) end

---Equivalent to utf8.next()
---@param s  string
---@param charpos? integer
---@param index? integer
---@return integer charpos
---@return integer codepoint
function string.unext(s, charpos, index) end

---Equivalent to utf8.insert()
---@param s string
---@param idx? integer
---@param substring string
---@return string new_string
function string.uinsert(s, idx, substring) end

---Equivalent to utf8.remove()
---@param s string
---@param start? integer
---@param stop? integer
---@return string new_string
function string.uremove(s, start, stop) end

---Equivalent to utf8.width()
---@param s string
---@param ambi_is_double? boolean
---@param default_width? integer
---@return integer width
function string.uwidth(s, ambi_is_double, default_width) end

---Equivalent to utf8.widthindex()
---@param s string
---@param location integer
---@param ambi_is_double? boolean
---@param default_width? integer
---@return integer idx
---@return integer offset
---@return integer width
function string.uwidthindex(s, location, ambi_is_double, default_width) end

---Equivalent to utf8.title()
---@param s string
---@return string new_string
function string.utitle(s) end

---Equivalent to utf8.fold()
---@param s string
---@return string new_string
function string.ufold(s) end

---Equivalent to utf8.ncasecmp()
---@param a string
---@param b string
---@return integer result
function string.uncasecmp(a, b) end

---Equivalent to utf8.offset()
---@param s string
---@param n integer
---@param i? integer
---@return integer position_in_bytes
function string.uoffset(s, n, i) end

---Equivalent to utf8.codepoint()
---@param s    string
---@param i?   integer
---@param j?   integer
---@return integer code
---@return ...
function string.ucodepoint(s, i, j) end

---Equivalent to utf8.codes()
---@param s string
---@return fun():integer, integer
function string.ucodes(s) end
