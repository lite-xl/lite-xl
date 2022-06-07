local core = require "core"
local common = require "core.common"
local command = require "core.command"
local keymap = require "core.keymap"
local LogView = require "core.logview"


local fullscreen = false
local restore_title_view = false

local function suggest_directory(text)
  text = common.home_expand(text)
  local basedir = common.dirname(core.project_dir)
  return common.home_encode_list((basedir and text == basedir .. PATHSEP or text == "") and
    core.recent_projects or common.dir_path_suggest(text))
end

local function check_directory_path(path)
    local abs_path = system.absolute_path(path)
    local info = abs_path and system.get_file_info(abs_path)
    if not info or info.type ~= 'dir' then
      return nil
    end
    return abs_path
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
    if fullscreen then
      restore_title_view = core.title_view.visible
    end
    system.set_window_mode(fullscreen and "fullscreen" or "normal")
    core.show_title_bar(not fullscreen and restore_title_view)
    core.title_view:configure_hit_test(not fullscreen and restore_title_view)
  end,

  ["core:reload-module"] = function()
    core.command_view:enter("Reload Module", {
      submit = function(text, item)
        local text = item and item.text or text
        core.reload_module(text)
        core.log("Reloaded module %q", text)
      end,
      suggest = function(text)
        local items = {}
        for name in pairs(package.loaded) do
          table.insert(items, name)
        end
        return common.fuzzy_match(items, text)
      end
    })
  end,

  ["core:find-command"] = function()
    local commands = command.get_all_valid()
    core.command_view:enter("Do Command", {
      submit = function(text, item)
        if item then
          command.perform(item.command)
        end
      end,
      suggest = function(text)
        local res = common.fuzzy_match(commands, text)
        for i, name in ipairs(res) do
          res[i] = {
            text = command.prettify_name(name),
            info = keymap.get_binding(name),
            command = name,
          }
        end
        return res
      end
    })
  end,

  ["core:find-file"] = function()
    if not core.project_files_number() then
       return command.perform "core:open-file"
    end
    local files = {}
    for dir, item in core.get_project_files() do
      if item.type == "file" then
        local path = (dir == core.project_dir and "" or dir .. PATHSEP)
        table.insert(files, common.home_encode(path .. item.filename))
      end
    end
    core.command_view:enter("Open File From Project", {
      submit = function(text, item)
        text = item and item.text or text
        core.root_view:open_doc(core.open_doc(common.home_expand(text)))
      end,
      suggest = function(text)
        return common.fuzzy_match_with_recents(files, core.visited_files, text)
      end
    })
  end,

  ["core:new-doc"] = function()
    core.root_view:open_doc(core.open_doc())
  end,

  ["core:new-named-doc"] = function()
    core.command_view:enter("File name", {
      submit = function(text)
        core.root_view:open_doc(core.open_doc(text))
      end
    })
  end,

  ["core:open-file"] = function()
    local view = core.active_view
    local text
    if view.doc and view.doc.abs_filename then
      local dirname, filename = view.doc.abs_filename:match("(.*)[/\\](.+)$")
      if dirname then
        dirname = core.normalize_to_project_dir(dirname)
        text = dirname == core.project_dir and "" or common.home_encode(dirname) .. PATHSEP
      end
    end
    core.command_view:enter("Open File", {
      text = text,
      submit = function(text)
        local filename = system.absolute_path(common.home_expand(text))
        core.root_view:open_doc(core.open_doc(filename))
      end,
      suggest = function (text)
          return common.home_encode_list(common.path_suggest(common.home_expand(text)))
        end,
      validate = function(text)
          local filename = common.home_expand(text)
          local path_stat, err = system.get_file_info(filename)
          if err then
            if err:find("No such file", 1, true) then
              -- check if the containing directory exists
              local dirname = common.dirname(filename)
              local dir_stat = dirname and system.get_file_info(dirname)
              if not dirname or (dir_stat and dir_stat.type == 'dir') then
                return true
              end
            end
            core.error("Cannot open file %s: %s", text, err)
          elseif path_stat.type == 'dir' then
            core.error("Cannot open %s, is a folder", text)
          else
            return true
          end
        end,
    })
  end,

  ["core:open-log"] = function()
    local node = core.root_view:get_active_node_default()
    node:add_view(LogView())
  end,

  ["core:open-user-module"] = function()
    local user_module_doc = core.open_doc(USERDIR .. "/init.lua")
    if not user_module_doc then return end
    core.root_view:open_doc(user_module_doc)
  end,

  ["core:open-project-module"] = function()
    if not system.get_file_info(".lite_project.lua") then
      core.try(core.write_init_project_module, ".lite_project.lua")
    end
    local doc = core.open_doc(".lite_project.lua")
    core.root_view:open_doc(doc)
    doc:save()
  end,

  ["core:change-project-folder"] = function()
    local dirname = common.dirname(core.project_dir)
    local text
    if dirname then
      text = common.home_encode(dirname) .. PATHSEP
    end
    core.command_view:enter("Change Project Folder", {
      text = text,
      submit = function(text)
        local path = common.home_expand(text)
        local abs_path = check_directory_path(path)
        if not abs_path then
          core.error("Cannot open directory %q", path)
          return
        end
        if abs_path == core.project_dir then return end
        core.confirm_close_docs(core.docs, function(dirpath)
          core.open_folder_project(dirpath)
        end, abs_path)
      end,
      suggest = suggest_directory
    })
  end,

  ["core:open-project-folder"] = function()
    local dirname = common.dirname(core.project_dir)
    local text
    if dirname then
      text = common.home_encode(dirname) .. PATHSEP
    end
    core.command_view:enter("Open Project", {
      text = text,
      submit = function(text)
        local path = common.home_expand(text)
        local abs_path = check_directory_path(path)
        if not abs_path then
          core.error("Cannot open directory %q", path)
          return
        end
        if abs_path == core.project_dir then
          core.error("Directory %q is currently opened", abs_path)
          return
        end
        system.exec(string.format("%q %q", EXEFILE, abs_path))
      end,
      suggest = suggest_directory
    })
  end,

  ["core:add-directory"] = function()
    core.command_view:enter("Add Directory", {
      submit = function(text)
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
      end,
      suggest = suggest_directory
    })
  end,

  ["core:remove-directory"] = function()
    local dir_list = {}
    local n = #core.project_directories
    for i = n, 2, -1 do
      dir_list[n - i + 1] = core.project_directories[i].name
    end
    core.command_view:enter("Remove Directory", {
      submit = function(text, item)
        text = common.home_expand(item and item.text or text)
        if not core.remove_project_directory(text) then
          core.error("No directory %q to be removed", text)
        end
      end,
      suggest = function(text)
        text = common.home_expand(text)
        return common.home_encode_list(common.dir_list_suggest(text, dir_list))
      end
    })
  end,
})
