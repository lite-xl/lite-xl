-- mod-version:4
-- Plugin that handles code folding within the editor.
-- language_* plugins can modify the config for what can be folded by doing, for example:
-- config.plugins.codefolding.blocks["perl"] = { { "{", "}" }
-- 
-- This plugin also handles the folding of long lines.
local core = require "core"
local config = require "core.config"
local style = require "core.style"
local Doc = require "core.doc"
local DocView = require "core.docview"
local Node = require "core.node"
local common = require "core.common"
local command = require "core.command"
local keymap = require "core.keymap"

local c_likes = { 
  { "{", "}" },
  { "^%s*#if", "#endif" },
  { "^%s*#ifdef", "#endif" },
  { "^%s*#ifndef", "#endif" }
}
local lua = { 
  { "%f[%a]function%s*[^(]*%s*%([^%)]*%)", "%f[%a_]end%f[%A]" },
  { "%f[%a]while.*do%f[%A]", "%f[%a_]end%f[%A]" },
  { "%f[%a]if.*%f[%a]then%f[%A]", "%f[%a_]end%f[%A]" }
}

config.plugins.codefolding = common.merge({
  debug = false,
  -- anything over this many characters will be truncated and replaced with ...
  -- set to false to disable
  fold_long_lines = 900, 
  -- the amount of characters to show at the end
  fold_long_trailing = 100,
  blocks = common.merge({
    ["C"] = c_likes,
    ["C++"] = c_likes,
    ["JavaScript"] = c_likes,
    ["Lua"] = lua,
    ["*"] = nil
  }, config.plugins.codefolding.blocks or {})
}, config.plugins.codefolding);

function DocView:get_folding_blocks()
  return self.doc and self.doc.syntax and config.plugins.codefolding.blocks[self.doc.syntax.name] or config.plugins.codefolding.blocks["*"]
end

function DocView:is_folded(doc_line)
  return self.folded[doc_line+1]
end

local old_docview_new = DocView.new
function DocView:new(...)
  -- keys are line numbers that are folded, values is either true, or  { start, end }
  self.folded = {}
  self.expanded = {}
  -- hash contains the list of open blocks at the end of this line
  self.folding_stack = { "" }
  return old_docview_new(self, ...)
end

-- returns the folding stack for the line, the start of the folded block, and the end, if relevant
local function compute_line_characteristics(blocks, line, folding_stack)
  local closing_block = #folding_stack > 0 and blocks[folding_stack:byte(-1)][2]
  local found_token = 1
  local first_found_end, last_found_start
  while found_token do
    local s = string.find(line, "%S", found_token)
    if not s then 
      break 
    end
    local opening_token_start, opening_token_end, opening_token_idx
    local closing_token_start, closing_token_end
    if closing_block then
      closing_token_start, closing_token_end = line:find(closing_block, found_token)
    end
    for j = 1, #blocks do
      local new_opening_token_start, new_opening_token_end = line:find(blocks[j][1], found_token)
      if new_opening_token_start and (not opening_token_start or new_opening_token_start < opening_token_start) then
        opening_token_start, opening_token_end, opening_token_idx = new_opening_token_start, new_opening_token_end, j
      end
    end
    if closing_token_start and (not opening_token_start or closing_token_start < opening_token_start) then
      folding_stack = folding_stack:sub(1, -2)
      found_token = closing_token_end and closing_token_end + 1
      last_found_start = closing_token_start
      first_found_end = first_found_end or closing_token_end
      closing_token_start = nil
    elseif opening_token_start then
      folding_stack = folding_stack .. string.char(opening_token_idx)
      found_token = opening_token_end + 1
      last_found_start = opening_token_start
      -- first_found_end = first_found_end or closing_token_end
      first_found_end = first_found_end
    else
      break
    end
  end
  return folding_stack, first_found_end, last_found_start
end

function DocView:compute_fold(doc_line, visible)
  local blocks = self:get_folding_blocks()
  if not blocks then return end
  local start_of_computation = doc_line
  for i = doc_line - 1, 1, -1 do
    if self.folding_stack[i] then break end
    start_of_computation = i
  end
  for i = start_of_computation, doc_line do
    self.folding_stack[i] = compute_line_characteristics(blocks, self.doc.highlighter:get_syntaxful_line(i, visible), self.folding_stack[i - 1] or "")
  end
end

function DocView:truncate_tokens(tokens, line, trigger_length, trailing_length)
  local total_length = 0
  local i = 1
  local new_tokens = {}
  while i < #tokens do
    if tokens[i] == "doc" then
      total_length = total_length + tokens[i + 3] - tokens[i + 2]
      if total_length > trigger_length then
        table.move(tokens, 1, i + 4, 1, new_tokens)
        local diff = (tokens[i + 3] - tokens[i + 2]) - (total_length - trigger_length)
        new_tokens[i + 3] = diff + tokens[i + 2] - 1
        break
      end
    else
      total_length = total_length + tokens[i + 2]:ulen()
      if total_length > trigger_length then
        table.move(tokens, 1, i + 4, 1, new_tokens)
        local diff = tokens[i + 2]:ulen() - (total_length - trigger_length)
        new_tokens[i + 2] = new_tokens[i + 2]:usub(1, diff + 1)
        break
      end
    end
    i = i + 5
  end
  if total_length <= trigger_length then return tokens end
  table.insert(new_tokens, "virtual")
  table.insert(new_tokens, line)
  table.insert(new_tokens, " ... ")
  table.insert(new_tokens, false)
  table.insert(new_tokens, { color = style.dim })
  local trailing_tokens = {}
  local cumulative_trailing_length = 0
  local new_token_length = #new_tokens + 1
  i = #tokens - 4
  while i >= 1 do
    local length
    if tokens[i] == "doc" then
      length = tokens[i + 3] - tokens[i + 2] 
      if cumulative_trailing_length + length >= trailing_length then
        local diff = trailing_length - cumulative_trailing_length
        table.move(tokens, i, #tokens, new_token_length, new_tokens)
        new_tokens[new_token_length + 2] = tokens[i + 3] - diff
        break
      end
    else
      length = tokens[i + 2]:ulen()
      if cumulative_trailing_length + length >= trailing_length then
        local diff = trailing_length - cumulative_trailing_length
        table.move(tokens, i, #tokens, new_token_length, new_tokens)
        new_tokens[new_token_length + 2] = tokens[i + 2]:usub(tokens[i + 2]:ulen() - diff, tokens[i + 2]:ulen())
        break
      end
    end
    cumulative_trailing_length = cumulative_trailing_length + length
    i = i - 5
  end
  return new_tokens
end

local old_tokenize = DocView.tokenize
function DocView:tokenize(line, visible)
  local blocks = self:get_folding_blocks()
  local tokens = old_tokenize(self, line, visible)
  if not blocks then 
    if config.plugins.codefolding.fold_long_lines and #self.doc.lines[line] > config.plugins.codefolding.fold_long_lines then
      local new_tokens = not self.expanded[line] and self:truncate_tokens(tokens, line, config.plugins.codefolding.fold_long_lines, config.plugins.codefolding.fold_long_trailing)
      if new_tokens then 
        self.expanded[line] = false
        return new_tokens 
      else
        self.expanded[line] = self.expanded[line] or nil
      end
    elseif self.expanded then
      self.expanded[line] = nil
    end
    return tokens 
  end
  self:compute_fold(line, visible)
  if self.folded[line] then 
    if self.folded[line] == true then return {} end
    -- if this is the end of a fold, let's compute the line characteristics again. If we don't have an end block, then this fold 
    -- is no longer valid, so go back and invalidate everything prior to this that was folded, until we don't get a fold
    ---local stack, first_found_end, last_found_start = compute_line_characteristics(blocks, self.doc.get_syntaxful_line(line), self.folding_stack[line-1] or "")
    --local last_found_start = compute_line_characteristics(blocks, self.doc.get_syntaxful_line(line), self.folding_stack[line-1] or "")
    local _, last_found_start = compute_line_characteristics(blocks, self.doc.highlighter:get_syntaxful_line(line, true), self.folding_stack[line-1] or "")
    if last_found_start then
      local idx = 1
      local new_tokens = {}
      while (tokens[idx] ~= "doc" or tokens[idx + 3] > self.folded[line]) and idx <= #tokens do
        if tokens[idx] == "doc" then
          table.insert(new_tokens, "doc")
          table.insert(new_tokens, line)
          table.insert(new_tokens, self.folded[line])
          table.insert(new_tokens, tokens[idx + 3])
          table.insert(new_tokens, tokens[idx + 4])
          table.move(tokens, idx + 5, #tokens, #new_tokens, new_tokens)
          break
        end
        idx = idx + 5
      end
      return new_tokens
    else
      local start_line = line
      while start_line >= 1 and self.folded[start_line] do
        self.folded[start_line] = false
        start_line = start_line - 1
      end
      -- should probably avoid doing this
      self:invalidate_cache(start_line, line)
      return tokens
    end
  end
  if config.plugins.codefolding.fold_long_lines and #self.doc.lines[line] > config.plugins.codefolding.fold_long_lines then
    local new_tokens = not self.expanded[line] and self:truncate_tokens(tokens, line, config.plugins.codefolding.fold_long_lines, config.plugins.codefolding.fold_long_trailing)
    if new_tokens then 
      self.expanded[line] = false
      return new_tokens 
    else
      self.expanded[line] = self.expanded[line] or nil
    end
  else
    self.expanded[line] = nil
  end
  if self:is_foldable(line) and self.folded[line+1] and self.folded[line+1] == true then
    -- remove the newline from the end of the tokens
    local type, line, e = tokens[#tokens - 4], tokens[#tokens - 3], tokens[#tokens - 1]
    if type == "doc" and self.doc.lines[line]:sub(e, e) == "\n" then tokens[#tokens - 1] = tokens[#tokens - 1] - 1 end
    table.insert(tokens, "virtual")
    table.insert(tokens, line)
    table.insert(tokens, " ... ")
    table.insert(tokens, false)
    table.insert(tokens, { color = style.dim })
  end
  return tokens
end

function DocView:is_foldable(line)
  if line < #self.doc.lines and line >= 1 then
    if not self.folding_stack[line] then self:compute_fold(line) end
    return #(self.folding_stack[line - 1] or "") < #self.folding_stack[line] and #self.folding_stack[line]
  end
  return false
end

function DocView:toggle_fold(start_doc_line, value)
  local vline = self:get_vline(start_doc_line)
  start_doc_line = self:get_dline(vline, 1)
  local blocks = self:get_folding_blocks()
  if self:is_foldable(start_doc_line) then
    local is_folded = self:is_folded(start_doc_line)
    if value == nil then value = not is_folded end
    if (value and not is_folded) or (is_folded and not value) then
      local starting_fold = #self.folding_stack[start_doc_line]
      local end_doc_line = start_doc_line + 1
      while end_doc_line <= #self.doc.lines do
        if end_doc_line < #self.doc.lines and not self.folding_stack[end_doc_line] then 
          self:compute_fold(end_doc_line+1, true) 
        end
        if #self.folding_stack[end_doc_line] < starting_fold then 
          local _, _, last_found_start = compute_line_characteristics(blocks, self.doc.highlighter:get_syntaxful_line(end_doc_line, true), self.folding_stack[end_doc_line - 1])
          self.folded[end_doc_line] = value and last_found_start
          break 
        end
        self.folded[end_doc_line] = not not value
        end_doc_line = end_doc_line + 1
      end
      -- we didn't find the end of the fold, so therefor this entire fold is invalid. unfold everything.
      if end_doc_line > #self.doc.lines then
        for i = start_doc_line, #self.doc.lines do
          self.folded[i] = false
        end
      end
      --self:invalidate_cache(start_doc_line, end_doc_line)
      -- TODO: Don't potentially need to invalidate this much, but if we don't then we get a judder if you open/close a thing at the bottom of the screen.
      -- Should probably fix this without invadliating everything.
      self:invalidate_cache(start_doc_line)
    end
  end
end

function DocView:toggle_expand(doc_line, value)
  self.expanded[doc_line] = value
  self:invalidate_cache(doc_line, doc_line)
end


local old_get_gutter_width = DocView.get_gutter_width
function DocView:get_gutter_width()
  local x,y = old_get_gutter_width(self)
  return x + self:get_font():get_width("+"), y
end

local old_draw_line_gutter = DocView.draw_line_gutter
function DocView:draw_line_gutter(vline, x, y, width)
  local lh = old_draw_line_gutter(self, vline, x, y, width)
  local blocks = self:get_folding_blocks()
  local line, col = self:get_dline(vline)
  if col == 1 then
    local size = lh - 8
    local startx = x + 4
    local starty = y + (lh - size) / 2
    if self.expanded[line] == false or (blocks and self:is_foldable(line)) then
      renderer.draw_rect(startx, starty, size, size, style.accent)
      renderer.draw_rect(startx + 1, starty + 1, size - 2, size - 2, self.hovering_foldable == line and style.dim or style.background)
      if self.expanded[line] == false then
        common.draw_text(self:get_font(), style.accent, ">", "center", startx, starty - 1, size, size)
      else
        common.draw_text(self:get_font(), style.accent, self:is_folded(line) and "+" or "-", "center", startx, starty, size, size)
      end      
    end
    if config.plugins.codefolding.debug then
      common.draw_text(self:get_font(), style.accent, #self.folding_stack[line] or 0, "center", startx, starty, size, size)
    end
  end
  return lh
end

local old_mouse_moved = DocView.on_mouse_moved
function DocView:on_mouse_moved(x, y, ...)
  old_mouse_moved(self, x, y, ...)
  local blocks = self:get_folding_blocks()
  self.hovering_foldable = false
  if self.hovering_gutter and x < self.position.x + self:get_font():get_width("+") + style.padding.x then
    local line = self:resolve_screen_position(x, y)
    if self.expanded[line] == false or (blocks and self:is_foldable(line)) then
      self.hovering_foldable = line
      self.cursor = "hand"
    end
  end
end

local old_mouse_pressed = DocView.on_mouse_pressed
function DocView:on_mouse_pressed(button, x, y, clicks)
  if old_mouse_pressed(button, x, y, clicks) then return true end
  local blocks = self:get_folding_blocks()
  if self.hovering_foldable and self.expanded[self.hovering_foldable] == false then
    self:toggle_expand(self.hovering_foldable, true)
    return true
  elseif blocks and button == "left" and self.hovering_foldable then
    self:toggle_fold(self.hovering_foldable)
    return true
  end
  return false
end

command.add(function()
  if not core.active_view:extends(DocView) or not core.active_view:get_folding_blocks() then return false end 
  local vline = core.active_view:get_vline(core.active_view:get_selection())
  local line = core.active_view:get_dline(vline, 1)
  return core.active_view:is_foldable(line), core.active_view
end, {
  ["codefolding:toggle"] = function(dv)
    local line = dv:get_selection()
    dv:toggle_fold(line)
  end,
  ["codefolding:fold"] = function(dv)
    local line = dv:get_selection()
    dv:toggle_fold(line, true)
  end,
  ["codefolding:expand"] = function(dv)
    local line = dv:get_selection()
    dv:toggle_expand(line, true)
  end,
  ["codefolding:unfold"] = function(dv)
    local line = dv:get_selection()
    dv:toggle_fold(line, false)
  end
})
command.add(function()
   if not core.active_view:extends(DocView) then return false end 
   local line = core.active_view:get_selection()
   return core.active_view.expanded[line] ~= nil, core.active_view
end, {
  ["codefolding:expand"] = function(dv)
    local line = dv:get_selection()
    dv:toggle_expand(line, true)
  end
})
command.add(DocView, {
  ["codefolding:fold-all"] = function(dv)
    dv:compute_fold(#dv.doc.lines)
    for i = #dv.doc.lines, 1, -1 do
      if dv:is_foldable(i) == 1 then 
        dv:toggle_fold(i, true) 
      end
    end
  end,
  ["codefolding:unfold-all"] = function(dv)
    dv:compute_fold(#dv.doc.lines)
    for i = #dv.doc.lines, 1, -1 do
      if dv:is_foldable(i) == 1 then 
        dv:toggle_fold(i, false) 
      end
    end
  end
})

keymap.add {
  ["ctrl+alt+."] = "codefolding:expand",
  ["ctrl+alt+["] = "codefolding:fold",
  ["ctrl+alt+]"] = "codefolding:unfold",
  ["ctrl+alt+\\"] = "codefolding:toggle",
  ["ctrl+alt+-"] = "codefolding:fold-all",
  ["ctrl+alt+="] = "codefolding:unfold-all"
} 
