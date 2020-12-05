local project_manager = {}

local core = require "core"
local command = require "core.command"
local common  = require "core.common"
local keymap  = require "core.keymap"

local projects_file = ".lite_projects.lua"

project_manager.projects = {}

local function load_projects()
  local ok, t = pcall(dofile, EXEDIR .. "/" .. projects_file)
  if ok then project_manager.projects = t end
end

load_projects()

local function serialize(val)
  if type(val) == "string" then
    return string.format("%q", val)
  elseif type(val) == "table" then
    local t = {}
    for k, v in pairs(val) do
      table.insert(t, "[" .. serialize(k) .. "]=" .. serialize(v))
    end
    return "{" .. table.concat(t, ",") .. "}"
  end
  return tostring(val)
end

local function save_projects()
  local fp = io.open(EXEDIR .. "/" .. projects_file, "w")
  if fp then
    fp:write("return ", serialize(project_manager.projects), "\n")
    fp:close()
  end
end

local function path_base_name(str)
  local pattern = "[\\/]?([^\\/]+)[\\/]?$"
  return str:match(pattern)
end

function project_manager.add_project()
  local proj_dir = system.absolute_path(".")
  local proj_name = path_base_name(proj_dir)
  core.command_view:set_text(proj_name)
  core.command_view:enter("Project Name",
    function(text)
      if text then
        project_manager.projects[text] = proj_dir
        save_projects()
      end
    end)
end

local function get_project_names()
  local t = {}
  for k, v in pairs(project_manager.projects) do table.insert(t, k) end
  return t
end

local function project_lister(func)
  local projects = get_project_names();
  core.command_view:enter("Open Project", func, function(text)
    local res = common.fuzzy_match(projects, text)
    for i, name in ipairs(res) do
      res[i] = {
        text = name,
        info = project_manager.projects[name],
      }
    end
    return res
  end)
end

function project_manager.rename_project(func)
  project_lister(function(text, item)
    if item then
      core.command_view:set_text(item.text)
      core.command_view:enter("Rename ".. item.text,
        function(_text)
          if _text then
            project_manager.projects[_text] = project_manager.projects[item.text]
            project_manager.projects[item.text] = nil
            save_projects()
          end
        end)
    end
  end)
end

function project_manager.open_project()
  project_lister(function(text, item)
    if item then
      system.exec(string.format("%q %q", EXEFILE, item.info))
    end
  end)
end

function project_manager.switch_project()
  project_lister(function(text, item)
    if item then
      if core.confirm_close_all() then
        core.root_view:close_all_docviews()
        core.switch_project = item.info
      end
    end
  end)
end

function project_manager.remove_project()
  project_lister(function(text, item)
    if item then
      project_manager.projects[item.text] = nil
      save_projects()
    end
  end)
end

command.add(nil, {
  ["project-manager:open-project"]   = project_manager.open_project,
  ["project-manager:switch-project"] = project_manager.switch_project,
  ["project-manager:add-project"]    = project_manager.add_project,
  ["project-manager:remove-project"] = project_manager.remove_project,
  ["project-manager:rename-project"] = project_manager.rename_project,
  })

return project_manager
