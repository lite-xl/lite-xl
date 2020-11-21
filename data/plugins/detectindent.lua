local core = require "core"
local command = require "core.command"
local config = require "core.config"
local DocView = require "core.docview"
local Doc = require "core.doc"

local cache = setmetatable({}, { __mode = "k" })


local function add_to_stat(stat, val)
  for i = 1, #stat do
    if val == stat[i][1] then
      stat[i][2] = stat[i][2] + 1
      return
    end
  end
  stat[#stat + 1] = {val, 1}
end


local function optimal_indent_from_stat(stat)
  if #stat == 0 then return nil, 0 end
  local bins = {}
  for k = 1, #stat do
    local indent = stat[k][1]
    local score = 0
    local mult_prev, lines_prev
    for i = k, #stat do
      if stat[i][1] % indent == 0 then
        local mult = stat[i][1] / indent
        if not mult_prev or (mult_prev + 1 == mult and lines_prev / stat[i][2] > 0.1) then
          -- we add the number of lines to the score only if the previous
          -- multiple of "indent" was populated with enough lines.
          score = score + stat[i][2]
        end
        mult_prev, lines_prev = mult, stat[i][2]
      end
    end
    bins[#bins + 1] = {indent, score}
  end
  table.sort(bins, function(a, b) return a[2] > b[2] end)
  return bins[1][1], bins[1][2]
end

local auto_detect_max_lines = 400

local function detect_indent_stat(doc)
  local stat = {}
  local tab_count = 0
  for i, text in ipairs(doc.lines) do
    local str = text:match("^ %s+%S")
    if str then add_to_stat(stat, #str - 1) end
    local str = text:match("^\t+")
    if str then tab_count = tab_count + 1 end
    -- Stop parsing when files is very long. Not needed for euristic determination.
    if i > auto_detect_max_lines then break end
  end
  table.sort(stat, function(a, b) return a[1] < b[1] end)
  local indent, score = optimal_indent_from_stat(stat)
  if tab_count > score then
    core.log_quiet("Detect-indent: using tabs indentation")
    return "hard"
  elseif indent then
    core.log_quiet("Detect-indent: using indentation size of %d", indent)
    return "soft", indent
  end
end


local function update_cache(doc)
  local type, size = detect_indent_stat(doc)
  if type then
    cache[doc] = { type = type, size = size }
  end
end


local new = Doc.new
function Doc:new(...)
  new(self, ...)
  update_cache(self)
end

local clean = Doc.clean
function Doc:clean(...)
  clean(self, ...)
  update_cache(self)
end


local function with_indent_override(doc, fn, ...)
  local c = cache[doc]
  if not c then
    return fn(...)
  end
  local type, size = config.tab_type, config.indent_size
  config.tab_type, config.indent_size = c.type, c.size or config.indent_size
  local r1, r2, r3 = fn(...)
  config.tab_type, config.indent_size = type, size
  return r1, r2, r3
end


local perform = command.perform
function command.perform(...)
  return with_indent_override(core.active_view.doc, perform, ...)
end


local draw = DocView.draw
function DocView:draw(...)
  return with_indent_override(self.doc, draw, self, ...)
end

