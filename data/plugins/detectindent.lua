-- mod-version:3
local core = require "core"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local core_syntax = require "core.syntax"
local DocView = require "core.docview"
local Doc = require "core.doc"

local cache = setmetatable({}, { __mode = "k" })
local comments_cache = {}
local auto_detect_max_lines = 150


local function indent_occurrences_more_than_once(stat, idx)
  if stat[idx-1] and stat[idx-1] == stat[idx] then
    return true
  elseif stat[idx+1] and stat[idx+1] == stat[idx] then
    return true
  end
  return false
end


local function optimal_indent_from_stat(stat)
  if #stat == 0 then return nil, 0 end
  table.sort(stat, function(a, b) return a > b end)
  local best_indent = 0
  local best_score = 0
  local count = #stat
  for x=1, count do
    local indent = stat[x]
    local score = 0
    for y=1, count do
      if y ~= x and stat[y] % indent == 0 then
        score = score + 1
      elseif
        indent > stat[y]
        and
        indent_occurrences_more_than_once(stat, y)
      then
        score = 0
        break
      end
    end
    if score > best_score then
      best_indent = indent
      best_score = score
    end
    if score > 0 then
      break
    end
  end
  return best_score > 0 and best_indent or nil, best_score
end


local function escape_comment_tokens(token)
  local special_chars = "*-%[].()+?^$"
  local escaped = ""
  for x=1, token:len() do
    local found = false
    for y=1, special_chars:len() do
      if token:sub(x, x) == special_chars:sub(y, y) then
        escaped = escaped .. "%" .. token:sub(x, x)
        found = true
        break
      end
    end
    if not found then
      escaped = escaped .. token:sub(x, x)
    end
  end
  return escaped
end


local function get_comment_patterns(syntax, _loop)
  _loop = _loop or 1
  if _loop > 5 then return end
  if comments_cache[syntax] then
    if #comments_cache[syntax] > 0 then
      return comments_cache[syntax]
    else
      return nil
    end
  end
  local comments = {}
  for idx=1, #syntax.patterns do
    local pattern = syntax.patterns[idx]
    local startp = ""
    if
      type(pattern.type) == "string"
      and
      (pattern.type == "comment" or pattern.type == "string")
    then
      local not_is_string = pattern.type ~= "string"
      if pattern.pattern then
        startp = type(pattern.pattern) == "table"
          and pattern.pattern[1] or pattern.pattern
        if not_is_string and startp:sub(1, 1) ~= "^" then
          startp = "^%s*" .. startp
        elseif not_is_string then
          startp = "^%s*" .. startp:sub(2, startp:len())
        end
        if type(pattern.pattern) == "table" then
          table.insert(comments, {"p", startp, pattern.pattern[2]})
        elseif not_is_string then
          table.insert(comments, {"p", startp})
        end
      elseif pattern.regex then
        startp = type(pattern.regex) == "table"
          and pattern.regex[1] or pattern.regex
        if not_is_string and startp:sub(1, 1) ~= "^" then
          startp = "^\\s*" .. startp
        elseif not_is_string then
          startp = "^\\s*" .. startp:sub(2, startp:len())
        end
        if type(pattern.regex) == "table" then
          table.insert(comments, {
            "r", regex.compile(startp), regex.compile(pattern.regex[2])
          })
        elseif not_is_string then
          table.insert(comments, {"r", regex.compile(startp)})
        end
      end
    elseif pattern.syntax then
      local subsyntax = type(pattern.syntax) == 'table' and pattern.syntax
        or core_syntax.get("file"..pattern.syntax, "")
      local sub_comments = get_comment_patterns(subsyntax, _loop + 1)
      if sub_comments then
        for s=1, #sub_comments do
          table.insert(comments, sub_comments[s])
        end
      end
    end
  end
  if #comments == 0 then
    local single_line_comment = syntax.comment
      and escape_comment_tokens(syntax.comment) or nil
    local block_comment = nil
    if syntax.block_comment then
      block_comment = {
        escape_comment_tokens(syntax.block_comment[1]),
        escape_comment_tokens(syntax.block_comment[2])
      }
    end
    if single_line_comment then
      table.insert(comments, {"p", "^%s*" .. single_line_comment})
    end
    if block_comment then
      table.insert(comments, {"p", "^%s*" .. block_comment[1], block_comment[2]})
    end
  end
  comments_cache[syntax] = comments
  if #comments > 0 then
    return comments
  end
  return nil
end


