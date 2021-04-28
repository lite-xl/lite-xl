
-- So that in addition to regex.gsub(pattern, string), we can also do 
-- pattern:gsub(string).
regex.__index = function(table, key) return regex[key]; end

regex.match = function(pattern_string, string)
  local pattern = type(pattern_string) == "userdata" and
    pattern_string or regex.compile(pattern_string)
  return regex.cmatch(pattern, string)
end

-- Build off matching. For now, only support basic replacements, but capture
-- groupings should be doable. We can even have custom group replacements and
-- transformations and stuff in lua.
regex.gsub = function(pattern_string, string, replacement)
  local pattern = type(pattern_string) == "userdata" and 
    pattern_string or regex.compile(pattern_string)
  local offset, result, str, indices = 0, "", string
  repeat
    str = str:sub(offset)
    indices = { regex.cmatch(pattern, str) }
    if #indices > 0 then
      result = result .. str:sub(offset, indices[1] - 1) .. replacement
      offset = indices[2]
    end
  until #indices == 0 or indices[1] == indices[2]
  return result .. str:sub(offset - 1)
end

