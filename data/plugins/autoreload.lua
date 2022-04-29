-- mod-version:2 -- lite-xl 2.0
local core = require "core"
local config = require "core.config"
local style = require "core.style"
local Doc = require "core.doc"
local common = require "core.common"
local dirwatch = require "core.dirwatch"

local times = setmetatable({}, { __mode = "k" })

local function update_time(doc)
  local info = system.get_file_info(doc.filename)
  times[doc] = info.modified
end

local function reload_doc(doc)
  doc:reload()
  update_time(doc)
  core.log_quiet("Auto-reloaded doc \"%s\"", doc.filename)
end

local function check_prompt_reload()
  if core.active_view.doc and core.active_view.doc.deferred_reload then
    local doc = core.active_view.doc
    core.nag_view:show("File Changed", doc.filename .. " has changed. Reload this file?", {
      { font = style.font, text = "Yes", default_yes = true },
      { font = style.font, text = "No" , default_no = true }
    }, function(item)
      if item.text == "Yes" then reload_doc(doc) end
      doc.deferred_reload = false
    end)
  end
end

local function check_if_modified(doc)
  local info = system.get_file_info(doc.filename or "")
  if info and times[doc] ~= info.modified then
    if not doc:is_dirty() then
      reload_doc(doc)
    else
      doc.deferred_reload = true
    end
  end
end

local on_check = dirwatch.check
function dirwatch:check(change_callback, ...)
  on_check(self, function(dir)
    for _, doc in ipairs(core.docs) do
      if dir == common.dirname(doc.abs_filename) then
        check_if_modified(doc)
      end
    end
    change_callback(dir)
  end, ...)
  check_prompt_reload()
end


local set_active_view = core.set_active_view
function core.set_active_view(view)
  set_active_view(view)
  check_prompt_reload()
  if view.doc and view.doc.abs_filename then
    local should_poll = true
    for i,v in ipairs(core.project_directories) do
      if view.doc.abs_filename:find(v.name, 1, true) == 1 and not v.files_limit then
        should_poll = false
      end
    end
    if should_poll then
      local doc = core.active_view.doc
      core.add_thread(function()
        while core.active_view.doc == doc do
          check_if_modified(doc)
          coroutine.yield(0.25)
        end
      end)
    end
  end
end

-- patch `Doc.save|load` to store modified time
local load = Doc.load
local save = Doc.save

Doc.load = function(self, ...)
  local res = load(self, ...)
  update_time(self)
  return res
end

Doc.save = function(self, ...)
  local res = save(self, ...)
  update_time(self)
  return res
end
