local core = require "core"
local common = require "core.common"
local command = require "core.command"
local keymap = require "core.keymap"
local LogView = require "core.logview"


local fullscreen = false

local function suggest_directory(text)
  text = common.home_expand(text)
  return common.home_encode_list(text == "" and core.recent_projects or common.dir_path_suggest(text))
end

command.add(nil, {
  ["core:quit"] = function()
    core.quit()
  end,

  ["core:restart"] = function()
    core.restart()
  end,

  ["core:force-quit"] = function()
    core.quit(true)
  end,

  ["core:toggle-fullscreen"] = function()
    fullscreen = not fullscreen
    system.set_window_mode(fullscreen and "fullscreen" or "normal")
  end,

  ["core:reload-module"] = function()
    core.command_view:enter("Reload Module", function(text, item)
      local text = item and item.text or text
      core.reload_module(text)
      core.log("Reloaded module %q", text)
    end, function(text)
      local items = {}
      for name in pairs(package.loaded) do
        table.insert(items, name)
      end
      return common.fuzzy_match(items, text)
    end)
  end,

  ["core:find-command"] = function()
    local commands = command.get_all_valid()
    core.command_view:enter("Do Command", function(text, item)
      if item then
        command.perform(item.command)
      end
    end, function(text)
      local res = common.fuzzy_match(commands, text)
      for i, name in ipairs(res) do
        res[i] = {
          text = command.prettify_name(name),
          info = keymap.get_binding(name),
          command = name,
        }
      end
      return res
    end)
  end,

  ["core:find-file"] = function()
    local files = {}
    for dir, item in core.get_project_files() do
      if item.type == "file" then
        local path = (dir == core.project_dir and "" or dir .. PATHSEP)
        table.insert(files, common.home_encode(path .. item.filename))
      end
    end
    core.command_view:enter("Open File From Project", function(text, item)
      text = item and item.text or text
      core.root_view:open_doc(core.open_doc(common.home_expand(text)))
    end, function(text)
      return common.fuzzy_match_with_recents(files, core.visited_files, text)
    end)
  end,

  ["core:new-doc"] = function()
    core.root_view:open_doc(core.open_doc())
  end,

  ["core:open-file"] = function()
    core.command_view:enter("Open File", function(text)
      core.root_view:open_doc(core.open_doc(common.home_expand(text)))
    end, function (text)
      return common.home_encode_list(common.path_suggest(common.home_expand(text)))
    end)
  end,

  ["core:open-log"] = function()
    local node = core.root_view:get_active_node()
    node:add_view(LogView())
  end,

  ["core:open-user-module"] = function()
    local user_module_doc = core.open_doc(USERDIR .. "/init.lua")
    if not user_module_doc then return end
    core.root_view:open_doc(user_module_doc)
  end,

  ["core:open-project-module"] = function()
    local filename = ".lite_project.lua"
    if system.get_file_info(filename) then
      core.root_view:open_doc(core.open_doc(filename))
    else
      local doc = core.open_doc()
      core.root_view:open_doc(doc)
      doc:save(filename)
    end
  end,

  ["core:change-project-folder"] = function()
    core.command_view:enter("Change Project Folder", function(text, item)
      text = system.absolute_path(common.home_expand(item and item.text or text))
      if text == core.project_dir then return end
      local path_stat = system.get_file_info(text)
      if not path_stat or path_stat.type ~= 'dir' then
        core.error("Cannot open folder %q", text)
        return
      end
      if core.confirm_close_all() then
        core.open_folder_project(text)
      end
    end, suggest_directory)
  end,

  ["core:open-project-folder"] = function()
    core.command_view:enter("Open Project", function(text, item)
      text = common.home_expand(item and item.text or text)
      local path_stat = system.get_file_info(text)
      if not path_stat or path_stat.type ~= 'dir' then
        core.error("Cannot open folder %q", text)
        return
      end
      system.exec(string.format("%q %q", EXEFILE, text))
    end, suggest_directory)
  end,

  ["core:add-directory"] = function()
    core.command_view:enter("Add Directory", function(text)
      text = common.home_expand(text)
      local path_stat, err = system.get_file_info(text)
      if not path_stat then
        core.error("cannot open %q: %s", text, err)
        return
      elseif path_stat.type ~= 'dir' then
        core.error("%q is not a directory", text)
        return
      end
      core.add_project_directory(system.absolute_path(text))
      -- TODO: add the name of directory to prioritize
      core.reschedule_project_scan()
    end, suggest_directory)
  end,

  ["core:remove-directory"] = function()
    local dir_list = {}
    local n = #core.project_directories
    for i = n, 2, -1 do
      dir_list[n - i + 1] = core.project_directories[i].name
    end
    core.command_view:enter("Remove Directory", function(text, item)
      text = common.home_expand(item and item.text or text)
      if not core.remove_project_directory(text) then
        core.error("No directory %q to be removed", text)
      end
    end, function(text)
      text = common.home_expand(text)
      return common.home_encode_list(common.dir_list_suggest(text, dir_list))
    end)
  end,
})
