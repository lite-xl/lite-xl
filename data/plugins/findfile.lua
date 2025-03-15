-- mod-version:4

local core = require "core"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local keymap = require "core.keymap"

config.plugins.findfile = common.merge({
  file_limit = 20000,
  max_search_time = 2.0
}, config.plugins.findfile)


command.add(nil, {
  ["core:find-file"] = function()
    local files, complete = {}, false
    local k = core.add_thread(function()
      local start, total = system.get_time(), 0
      for i, project in ipairs(core.projects) do
        for project, item in project:files() do
          if complete or #files > config.plugins.findfile.file_limit then return end
          table.insert(files, i == 1 and item.filename:sub(#project.path + 2) or common.home_encode(item.filename))
          local diff = system.get_time() - start
          if diff > 2 / config.fps then
            total = total + diff
            if total > config.plugins.findfile.max_search_time then return end
            coroutine.yield(0.1)
            start = system.get_time()
          end
        end
      end
    end)
    coroutine.resume(core.threads[k].cr)
    core.command_view:enter("Open File From Project", {
      submit = function(text, item)
        text = item and item.text or text
        core.root_view:open_doc(core.open_doc(common.home_expand(text)))
        complete = true
      end,
      suggest = function(text)
        return common.fuzzy_match_with_recents(files, core.visited_files, text)
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
