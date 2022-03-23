local core = require "core"
local common = require "core.common"
local config = require "core.config"
local tokenizer = require "core.tokenizer"
local Object = require "core.object"

local considered_slow = 0.05
local considered_huge = 10000
local maximum_context = 50
local max_line_len_when_slow = config.line_limit + 20

local Highlighter = Object:extend()

function Highlighter:new(doc)
  self.doc = doc
  self.lazy_mode = false
  self.last_line_edited = nil
  self.last_tokenize_time = {line = 0, time = 0}
  self.visible_lines = {first = 1, last = 1}
  self.tokenized_visible = false
  self.first_tokenization_run = false
  self.first_lines = false
  self:reset()

  -- init incremental syntax highlighting
  core.add_thread(function()
    while true do
      local doc_lines = #self.doc.lines

      if self.tokenized_visible or not self.doc.syntax or doc_lines <= 0 then
        coroutine.yield(1 / config.fps)

      else
        local first_run_next_min = nil
        ::tokenize::
        -- check if we should first tokenize visible lines
        local two_pass = false
        if
          self.lazy_mode and self.first_lines and not self.last_line_edited
          and
          (
            not self.lines[self.visible_lines.first]
            or
            not self.lines[self.visible_lines.last]
          )
        then
          two_pass = true
        end

        local min, max = 0, 0
        local first_visible = self.visible_lines.first
        local last_visible = self.visible_lines.last
        local last_edited = self.last_line_edited
        local yielded = false

        if
          not self.first_tokenization_run
          and
          not (doc_lines > considered_huge or self.lazy_mode)
        then
          min = first_run_next_min or 1
          max = doc_lines
        elseif not two_pass then
          if last_edited and self.doc.lines[last_edited] then
            min = self.last_line_edited
            self.last_line_edited = nil
          else
            min = math.max(
              (doc_lines > considered_huge or self.lazy_mode)
                and self.visible_lines.first - maximum_context
                or self.visible_lines.first,
              1
            )
          end
          max = math.min(
            (doc_lines > considered_huge or self.lazy_mode)
              and self.visible_lines.first + maximum_context
              or doc_lines,
            doc_lines
          )
        else
          min = math.max(self.visible_lines.first, 1)
          max = math.min(self.visible_lines.last, doc_lines)
        end

        if min > 0 then
          local reset_line, start_time = false, system.get_time();

          ::tokenize_loop::
          for i = min, max do
            local state = ((i > 1) and self.lines[i - 1])
              and self.lines[i - 1].state or nil
            local line = self.lines[i]
            local line_len = 0
            if self.doc.lines[i] then
              line_len = #self.doc.lines[i]
            else
              break
            end
            if not (
              line and line.lazy and line.init_state == state
              and
              line_len < 2 and line.text == self.doc.lines[i]
            )
            then
              -- yield currently non visible lines or long lines in lazy_mode
              local yield_tokenizer = (i < self.visible_lines.first
                or i > self.visible_lines.last) or (
                  self.lazy_mode and line_len > max_line_len_when_slow
              )

              self.lines[i] = self:tokenize_line(i, state, yield_tokenizer)
              self.lines[i].lazy = true
              local end_time = system.get_time()
              local total_time = end_time - start_time

              -- check the rest of the lines that follow the last edited
              -- to see if they do not require tokenization and exit
              if
                last_edited and i > last_edited
                and self:tokens_same(line, self.lines[i])
              then
                self.tokenized_visible = true
                break
              end

              if reset_line or (not yield_tokenizer and total_time >= considered_slow) then
                reset_line, core.redraw, yielded = false, true, true
                coroutine.yield()
                if max > #self.doc.lines then break end
                start_time = system.get_time();
              else
                yielded, start_time = yield_tokenizer, end_time
              end
            end
            first_run_next_min = i
            -- restart tokenization from last edited line
            if self.last_line_edited then
              if self.last_line_edited <= i then
                min = math.min(self.last_line_edited, #self.doc.lines)
                self.last_line_edited, reset_line = nil, true
                goto tokenize_loop
              end
            end
          end

          if
            first_visible == self.visible_lines.first
            and
            last_visible == self.visible_lines.last
          then
            self.tokenized_visible = true
          end

          if not self.tokenized_visible or two_pass then
            if not yielded then coroutine.yield() end
            two_pass = false
            goto tokenize
          end

          self.first_tokenization_run = true
          self.first_lines = true

          core.redraw = true
        end
        coroutine.yield()
      end
    end
  end, self)
end

function Highlighter:tokens_same(line1, line2)
  if not line1 or not line2 or #line1.tokens ~= #line2.tokens then
    return false
  end
  for i, token in ipairs(line1.tokens) do
    if token ~= line2.tokens[i] then return false end
  end
  return true
end

function Highlighter:set_visible_lines(first, last)
  if first ~= 1 and last ~= 1 and self.first_lines then
    if
      first < last
      and
      (first ~= self.visible_lines.first or last ~= self.visible_lines.last)
    then
      self.visible_lines.first = first
      self.visible_lines.last = last
      if self.lazy_mode then
        self.tokenized_visible = false
      else
        for i=first, last do
          if not self.lines[i] or not self.lines[i].lazy then
            self.tokenized_visible = false
            return
          end
        end
      end
    end
  elseif not self.first_lines then
    self.visible_lines.first = 1
    self.visible_lines.last = 100
    self.tokenized_visible = false
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
end

function Highlighter:insert_notify(line, n)
  self.last_line_edited = line
  local blanks = { }
  for i = 1, n do
    blanks[i] = false
  end
  common.splice(self.lines, line, 0, blanks)
end

function Highlighter:remove_notify(line, n)
  self.last_line_edited = line
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
      line_len > 1 and ((force or not self.lazy_mode)
      or
      line_len <= max_line_len_when_slow
      or
      (
        self.last_line_edited == idx
        and
        -- edited a single line and tokenization time is fast even if long
        -- otherwise lazy tokenize to avoid typing lag
        (
          self.last_tokenize_time.line ~= idx
          or
          self.last_tokenize_time.time < considered_slow
        )
      )
    )
    then
      local prev = self.lines[idx - 1]
      local start_time = system.get_time()
      line = self:tokenize_line(idx, prev and prev.state)
      line.lazy = false
      local end_time = system.get_time()
      local total_time = end_time - start_time

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
    end
    if self.first_lines then
      self.visible_lines.first = idx
      self.tokenized_visible = false
    end
  end
  return line
end

function Highlighter:each_token(idx, force)
  return tokenizer.each_token(self:get_line(idx, force).tokens)
end


return Highlighter
