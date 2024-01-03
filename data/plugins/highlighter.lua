-- mod-version:3
local core = require "core"
local config = require "core.config"
local style = require "core.style"
local DocView = require "core.docview"
local common = require "core.common"
local tokenizer = require "core.tokenizer"
local Object = require "core.object"


local Highlighter = Object:extend()

function Highlighter:new(doc)
  self.doc = doc
  self.running = false
  self:reset()
end


-- init incremental syntax highlighting
function Highlighter:start()
  if self.running then return end
  self.running = true
  core.add_thread(function()
    while self.first_invalid_line <= self.max_wanted_line do
      local max = math.min(self.first_invalid_line + 40, self.max_wanted_line)
      local retokenized_from
      for i = self.first_invalid_line, max do
        local state = (i > 1) and self.lines[i - 1].state
        local line = self.lines[i]
        if line and line.resume and (line.init_state ~= state or line.text ~= self.doc.lines[i]) then
          -- Reset the progress if no longer valid
          line.resume = nil
        end
        if not (line and line.init_state == state and line.text == self.doc.lines[i] and not line.resume) then
          retokenized_from = retokenized_from or i
          self.lines[i] = self:tokenize_line(i, state, line and line.resume)
          if self.lines[i].resume then
            self.first_invalid_line = i
            goto yield
          end
        elseif retokenized_from then
          retokenized_from = nil
        end
      end

      ::yield::
      self.first_invalid_line = max + 1
      core.redraw = true
      coroutine.yield(0)
    end
    self.max_wanted_line = 0
    self.running = false
  end, self)
end

local function set_max_wanted_lines(self, amount)
  self.max_wanted_line = amount
  if self.first_invalid_line <= self.max_wanted_line then
    self:start()
  end
end


function Highlighter:reset()
  self.lines = {}
  self:soft_reset()
end


function Highlighter:soft_reset()
  for i=1,#self.lines do
    self.lines[i] = false
  end
  self.first_invalid_line = 1
  self.max_wanted_line = 0
end


function Highlighter:invalidate(idx)
  self.first_invalid_line = math.min(self.first_invalid_line, idx)
  set_max_wanted_lines(self, math.min(self.max_wanted_line, #self.doc.lines))
end


function Highlighter:tokenize_line(idx, state, resume)
  local res = {}
  res.init_state = state
  res.text = self.doc.lines[idx]
  res.tokens, res.state, res.resume = tokenizer.tokenize(self.doc.syntax, res.text, state, resume)
  return res
end


function Highlighter:get_line(idx)
  local line = self.lines[idx]
  if not line or line.text ~= self.doc.lines[idx] then
    local prev = self.lines[idx - 1]
    line = self:tokenize_line(idx, prev and prev.state)
    self.lines[idx] = line
  end
  set_max_wanted_lines(self, math.max(self.max_wanted_line, idx))
  return line
end


local function get_tokens(highlighted_tokens, doc_line, start_offset, end_offset, token_style)
  local tokens = {}
  local offset = 1
  for i = 1, #highlighted_tokens, 2 do
    local type, text = highlighted_tokens[i], highlighted_tokens[i+1]
    if offset <= end_offset and offset + #text >= start_offset then
      table.insert(tokens, "doc")
      table.insert(tokens, doc_line)
      table.insert(tokens, math.max(start_offset, offset))
      table.insert(tokens, math.min(end_offset, offset + #text - 1))
      table.insert(tokens, common.merge(token_style, { color = style.syntax[type], font = style.syntax_fonts[type] }))
    end
    if offset > end_offset then break end
    offset = offset + #text
  end
  return tokens
end

local old_tokenize = DocView.tokenize
function DocView:tokenize(line)
  if not self.doc.highighter then self.doc.highlighter = Highlighter(self.doc) end

  local tokens = old_tokenize(self, line)
  if #tokens == 0 then return tokens end
  local highlighted_tokens = self.doc.highlighter:get_line(line).tokens
  -- Walk through all doc tokens, and then map them onto what we've tokenized.
  local colorized = {}
  local start_offset = 1
  local start_highlighted = 1
  for i = 1, #tokens, 5 do
    if tokens[i] == "doc" then
      local t = get_tokens(highlighted_tokens, tokens[i+1], tokens[i+2], tokens[i+3], tokens[i+4])
      table.move(t, 1, #t, #colorized + 1, colorized)
    else
      table.move(tokens, i, i + 4, #colorized + 1, colorized)
    end
  end
  return #colorized > 0 and colorized or { "doc", line, 1, 1, {} }
end

return Highlighter
