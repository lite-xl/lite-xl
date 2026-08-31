local core = require "core"
local common = require "core.common"
local config = require "core.config"
local tokenizer = require "core.tokenizer"
local Object = require "core.object"


local Highlighter = Object:extend()

function Highlighter:__tostring() return "Highlighter" end

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
      if self:thread_enabled() then
        self:thread_step()
      else
        if self.job then self:drop_job() end   -- left thread mode; abandon its job
        self:sync_step()
      end
      core.redraw = true
      coroutine.yield(0)
    end
    self.max_wanted_line = 0
    self.running = false
    self:thread_stop()
  end, self)
end

-- one batch of the main-thread tokenizer: retokenize up to 40 lines from
-- first_invalid_line, honouring the per-line `resume` checkpoint.
function Highlighter:sync_step()
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
      self:update_notify(retokenized_from, i - retokenized_from - 1)
      retokenized_from = nil
    end
  end

  self.first_invalid_line = max + 1
  ::yield::
  if retokenized_from then
    self:update_notify(retokenized_from, max - retokenized_from)
  end
end

-- Background-thread path (C core only, config.tokenizer_thread). A worker
-- tokenizes a sliding window of lines off the main thread; each step here
-- submits/extends the window, drains whatever the worker has finished into
-- self.lines, and walks first_invalid_line over the now-valid prefix.
local THREAD_WINDOW = 4000

function Highlighter:thread_enabled()
  return config.tokenizer_thread and tokenizer.thread_submit
     and not self.thread_unsupported
     and self.doc.syntax and #self.doc.syntax.patterns > 0
end

function Highlighter:thread_stop()
  if self.job then
    tokenizer.thread_cancel(self.job.id)
    self.job = nil
    if tokenizer.thread_poll then tokenizer.thread_poll() end   -- run the reap pass
  end
end

function Highlighter:thread_step()
  local first = self.first_invalid_line
  local last = math.min(first + THREAD_WINDOW, #self.doc.lines)
  if last < first then return end

  local job = self.job
  if not (job and job.first <= first and first <= job.last) then
    if job then tokenizer.thread_cancel(job.id) end
    local prev = self.lines[first - 1]
    local start_state = (first > 1) and prev and prev.state or "\0"
    local id = tokenizer.thread_submit(self.doc.syntax, self.doc.lines,
                                       first, last, start_state)
    if not id then
      self.thread_unsupported = true          -- C core can't model this syntax
      self.job = nil
      return
    end
    self.job = { id = id, first = first, last = last }
  end

  local batch = tokenizer.thread_poll(self.job.id)
  if batch then
    for _, jb in ipairs(batch) do
      for off, rec in ipairs(jb.lines) do
        local idx = jb.first_line + off - 1
        if idx >= self.first_invalid_line and idx <= #self.doc.lines then
          if rec.ok and rec.tokens then
            local prev = self.lines[idx - 1]
            self.lines[idx] = {
              init_state = (idx > 1) and prev and prev.state or false,
              text = self.doc.lines[idx],
              tokens = rec.tokens,
              state = rec.state,
            }
          elseif rec.ok == false and idx == self.first_invalid_line then
            -- C declined this line: finish it (and its state) in Lua and force
            -- a fresh window from the next line
            local prev = self.lines[idx - 1]
            self.lines[idx] = self:tokenize_line(idx, (idx > 1) and prev and prev.state)
            self.job = nil
          end
        end
      end
    end
  end

  local i = self.first_invalid_line
  local top = math.min(self.max_wanted_line, #self.doc.lines)
  while i <= top do
    local ln, prev = self.lines[i], self.lines[i - 1]
    local pstate = (i > 1) and prev and prev.state or false
    if ln and ln.text == self.doc.lines[i] and ln.init_state == pstate
       and ln.tokens and not ln.resume then
      i = i + 1
    else
      break
    end
  end
  if i > self.first_invalid_line then
    self:update_notify(self.first_invalid_line, i - self.first_invalid_line - 1)
    self.first_invalid_line = i
  end
end

local function set_max_wanted_lines(self, amount)
  self.max_wanted_line = amount
  if self.first_invalid_line <= self.max_wanted_line then
    self:start()
  end
end


-- drop any in-flight worker job (its snapshot of the doc is now stale)
function Highlighter:drop_job()
  if self.job and tokenizer.thread_cancel then
    tokenizer.thread_cancel(self.job.id)
  end
  self.job = nil
end

function Highlighter:reset()
  self.lines = {}
  self:drop_job()
  self:soft_reset()
end

function Highlighter:soft_reset()
  for i=1,#self.lines do
    self.lines[i] = false
  end
  self.first_invalid_line = 1
  self.max_wanted_line = 0
  self:drop_job()
end

function Highlighter:invalidate(idx)
  self.first_invalid_line = math.min(self.first_invalid_line, idx)
  self:drop_job()   -- the next thread_step resubmits from first_invalid_line
  set_max_wanted_lines(self, math.min(self.max_wanted_line, #self.doc.lines))
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

function Highlighter:update_notify(line, n)
  -- plugins can hook here to be notified that lines have been retokenized
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
    self:update_notify(idx, 0)
  end
  set_max_wanted_lines(self, math.max(self.max_wanted_line, idx))
  return line
end


function Highlighter:each_token(idx)
  return tokenizer.each_token(self:get_line(idx).tokens)
end

return Highlighter
