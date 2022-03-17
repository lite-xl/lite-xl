local core = require "core"
local common = require "core.common"
local config = require "core.config"
local tokenizer = require "core.tokenizer"
local Object = require "core.object"

local considered_slow = 0.05
local max_line_len_when_slow = 100

local Highlighter = Object:extend()


function Highlighter:new(doc)
  self.doc = doc
  -- mode activated on slow machines where tokenization is taking too long
  self.lazy_mode = false
  self:reset()

  -- init incremental syntax highlighting
  core.add_thread(function()
    while true do
      if self.first_invalid_line > self.max_wanted_line then
        self.max_wanted_line = 0
        coroutine.yield(1 / config.fps)

      else
        local max = math.min(self.first_invalid_line + 40, self.max_wanted_line)

        for i = self.first_invalid_line, max do
          local state = (i > 1) and self.lines[i - 1].state
          local line = self.lines[i]
          if not (line and line.init_state == state and line.text == self.doc.lines[i]) then
            local start_time = system.get_time();
            self.lines[i] = self:tokenize_line(i, state)
            local total_time = system.get_time() - start_time
            if total_time >= considered_slow then
              core.redraw = true
              coroutine.yield(0)
            end
          end
        end

        self.first_invalid_line = max + 1
        core.redraw = true
        coroutine.yield()
      end
    end
  end, self)
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
  self.max_wanted_line = math.min(self.max_wanted_line, #self.doc.lines)
end

function Highlighter:insert_notify(line, n)
  self:invalidate(line)
  local blanks = { }
  for i = 1, n do
    blanks[i] = false
  end
  common.splice(self.lines, line, 0, blanks)
end

function Highlighter:remove_notify(line, n)
  self:invalidate(line)
  common.splice(self.lines, line, n)
end


function Highlighter:tokenize_line(idx, state)
  local res = {}
  res.init_state = state
  res.text = self.doc.lines[idx]
  res.tokens, res.state = tokenizer.tokenize(self.doc.syntax, res.text, state)
  return res
end


function Highlighter:get_line(idx)
  local line = self.lines[idx]
  if not line or line.text ~= self.doc.lines[idx] then
    if not self.lazy_mode or (self.doc.lines[idx]:len() <= max_line_len_when_slow) then
      local prev = self.lines[idx - 1]
      local start_time = system.get_time();
      line = self:tokenize_line(idx, prev and prev.state)
      local total_time = system.get_time() - start_time
      if total_time >= considered_slow then
        self.lazy_mode = true
        core.log(
          "%s: slow tokenization detected, lazy mode activated",
          self.doc:get_name():match("[^/%\\]*$")
        )
      end
      self.lines[idx] = line
    else
      line = {
        tokens = {
          "normal",
          self.doc.lines[idx]
        }
      }
      self:invalidate(idx)
    end
  end
  self.max_wanted_line = math.max(self.max_wanted_line, idx)
  return line
end


function Highlighter:each_token(idx)
  return tokenizer.each_token(self:get_line(idx).tokens)
end


return Highlighter
