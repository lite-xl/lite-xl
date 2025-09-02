-- mod-version:4
local core = require "core"
local common = require "core.common"
local config = require "core.config"
local command = require "core.command"
local Doc = require "core.doc"

---@class config.plugins.trimwhitespace
---@field enabled boolean
---@field trim_empty_end_lines boolean
config.plugins.trimwhitespace = common.merge({
  enabled = false,
  trim_empty_end_lines = false,
  config_spec = {
    name = "Trim Whitespace",
    {
      label = "Enabled",
      description = "Disable or enable the trimming of white spaces by default.",
      path = "enabled",
      type = "toggle",
      default = false
    },
    {
      label = "Trim Empty End Lines",
      description = "Remove any empty new lines at the end of documents.",
      path = "trim_empty_end_lines",
      type = "toggle",
      default = false
    }
  }
}, config.plugins.trimwhitespace)

---@class plugins.trimwhitespace
local trimwhitespace = {}

---Disable whitespace trimming for a specific document.
---@param doc core.doc
function trimwhitespace.disable(doc)
  doc.disable_trim_whitespace = true
end

---Re-enable whitespace trimming if previously disabled.
---@param doc core.doc
function trimwhitespace.enable(doc)
  doc.disable_trim_whitespace = nil
end

---Perform whitespace trimming in all lines of a document except the
---line where the caret is currently positioned.
---@param doc core.doc
function trimwhitespace.trim(dv)
  local cline, ccol = dv:get_selection()
  for i = 1, #dv.doc.lines do
    local old_text = dv.doc:get_text(i, 1, i, math.huge)
    local new_text = old_text:gsub("%s*$", "")

    -- don't remove whitespace which would cause the caret to reposition
    if cline == i and ccol > #new_text then
      new_text = old_text:sub(1, ccol - 1)
    end

    if old_text ~= new_text then
      dv.doc:insert(i, 1, new_text)
      dv.doc:remove(i, #new_text + 1, i, math.huge)
    end
  end
end

---Removes all empty new lines at the end of the document.
---@param doc core.doc
---@param raw_remove? boolean Perform the removal not registering to undo stack
function trimwhitespace.trim_empty_end_lines(dv, raw_remove)
  for _=#dv.doc.lines, 1, -1 do
    local l = #dv.doc.lines
    if l > 1 and dv.doc.lines[l] == "\n" then
      local current_line = dv:get_selection()
      if current_line == l then
        dv:set_selection(l-1, math.huge, l-1, math.huge)
      end
      if not raw_remove then
        dv.doc:remove(l-1, math.huge, l, math.huge)
      else
        table.remove(dv.doc.lines, l)
      end
    else
      break
    end
  end
end


command.add("core.docview", {
  ["trim-whitespace:trim-trailing-whitespace"] = function(dv)
    trimwhitespace.trim(dv)
  end,

  ["trim-whitespace:trim-empty-end-lines"] = function(dv)
    trimwhitespace.trim_empty_end_lines(dv)
  end,
})


local doc_save = Doc.save
Doc.save = function(self, ...)
  if
    config.plugins.trimwhitespace.enabled
    and
    not self.disable_trim_whitespace
  then
    for _, view in ipairs(core.get_views_referencing_doc(self)) do
      trimwhitespace.trim(view)
      if config.plugins.trimwhitespace.trim_empty_end_lines then
        trimwhitespace.trim_empty_end_lines(view)
      end
      break
    end
  end
  doc_save(self, ...)
end


return trimwhitespace
