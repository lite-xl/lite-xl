-- mod-version:2 -- lite-xl 2.0
local core = require "core"
local config = require "core.config"
local style = require "core.style"
local Doc = require "core.doc"
local common = require "core.common"
local dirwatch = require "core.dirwatch"

config.plugins.autoreload = common.merge({
  always_show_nagview = false
}, config.plugins.autoreload)

local function get_project_doc(doc)
  for i, v in ipairs(core.project_directories) do
    if doc.abs_filename:find(v.abs_filename, 1, true) == 1 then return v end
  end
  return nil
end

local watch = dirwatch.new()
local times = setmetatable({}, { __mode = "k" })
local visible = setmetatable({}, { __mode = "k" })

local function update_time(doc)
  local info = system.get_file_info(doc.filename)
  times[doc] = info.modified
end

local function reload_doc(doc)
  doc:reload()
  update_time(doc)
  core.log_quiet("Auto-reloaded doc \"%s\"", doc.filename)
end

local function check_prompt_reload(doc)
  if doc or (core.active_view.doc and core.active_view.doc.deferred_reload) then
    doc = doc or core.active_view.doc
    core.nag_view:show("File Changed", doc.filename .. " has changed. Reload this file?", {
      { font = style.font, text = "Yes", default_yes = true },
      { font = style.font, text = "No" , default_no = true }
    }, function(item)
      if item.text == "Yes" then reload_doc(doc) end
      doc.deferred_reload = false
    end)
  end
end

local function doc_becomes_visible(doc)
  if doc and not visible[doc] and doc.abs_filename then
    visible[doc] = true
    check_prompt_reload(doc)
    local dir = get_project_doc(doc)
    (dir and dir.watch or watch):watch(doc.abs_filename)
  end
end

local function doc_becomes_invisible(doc)
  if doc and visible[doc] then
    visible[doc] = false
    local dir = get_project_doc(doc)
    (dir and dir.watch or watch):unwatch(doc.abs_filename)
  end
end

>>>>>>> Stashed changes
local function check_if_modified(doc)
  local info = system.get_file_info(doc.filename or "")
  if info and times[doc] ~= info.modified then
    if not doc:is_dirty() and not config.plugins.autoreload.always_show_nagview then
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
      if dir == common.dirname(doc.abs_filename) or dir == doc.abs_filename then
        check_if_modified(doc)
      end
    end
    change_callback(dir)
  end, ...)
  check_prompt_reload()
end

local core_set_active_view = core.set_active_view
function core.set_active_view(view)
  core_set_active_view(view)
  doc_becomes_visible(view.doc)
end

local node_set_active_view = Node.set_active_view
function Node:set_active_view(view)
  doc_becomes_invisible(self.active_view.doc)
  node_set_active_view(self, view)
  doc_becomes_visible(self.active_view.doc)
end

core.add_thread(function()
  while true do
    -- because we already hook this function above; we only
    -- need to check the file.
    watch:check(function() end)
    coroutine.yield(0.05)
  end
end)

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
