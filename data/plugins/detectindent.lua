-- mod-version:2 -- lite-xl 2.0
local core = require "core"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local DocView = require "core.docview"
local Doc = require "core.doc"
local tokenizer = require "core.tokenizer"

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


-- return nil if it is a comment or blank line or the initial part of the
-- line otherwise.
-- we don't need to have the whole line to detect indentation.
local function get_first_line_part(tokens)
  local i, n = 1, #tokens
  while i + 1 <= n do
    local ttype, ttext = tokens[i], tokens[i + 1]
    if ttype ~= "comment" and ttext:gsub("%s+", "") ~= "" then
      return ttext
    end
    i = i + 2
  end
end

local function get_non_empty_lines(syntax, lines)
  return coroutine.wrap(function()
    local tokens, state
    local i = 0
    for _, line in ipairs(lines) do
      tokens, state = tokenizer.tokenize(syntax, line, state)
      local line_start = get_first_line_part(tokens)
      if line_start then
        i = i + 1
        coroutine.yield(i, line_start)
      end
    end
  end)
end


local auto_detect_max_lines = 100

local function detect_indent_stat(doc)
  local stat = {}
  local tab_count = 0
  for i, text in get_non_empty_lines(doc.syntax, doc.lines) do
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
    return "hard", config.indent_size, tab_count
  else
    return "soft", indent or config.indent_size, score or 0
  end
end


local function update_cache(doc)
  local type, size, score = detect_indent_stat(doc)
  local score_threshold = 4
  if score < score_threshold then
    -- use default values
    type = config.tab_type
    size = config.indent_size
  end
  cache[doc] = { type = type, size = size, confirmed = (score >= score_threshold) }
  doc.indent_info = cache[doc]
end


local new = Doc.new
function Doc:new(...)
  new(self, ...)
  update_cache(self)
end

local clean = Doc.clean
function Doc:clean(...)
  clean(self, ...)
  if not cache[self].confirmed then
    update_cache(self)
  end
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


local function set_indent_type(doc, type)
  cache[doc] = {type = type,
                size = cache[doc].value or config.indent_size,
                confirmed = true}
  doc.indent_info = cache[doc]
end

local function set_indent_type_command()
  core.command_view:enter(
    "Specify indent style for this file",
    function(value) -- submit
      local doc = core.active_view.doc
      value = value:lower()
      set_indent_type(doc, value == "tabs" and "hard" or "soft")
    end,
    function(text) -- suggest
      return common.fuzzy_match({"tabs", "spaces"}, text)
    end,
    nil, -- cancel
    function(text) -- validate
      local t = text:lower()
      return t == "tabs" or t == "spaces"
    end
  )
end


local function set_indent_size(doc, size)
  cache[doc] = {type = cache[doc].type or config.tab_type,
                size = size,
                confirmed = true}
  doc.indent_info = cache[doc]
end

local function set_indent_size_command()
  core.command_view:enter(
    "Specify indent size for current file",
    function(value) -- submit
      local value = math.floor(tonumber(value))
      local doc = core.active_view.doc
      set_indent_size(doc, value)
    end,
    nil, -- suggest
    nil, -- cancel
    function(value) -- validate
      local value = tonumber(value)
      return value ~= nil and value >= 1
    end
  )
end


command.add("core.docview", {
  ["indent:set-file-indent-type"] = set_indent_type_command,
  ["indent:set-file-indent-size"] = set_indent_size_command
})


command.add(function()
    return core.active_view:is(DocView)
           and cache[core.active_view.doc]
           and cache[core.active_view.doc].type == "soft"
  end, {
  ["indent:switch-file-to-tabs-indentation"] = function() set_indent_type(core.active_view.doc, "hard") end
})


command.add(function()
    return core.active_view:is(DocView)
           and cache[core.active_view.doc]
           and cache[core.active_view.doc].type == "hard"
  end, {
  ["indent:switch-file-to-spaces-indentation"] = function() set_indent_type(core.active_view.doc, "soft") end
})
