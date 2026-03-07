-- mod-version:4

local core = require "core"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local keymap = require "core.keymap"

config.plugins.findfile = common.merge({
  -- how many files from the project we store in a list before we stop
  file_limit = 20000,
  -- the maximum amount of time we spend gathering files before stopping
  max_search_time = 10.0,
  -- the amount of time we wait between loops of gathering files
  interval = 0,
  -- the amount of time we spend in a single loop (by default, half a frame)
  max_loop_time = 0.5 / config.fps
}, config.plugins.findfile)


command.add(nil, {
  ["core:find-file"] = function(root_view)
    local files, complete = {}, false
    local refresh = coroutine.wrap(function()
      local start, total = system.get_time(), 0
      for i, project in ipairs(core.projects) do
        for project, item in project:files() do
          if complete then return end
          if #files > config.plugins.findfile.file_limit then 
            root_view.command_view:update_suggestions() 
            return 
          end
          table.insert(files, i == 1 and item.filename:sub(#project.path + 2) or common.home_encode(item.filename))
          local diff = system.get_time() - start
          if diff > config.plugins.findfile.max_loop_time then
            root_view.command_view:update_suggestions()
            total = total + diff
            if total > config.plugins.findfile.max_search_time then return end
            coroutine.yield(config.plugins.findfile.interval)
            start = system.get_time()
          end
        end
      end
    end)
    local wait = refresh()
    if wait then
      core.add_thread(function()
        while wait do
          wait = refresh()
          coroutine.yield(wait)
        end
      end)
    end
    local original_files
    root_view.command_view:enter("Open File From Project", {
      submit = function(text, item)
        text = item and item.text or text
        root_view:open_doc(core.open_doc(common.home_expand(text)))
        complete = true
      end,
      suggest = function(text)
        if original_files and text == "" then 
          return original_files
        end
        original_files = common.fuzzy_match_with_recents(files, core.visited_files, text)
        return original_files
      end,
      cancel = function()
        complete = true
      end
    })
  end
})

keymap.add({
  [PLATFORM == "Mac OS X" and "cmd+p" or "ctrl+p"] = "core:find-file"
})
