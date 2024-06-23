-- mod-version:3
local core = require "core"
local config = require "core.config"
local Doc = require "core.doc"
local Node = require "core.node"
local common = require "core.common"
local dirwatch = require "core.dirwatch"

config.plugins.autoreload = common.merge({
  always_show_nagview = false,
  config_spec = {
    name = "Autoreload",
    {
      label = "Always Show Nagview",
      description = "Alerts you if an opened file changes externally even if you haven't modified it.",
      path = "always_show_nagview",
      type = "toggle",
      default = false
    }
  }
}, config.plugins.autoreload)

local watch = dirwatch.new()
local times = setmetatable({}, { __mode = "k" })
local visible = setmetatable({}, { __mode = "k" })

local function get_project_doc_watch(doc)
  for _, v in ipairs(core.project_directories) do
    if doc.abs_filename:find(v.name, 1, true) == 1 then return v.watch end
  end
  return watch
end

local function update_time(doc)
  times[doc] = system.get_file_info(doc.filename).modified
end

local function reload_doc(doc)
  doc:reload()
  update_time(doc)
  core.redraw = true
  core.log_quiet("Auto-reloaded doc \"%s\"", doc.filename)
end


local timers = setmetatable({}, { __mode = "k" })

local function delayed_reload(doc, mtime)
  if timers[doc] then
    -- If mtime remains the same, there's no need to restart the timer
    -- as we're waiting a full second anyways.
    if not mtime or timers[doc].mtime ~= mtime then
      timers[doc] = { last_trigger = system.get_time(), mtime = mtime }
    end
    return
  end

  timers[doc] = { last_trigger = system.get_time(), mtime = mtime }
  core.add_thread(function()
    local diff = system.get_time() - timers[doc].last_trigger
    -- Wait a second before triggering a reload because we're using mtime
    -- to determine if a file has changed, and on many systems it has a
    -- resolution of 1 second.
    while diff < 1 do
      coroutine.yield(diff)
      diff = system.get_time() - timers[doc].last_trigger
    end
    timers[doc] = nil
    reload_doc(doc)
  end)
end

local function check_prompt_reload(doc)
  if doc and doc.deferred_reload then
    core.nag_view:show("File Changed", doc.filename .. " has changed. Reload this file?", {
      { text = "Yes", default_yes = true },
      { text = "No", default_no = true }
    }, function(item)
      if item.text == "Yes" then reload_doc(doc) end
      doc.deferred_reload = false
    end)
  end
end

local function doc_changes_visiblity(doc, visibility)
  if doc and visible[doc] ~= visibility and doc.abs_filename then
    visible[doc] = visibility
    if visibility then check_prompt_reload(doc) end
    get_project_doc_watch(doc):watch(doc.abs_filename, visibility)
  end
end

local on_check = dirwatch.check
function dirwatch:check(change_callback, ...)
  on_check(self, function(dir)
    for _, doc in ipairs(core.docs) do
      if doc.abs_filename and (dir == common.dirname(doc.abs_filename) or dir == doc.abs_filename) then
        local info = system.get_file_info(doc.filename or "")
        if info and info.type == "file" and times[doc] ~= info.modified then
          if not doc:is_dirty() and not config.plugins.autoreload.always_show_nagview then
            delayed_reload(doc, info.modified)
          else
            doc.deferred_reload = true
            if doc == core.active_view.doc then check_prompt_reload(doc) end
          end
        end
      end
    end
    change_callback(dir)
  end, ...)
end

local core_set_active_view = core.set_active_view
function core.set_active_view(view)
  core_set_active_view(view)
  doc_changes_visiblity(view.doc, true)
end

local node_set_active_view = Node.set_active_view
function Node:set_active_view(view)
  if self.active_view then doc_changes_visiblity(self.active_view.doc, false) end
  node_set_active_view(self, view)
  doc_changes_visiblity(self.active_view.doc, true)
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
  -- if starting with an unsaved document with a filename.
  if not times[self] then get_project_doc_watch(self):watch(self.abs_filename, true) end
  update_time(self)
  return res
end
