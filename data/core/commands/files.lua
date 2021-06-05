local core = require "core"
local command = require "core.command"

local function mkdirp(path)
  local segments = {}
  if path == '/' or path == '\\' then
    table.insert(segments, PATHSEP)
  end

  for m in string.gmatch("[^/\\]+") do
    table.insert(segments, m)
  end

  if #path > 1 and string.match(path, "^[/\\]") then
    segments[1] = PATHSEP .. segments[1]
  end

  for i = 1, #segments do
    local p = table.concat(segments, PATHSEP, 1, i)
    if not system.get_file_info(p) then
      local success, err = system.mkdir(p)
      if not success then
        core.error("cannot create directory %q: %s", p, err)
        break
      end
    end
  end
end

command.add(nil, {
  ["files:create-directory"] = function()
    core.command_view:enter("New directory name", function(text)
      mkdirp(text)
    end)
  end,
})
