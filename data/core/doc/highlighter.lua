local core = require "core"
local common = require "core.common"
local config = require "core.config"
local tokenizer = require "core.tokenizer"
local Object = require "core.object"

local considered_slow = 0.05
local max_line_len_when_slow = config.line_limit + 20

local Highlighter = Object:extend()


function Highlighter:new(doc)
  self.doc = doc
  self.lazy_mode = false
  self.last_line_edited = 0
  self.last_tokenize_time = {line = 0, time=0}
  self.incremental_running = false
  self:reset()

  -- init incremental syntax highlighting
  core.add_thread(function()
    while true do
      if self.first_invalid_line > self.max_wanted_line then
        self.max_wanted_line = 0
        coroutine.yield(1 / config.fps)

      else
        self.incremental_running = true
        local last_invalid = self.first_invalid_line
        local max = math.min(self.first_invalid_line + 40, self.max_wanted_line)

        local start_time = system.get_time();
        for i = self.first_invalid_line, max do
          local state = (i > 1) and self.lines[i - 1].state
          local line = self.lines[i]
          local line_len = #self.doc.lines[i]
          if not (
            line and line.init_state == state
            and
            line_len < 2 and line.text == self.doc.lines[i]
          )
          then
            local yield_tokenizer = self.lazy_mode
              and not line
              and line_len > max_line_len_when_slow
              and i ~= self.last_line_edited

            self.lines[i] = self:tokenize_line(i, state, yield_tokenizer)
            local end_time = system.get_time()
            local total_time = end_time - start_time

            if total_time >= considered_slow then
              core.redraw = true
              coroutine.yield()
              if max > #self.doc.lines then
                break
              elseif last_invalid ~= self.first_invalid_line then
                i = self.first_invalid_line - 1
                last_invalid = i + 1
              end
              start_time = system.get_time();
            else
              start_time = end_time
            end
          end
        end

        self.incremental_running = false
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
  self.last_line_edited = line
  self:invalidate(line)
  local blanks = { }
  for i = 1, n do
    blanks[i] = false
  end
  common.splice(self.lines, line, 0, blanks)
end

function Highlighter:remove_notify(line, n)
  self.last_line_edited = line
  self:invalidate(line)
  common.splice(self.lines, line, n)
end


function Highlighter:tokenize_line(idx, state, yield)
  local res = {}
  res.init_state = state
  res.text = self.doc.lines[idx]
  res.tokens, res.state = tokenizer.tokenize(self.doc.syntax, res.text, state, yield)
  return res
end


function Highlighter:get_line(idx, force)
  local line = self.lines[idx]
  if not line or line.text ~= self.doc.lines[idx] then
    local line_len = #self.doc.lines[idx]
    if
      line_len > 1 and ((force or not self.lazy_mode) or (
        -- edited a single line and tokenization time is fast even if long
        -- otherwise lazy tokenize to avoid typing lag
        (
          self.last_line_edited == idx
          and
          (
            self.last_tokenize_time.line ~= idx
            or
            self.last_tokenize_time.time < considered_slow
            or
            (self.incremental_running and self.first_invalid_line ~= idx)
          )
        )
        -- if the line is considered short should tokenize fast enough
        or
        (
          line_len <= max_line_len_when_slow
        )
      )
    )
    then
      local prev = self.lines[idx - 1]
      local start_time = system.get_time()
      line = self:tokenize_line(idx, prev and prev.state)
      local total_time = system.get_time() - start_time

      self.last_tokenize_time.line = idx
      self.last_tokenize_time.time = total_time

      if not self.lazy_mode and total_time >= considered_slow then
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
      if line_len > 1 then
        self:invalidate(idx)
      end
      self.max_wanted_line = math.max(self.max_wanted_line, idx)
    end
  end
  return line
end


function Highlighter:each_token(idx, force)
  return tokenizer.each_token(self:get_line(idx, force).tokens)
end


return Highlighter
