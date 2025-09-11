-- mod-version:4
local core = require "core"
local config = require "core.config"
local style = require "core.style"
local Doc = require "core.doc"
local DocView = require "core.docview"
local common = require "core.common"
local tokenizer = require "core.tokenizer"
local Object = require "core.object"


local Highlighter = Object:extend()

config.plugins.highlighter = common.merge({
  lines_per_step = 40
}, config.plugins.highlighter)


function Highlighter:new(doc)
  self.doc = doc
  self.running = false
  self.lines = {}
  self.syntax = self.doc.syntax
  self.first_invalid_line = 1
  self.max_wanted_line = 0
  self.views = setmetatable({}, { __mode = "k" })
  table.insert(doc.listeners, self)
end

function Highlighter:reset()
  self.lines = {}
  self:start(1)
end

function Highlighter:on_doc_change(type, text, line1, col1, line2, col2)
  if type == "insert" or type == "remove" then self:start(math.min(line1, line2)) end
  if type == "reset" then self:reset() end
  self:step()
end


function Highlighter:tokenize_line(idx, state, resume)
  local res = { init_state = state, text = self.doc.lines[idx] or "" }
  res.tokens, res.state, res.resume = tokenizer.tokenize(self.doc.syntax, res.text, state, resume)
  return res
end

function Highlighter:step()
  if self.first_invalid_line <= self.max_wanted_line then
    local max = math.min(self.first_invalid_line + config.plugins.highlighter.lines_per_step, self.max_wanted_line)
    local first_changed_line, last_changed_line
    for i = self.first_invalid_line, max do
      local state = (i > 1) and self.lines[i - 1].state
      local line = self.lines[i]
      if line and line.resume and (line.init_state ~= state or line.text ~= self.doc.lines[i]) then
        -- Reset the progress if no longer valid
        line.resume = nil
      end
      if not (line and line.init_state == state and line.text == self.doc.lines[i] and not line.resume) then
        first_changed_line = first_changed_line or i
        last_changed_line = i
        self.lines[i] = self:tokenize_line(i, state, line and line.resume)
        if self.lines[i].resume then
          self.first_invalid_line = i
          goto yield
        end
      end
    end
    if last_changed_line then
      for view in pairs(self.views) do 
        view:invalidate_cache(first_changed_line, last_changed_line) 
      end
    end
    self.first_invalid_line = max + 1
    ::yield::
    core.redraw = true
  end
end

function Highlighter:start(first_invalid_line, max_wanted_line)
  if first_invalid_line then self.first_invalid_line = common.clamp(self.first_invalid_line, 1, first_invalid_line) end
  if max_wanted_line then self.max_wanted_line = common.clamp(self.max_wanted_line, #self.doc.lines, max_wanted_line) end

  self.running = self.running or core.add_thread(function()
    while self.first_invalid_line <= self.max_wanted_line do
      self:step()
      coroutine.yield(0)
    end
    self.max_wanted_line = 0
    self.running = nil
  end)
end


function Highlighter:get_line(idx)
  local line = self.lines[idx]
  local prev = self.lines[idx - 1]
  if not line or line.text ~= self.doc.lines[idx] or (prev and line.init_state ~= prev.state) then
    line = self:tokenize_line(idx, prev and prev.state)
    if self.lines[idx] and line.state ~= self.lines[idx].state then
      self:start(idx + 1, idx + config.plugins.highlighter.lines_per_step)
    end
    self.lines[idx] = line
  end
  self:start(nil, idx)
  return line
end

local function highlighter_each_token(tokens, i)
  i = i + 1
  if i * 2 > #tokens then return nil end
  return i, tokens[(i - 1) * 2 + 1], tokens[(i - 1) * 2 + 2]
end

function Highlighter:each_token(line)
  local state = self:get_line(line)
  return highlighter_each_token, state.tokens, 0
end

-- replaces all strings, and comments with whitespace
function Highlighter:get_syntaxful_line(line, force)
  local t = {}
  if not self.lines[line] and not force then return self.doc.lines[line] end
  for _, type, text in self:each_token(line) do
    table.insert(t, (type == "comment" or type == "string") and string.rep(" ", text:ulen()) or text)
  end
  return table.concat(t)
end


local old_tokenize = DocView.tokenize
function DocView:tokenize(line, visible)
  if not self.doc.highlighter then self.doc.highlighter = Highlighter(self.doc) end
  local highlighter = self.doc.highlighter
  if not highlighter.views[self] then highlighter.views[self] = true end

  local tokens = old_tokenize(self, line, visible)
  if #tokens == 0 or (not highlighter.lines[line] and line > 1 and not visible) then 
    return tokens 
  end
  local tokenized = highlighter:get_line(line)
  -- Walk through all doc tokens, and then map them onto what we've tokenized.
  local colorized = {}
  for idx, type, doc_line, start_offset, end_offset, token_style in self:each_token(tokens) do
    if type == "doc" then
      local offset = 1
      for i = 1, #tokenized.tokens, 2 do
        local type, text = tokenized.tokens[i], tokenized.tokens[i+1]
        local width = text:ulen() or #text
        if offset <= end_offset and offset + width >= start_offset then
          table.insert(colorized, "doc")
          table.insert(colorized, doc_line)
          table.insert(colorized, math.max(start_offset, offset))
          table.insert(colorized, math.min(end_offset, offset + width - 1))
          table.insert(colorized, common.merge(token_style, { color = style.syntax[type], font = style.syntax_fonts[type], type = type }))
        end
        if offset > end_offset then break end
        offset = offset + width
      end
    else
      table.move(tokens, idx - 5, idx - 1, #colorized + 1, colorized)
    end
  end
  return #colorized > 0 and colorized or { "doc", line, 1, 1, {} }
end

return Highlighter
