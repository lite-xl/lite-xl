-- mod-version:4
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
  { "{", "}" } 
}
local lua = { 
  { "%f[%a]function%s*[^(]*%s*%([^%)]*%)", "%f[%a]end%f[%A]" },
  { "%f[%a]do%f[%A]", "%f[%a]end%f[%A]" },
  { "%f[%a]then%f[%A]", "%f[%a]end%f[%A]" }
}

config.plugins.codefolding = common.merge({
  debug = false,
  blocks = {
    ["C"] = c_likes,
    ["C++"] = c_likes,
    ["JavaScript"] = c_likes,
    ["Lua"] = lua,
    ["*"] = nil
  }
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
  -- hash contains the list of open blocks at the end of this line
  self.folding_stack = { "" }
  return old_docview_new(self, ...)
end

local function compute_line_characteristics(blocks, line, folding_stack)
  local closing_block = #folding_stack > 0 and blocks[folding_stack:byte(-1)][2]
  local found_token = 1
  local first_found_end, last_found_start
  while found_token do
    local s,e = line:find("%s*$", found_token)
    if s == found_token then 
      break 
    end
    local opening_token_start, opening_token_end, opening_token_idx
    local closing_token_start, closing_token_end = closing_block and line:find(closing_block, found_token)
    for j = 1, #blocks do
      local new_opening_token_start, new_opening_token_end = line:find(blocks[j][1], found_token)
      if new_opening_token_start and (not opening_token_start or new_opening_token_start < opening_token_start) then
        opening_token_start, opening_token_end, opening_token_idx = new_opening_token_start, new_opening_token_end, j
      end
    end
    if closing_token_start and (not opening_token_start or closing_token_start < opening_token_start) then
      folding_stack = folding_stack:sub(1, -2)
      found_token = closing_token_end
      last_found_start = closing_token_start
      first_found_end = first_found_end or closing_token_end
      closing_token_start = nil
    elseif opening_token_start then
      folding_stack = folding_stack .. string.char(opening_token_idx)
      found_token = opening_token_end + 1
      last_found_start = opening_token_start
      first_found_end = first_found_end or closing_token_end
    else
      break
    end
  end
  return folding_stack, first_found_end, last_found_start
end

function DocView:compute_fold(doc_line)
  local blocks = self:get_folding_blocks()
  if not blocks then return end
  local start_of_computation = doc_line
  for i = doc_line - 1, 1, -1 do
    if self.folding_stack[i] then break end
    start_of_computation = i
  end
  for i = start_of_computation, doc_line do
    self.folding_stack[i] = compute_line_characteristics(blocks, self.doc.lines[i], self.folding_stack[i - 1] or "")
  end
end


local old_tokenize = DocView.tokenize
function DocView:tokenize(line)
  local blocks = self:get_folding_blocks()
  local tokens = old_tokenize(self, line)
  if not blocks then return tokens end
  self:compute_fold(line)
  if self.folded[line] then 
    if self.folded[line] == true then return {} end
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
    return #(self.folding_stack[line - 1] or "") < #self.folding_stack[line]
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
          self:compute_fold(end_doc_line+1) 
        end
        if #self.folding_stack[end_doc_line] < starting_fold then 
          local _, _, last_found_start = compute_line_characteristics(blocks, self.doc.lines[end_doc_line], self.folding_stack[end_doc_line - 1])
          self.folded[end_doc_line] = value and last_found_start
          break 
        end
        self.folded[end_doc_line] = not not value
        end_doc_line = end_doc_line + 1
      end
      --self:invalidate_cache(start_doc_line, end_doc_line)
      -- TODO: Don't potentially need to invalidate this much, but if we don't then we get a judder if you open/close a thing at the bottom of the screen.
      -- Should probably fix this without invadliating everything.
      self:invalidate_cache(start_doc_line)
    end
  end
  self:invalidate_cache()
  self:ensure_cache(1, #self.doc.lines)
end


local old_get_gutter_width = DocView.get_gutter_width
function DocView:get_gutter_width()
  local x,y = old_get_gutter_width(self)
  return x + self:get_font():get_width("+"), y
end

local old_draw_line_gutter = DocView.draw_line_gutter
function DocView:draw_line_gutter(vline, x, y, width)
  local lh = old_draw_line_gutter(self, vline, x, y, width)
  if not self:get_folding_blocks() then return lh end
  local line, col = self:get_dline(vline)
  if col == 1 then
    local size = lh - 8
    local startx = x + 4
    local starty = y + (lh - size) / 2
    if self:is_foldable(line) then
      renderer.draw_rect(startx, starty, size, size, style.accent)
      renderer.draw_rect(startx + 1, starty + 1, size - 2, size - 2, self.hovering_foldable == line and style.dim or style.background)
      common.draw_text(self:get_font(), style.accent, self:is_folded(line) and "+" or "-", "center", startx, starty, size, size)
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
  if not blocks then return end
  self.hovering_foldable = false
  if self.hovering_gutter and x < self.position.x + self:get_font():get_width("+") + style.padding.x then
    local line = self:resolve_screen_position(x, y)
    if self:is_foldable(line) then
      self.hovering_foldable = line
      self.cursor = "hand"
    end
  end
end

local old_mouse_pressed = DocView.on_mouse_pressed
function DocView:on_mouse_pressed(button, x, y, clicks)
  if old_mouse_pressed(button, x, y, clicks) then return true end
  local blocks = self:get_folding_blocks()
  if blocks and button == "left" and self.hovering_foldable then
    self:toggle_fold(self.hovering_foldable)
    return true
  end
  return false
end

command.add(function()
  if not core.active_view:extends(DocView) or not core.active_view:get_folding_blocks() then return false end
  local line = core.active_view:get_selection()
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
  ["codefolding:unfold"] = function(dv)
    local line = dv:get_selection()
    dv:toggle_fold(line, false)
  end
})
command.add(DocView, {
  ["codefolding:fold-all"] = function(dv)
    dv:compute_fold(#dv.doc.lines)
    for i = #dv.doc.lines, 1, -1 do
      if dv:is_foldable(i) == 0 then 
        dv:toggle_fold(i, true) 
      end
    end
  end,
  ["codefolding:unfold-all"] = function(dv)
    dv:compute_fold(#dv.doc.lines)
    for i = #dv.doc.lines, 1, -1 do
      if dv:is_foldable(i) == 0 then 
        dv:toggle_fold(i, false) 
      end
    end
  end
})

keymap.add {
  ["ctrl+alt+["] = "codefolding:fold",
  ["ctrl+alt+]"] = "codefolding:unfold",
  ["ctrl+alt+\\"] = "codefolding:toggle",
  ["ctrl+alt+-"] = "codefolding:fold-all",
  ["ctrl+alt+="] = "codefolding:unfold-all"
} 
