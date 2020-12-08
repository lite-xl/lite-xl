local project_manager = {}

local core = require "core"
local command = require "core.command"
local common  = require "core.common"
local keymap  = require "core.keymap"

local recent_projects_file = "recent_projects.lua"

project_manager.recents = {}

local function load_projects()
  local ok, t = pcall(dofile, USERDIR .. "/" .. recent_projects_file)
  if ok then project_manager.recents = t end
end

load_projects()

local function serialize(val)
  local ls = {"{"}
  for i = 1, #val do
    ls[#ls + 1] = "  " .. string.format("%q", val[i]) .. ","
  end
  ls[#ls + 1] = "}"
  return table.concat(ls, "\n")
end

local function save_projects()
  local fp = io.open(USERDIR .. "/" .. recent_projects_file, "w")
  if fp then
    fp:write("return ", serialize(project_manager.recents), "\n")
    fp:close()
  end
end

local function path_base_name(str)
  local pattern = "[\\/]?([^\\/]+)[\\/]?$"
  return str:match(pattern)
end

function project_manager.open_folder()
  core.command_view:enter("Open Folder", function(text)
    local path_stat = system.get_file_info(text)
    if not path_stat or path_stat.type ~= 'dir' then
      core.error("Cannot open folder %q", text)
      return
    end
    if core.confirm_close_all() then
      core.root_view:close_all_docviews()
      table.insert(project_manager.recents, text)
      save_projects()
      core.switch_project = text
    end
  end, function(text)
    return text == "" and project_manager.recents or common.dir_path_suggest(text)
  end)
end

command.add(nil, {
  ["project-manager:open-folder"]    = project_manager.open_folder,
})

keymap.add { ["ctrl+shift+o"] = "project-manager:open-folder" }

return project_manager
