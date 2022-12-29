-- So that in addition to regex.gsub(pattern, string), we can also do
-- pattern:gsub(string).
regex.__index = function(table, key) return regex[key]; end

---Looks for the first match of `pattern` in the string `str`.
---If it finds a match, it returns the indices of `str` where this occurrence
---starts and ends; otherwise, it returns `nil`.
---If the pattern has captures, the captured start and end indexes are returned,
---after the two initial ones.
---
---@param pattern string|table The regex pattern to use, either as a simple string or precompiled.
---@param str string The string to search for valid matches.
---@param offset? integer The position on the subject to start searching.
---@param options? integer A bit field of matching options, eg: regex.NOTBOL | regex.NOTEMPTY
---
---@return integer? start Offset where the first match was found; `nil` if no match.
---@return integer? end Offset where the first match ends; `nil` if no match.
---@return integer? ... #Captured matches offsets.
regex.find_offsets = function(pattern, str, offset, options)
  if type(pattern) ~= "table" then
    pattern = regex.compile(pattern)
  end
  local res = { regex.cmatch(pattern, str, offset or 1, options or 0) }
  -- Reduce every end delimiter by 1
  for i = 2,#res,2 do
    res[i] = res[i] - 1
  end
  return table.unpack(res)
end

---Behaves like `string.match`.
---Looks for the first match of `pattern` in the string `str`.
---If it finds a match, it returns the matched string; otherwise, it returns `nil`.
---If the pattern has captures, only the captured strings are returned.
---If a capture is empty, its offset is returned instead.
---
---@param pattern string|table The regex pattern to use, either as a simple string or precompiled.
---@param str string The string to search for valid matches.
---@param offset? integer The position on the subject to start searching.
---@param options? integer A bit field of matching options, eg: regex.NOTBOL | regex.NOTEMPTY
---
---@return (string|integer)? ... #List of captured matches; the entire match if no matches were specified; if the match is empty, its offset is returned instead.
regex.match = function(pattern, str, offset, options)
  local res = { regex.find(pattern, str, offset, options) }
  if #res == 0 then return end
  -- If available, only return captures
  if #res > 2 then return table.unpack(res, 3) end
  return string.sub(str, res[1], res[2])
end

---Behaves like `string.find`.
---Looks for the first match of `pattern` in the string `str`.
---If it finds a match, it returns the indices of `str` where this occurrence
---starts and ends; otherwise, it returns `nil`.
---If the pattern has captures, the captured strings are returned,
---after the two indexes ones.
---If a capture is empty, its offset is returned instead.
---
---@param pattern string|table The regex pattern to use, either as a simple string or precompiled.
---@param str string The string to search for valid matches.
---@param offset? integer The position on the subject to start searching.
---@param options? integer A bit field of matching options, eg: regex.NOTBOL | regex.NOTEMPTY
---
---@return integer? start Offset where the first match was found; `nil` if no match.
---@return integer? end Offset where the first match ends; `nil` if no match.
---@return (string|integer)? ... #List of captured matches; if the match is empty, its offset is returned instead.
regex.find = function(pattern, str, offset, options)
  local res = { regex.find_offsets(pattern, str, offset, options) }
  local out = { }
  if #res == 0 then return end
  out[1] = res[1]
  out[2] = res[2]
  for i = 3,#res,2 do
    if res[i] > res[i+1] then
      -- Like in string.find, if the group has size 0, return the index
      table.insert(out, res[i])
    else
      table.insert(out, string.sub(str, res[i], res[i+1]))
    end
  end
  return table.unpack(out)
end
