-- So that in addition to regex.gsub(pattern, string), we can also do
-- pattern:gsub(string).
regex.__index = function(table, key) return regex[key]; end

regex.match = function(pattern_string, string, offset, options)
  local pattern = type(pattern_string) == "table" and
    pattern_string or regex.compile(pattern_string)
  local res = { regex.cmatch(pattern, string, offset or 1, options or 0) }
  res[2] = res[2] and res[2] - 1
  return table.unpack(res)
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
  while byte and byte >= 128 and byte < 192 do
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
regex.gsub = function(pattern_string, str, replacement)
  local pattern = type(pattern_string) == "table" and
    pattern_string or regex.compile(pattern_string)
  local result, indices = ""
  local matches, replacements = {}, {}
  repeat
    indices = { regex.cmatch(pattern, str) }
    if #indices > 0 then
      table.insert(matches, indices)
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
      table.insert(replacements, { indices[1], #currentReplacement+indices[1] })
      if indices[1] > 1 then
        result = result ..
          str:sub(1, previous_character(str, indices[1])) .. currentReplacement
      else
        result = result .. currentReplacement
      end
      str = str:sub(indices[2])
    end
  until #indices == 0 or indices[1] == indices[2]
  return result .. str, matches, replacements
end