local function get_non_empty_lines(syntax, lines)
  return coroutine.wrap(function()
    local comments = get_comment_patterns(syntax)

    local i = 0
    local end_regex = nil
    local end_pattern = nil
    local inside_comment = false
    for _, line in ipairs(lines) do
      if line:gsub("^%s+", "") ~= "" then
        local is_comment = false
        if comments then
          if not inside_comment then
            for c=1, #comments do
              local comment = comments[c]
              if comment[1] == "p" then
                if comment[3] then
                  local start, ending = line:find(comment[2])
                  if start then
                    if not line:find(comment[3], ending+1) then
                      is_comment = true
                      inside_comment = true
                      end_pattern = comment[3]
                    end
                    break
                  end
                elseif line:find(comment[2]) then
                  is_comment = true
                  break
                end
              else
                if comment[3] then
                  local start, ending = regex.find_offsets(
                    comment[2], line, 1, regex.ANCHORED
                  )
                  if start then
                    if not regex.find_offsets(
                        comment[3], line, ending+1, regex.ANCHORED
                      )
                    then
                      is_comment = true
                      inside_comment = true
                      end_regex = comment[3]
                    end
                    break
                  end
                elseif regex.find_offsets(comment[2], line, 1, regex.ANCHORED) then
                  is_comment = true
                  break
                end
              end
            end
          elseif end_pattern and line:find(end_pattern) then
            is_comment = true
            inside_comment = false
            end_pattern = nil
          elseif end_regex and regex.find_offsets(end_regex, line) then
            is_comment = true
            inside_comment = false
            end_regex = nil
          end
        end
        if
          not is_comment
          and
          not inside_comment
        then
          i = i + 1
          coroutine.yield(i, line)
        end
      end
    end
  end)
end


local function detect_indent_stat(doc)
  local stat = {}
  local tab_count = 0
  local runs = 1
  local max_lines = auto_detect_max_lines
  for i, text in get_non_empty_lines(doc.syntax, doc.lines) do
    local spaces = text:match("^ +")
    if spaces and #spaces > 1 then table.insert(stat, #spaces) end
    local tabs = text:match("^\t+")
    if tabs then tab_count = tab_count + 1 end
    -- if nothing found for first lines try at least 4 more times
    if i == max_lines and runs < 5 and #stat == 0 and tab_count == 0 then
      max_lines = max_lines + auto_detect_max_lines
      runs = runs + 1
    -- Stop parsing when files is very long. Not needed for euristic determination.
    elseif i > max_lines then break end
  end
  local indent, score = optimal_indent_from_stat(stat)
  if tab_count > score then
    return "hard", config.indent_size, tab_count
  else
    return "soft", indent or config.indent_size, score or 0
  end
end


local function update_cache(doc)
  local type, size, score = detect_indent_stat(doc)
  local score_threshold = 2
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
  local _, _, confirmed = self:get_indent_info()
  if not confirmed then
    update_cache(self)
  end
end


local function set_indent_type(doc, type)
  local _, indent_size = doc:get_indent_info()
  cache[doc] = {
    type = type,
    size = indent_size,
    confirmed = true
  }
  doc.indent_info = cache[doc]
end

local function set_indent_type_command(dv)
  core.command_view:enter("Specify indent style for this file", {
    submit = function(value)
      local doc = dv.doc
      value = value:lower()
      set_indent_type(doc, value == "tabs" and "hard" or "soft")
    end,
    suggest = function(text)
      return common.fuzzy_match({"tabs", "spaces"}, text)
    end,
    validate = function(text)
      local t = text:lower()
      return t == "tabs" or t == "spaces"
    end
  })
end


local function set_indent_size(doc, size)
  local indent_type = doc:get_indent_info()
  cache[doc] = {
    type = indent_type,
    size = size,
    confirmed = true
  }
  doc.indent_info = cache[doc]
end

local function set_indent_size_command(dv)
  core.command_view:enter("Specify indent size for current file", {
    submit = function(value)
      value = math.floor(tonumber(value))
      local doc = dv.doc
      set_indent_size(doc, value)
    end,
    validate = function(value)
      value = tonumber(value)
      return value ~= nil and value >= 1
    end
  })
end


command.add("core.docview", {
  ["indent:set-file-indent-type"] = set_indent_type_command,
  ["indent:set-file-indent-size"] = set_indent_size_command
})

command.add(
  function()
    return core.active_view:is(DocView)
      and cache[core.active_view.doc]
      and cache[core.active_view.doc].type == "soft"
  end, {
  ["indent:switch-file-to-tabs-indentation"] = function()
    set_indent_type(core.active_view.doc, "hard")
  end
})

command.add(
  function()
    return core.active_view:is(DocView)
      and cache[core.active_view.doc]
      and cache[core.active_view.doc].type == "hard"
  end, {
  ["indent:switch-file-to-spaces-indentation"] = function()
    set_indent_type(core.active_view.doc, "soft")
  end
})
