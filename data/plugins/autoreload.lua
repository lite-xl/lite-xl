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
  local fp = io.open(doc.filename, "r")
  local text = fp:read("*a")
  fp:close()

  local sel = { doc:get_selection() }
  doc:remove(1, 1, math.huge, math.huge)
  doc:insert(1, 1, text:gsub("\r", ""):gsub("\n$", ""))
  doc:set_selection(table.unpack(sel))

  update_time(doc)
  doc:clean()
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

local on_check = dirwatch.check
function dirwatch:check(change_callback, ...)
  on_check(self, function(dir)
    for _, doc in ipairs(core.docs) do
      if dir == common.dirname(doc.abs_filename) then
        local info = system.get_file_info(doc.filename or "")
        if info and times[doc] ~= info.modified then
          if not doc:is_dirty() then
            reload_doc(doc)
          else
            doc.deferred_reload = true
          end
          break
        end
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
