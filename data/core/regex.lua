
-- So that in addition to regex.gsub(pattern, string), we can also do 
-- pattern:gsub(string).
regex.__index = function(table, key) return regex[key]; end

regex.match = function(pattern_string, string)
  local pattern = type(pattern_string) == "table" and
    pattern_string or regex.compile(pattern_string)
  return regex.cmatch(pattern, string)
end

-- Will iterate back through any UTF-8 bytes so that we don't replace bits 
-- mid character.
local function previous_character(str, index)
  local byte
  repeat
    index = index - 1
    byte = string.byte(str, index)
  until byte < 128 or byte >= 192
  return index
end

-- Moves to the end of the identified character.
local function end_character(str, index)
  local byte = string.byte(str, index + 1)
  while byte >= 128 and byte < 192 do
    index = index + 1
    byte = string.byte(str, index + 1)
  end
  return index
end

-- Build off matching. For now, only support basic replacements, but capture
-- groupings should be doable. We can even have custom group replacements and
-- transformations and stuff in lua. Currently, this takes group replacements 
-- as \1 - \9.
-- Should work on UTF-8 text.
regex.gsub = function(pattern_string, string, replacement)
  local pattern = type(pattern_string) == "table" and 
    pattern_string or regex.compile(pattern_string)
  local result, str, indices, n = "", string
  repeat
    indices = { regex.cmatch(pattern, str) }
    if #indices > 0 then
      n = n + 1
      local currentReplacement = replacement
      if #indices > 2 then
        for i = 1, (#indices/2 - 1) do
          currentReplacement = string.gsub(
            currentReplacement, 
            "\\" .. i, 
            str:sub(indices[i*2+1], end_character(str,indices[i*2+2]-1))
          )
        end
      end
      currentReplacement = string.gsub(currentReplacement, "\\%d", "")
      if indices[1] > 1 then
        result = result .. 
          str:sub(1, previous_character(str, indices[1])) .. currentReplacement
      else
        result = result .. currentReplacement      
      end
      str = str:sub(indices[2])
    end
  until #indices == 0 or indices[1] == indices[2]
  return result .. str, n
end

