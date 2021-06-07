local core = require "core"
local command = require "core.command"

local function mkdirp(path)
  local segments = {}
  local pos = 1
  while true do
    local s, e = string.find(path, "[/\\]+", pos)
    if not s then break end
    table.insert(segments, string.sub(str, pos, s - 1))
    pos = e + 1
  end
  table.insert(segments, string.sub(str, pos))
  if segments[#segments] == '' then
    table.remove(segments)
  end

  for i = 1, #segments do
    local p = table.concat(segments, PATHSEP, 1, i)
    local stat = system.get_file_info(p)
    if stat and stat.type == "file" then
      return nil, "path exists", p
    end
    local success, err = system.mkdir(p)
    if not success then
      return nil, err, p
    end
  end
end

command.add(nil, {
  ["files:create-directory"] = function()
    core.command_view:enter("New directory name", function(text)
      local success, err, path = mkdirp(text)
      if not success then
        core.error("cannot create directory %q: %s", path, err)
      end
    end)
  end,
})
