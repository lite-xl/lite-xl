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

local c_likes = { "{", "}" }

config.plugins.codefolding = common.merge({
  debug = false,
  blocks = {
    ["C"] = c_likes,
    ["C++"] = c_likes,
    ["JavaScript"] = c_likes,
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
  -- hash that contains a list of lines that are not visible due to being folded.
  self.folded = {}
  -- hash that contains a list of all lines that are part of a folding block;
  -- keys being the line number, values being the line number that started this block
  self.foldable = {}
  return old_docview_new(self, ...)
end

function DocView:compute_fold(doc_line)
  local blocks = self:get_folding_blocks()
  if not blocks then return end
  local start_of_computation = doc_line
  for i = doc_line - 1, 1, -1 do
    if self.foldable[i] then break end
    start_of_computation = i
  end
  for i = start_of_computation, doc_line do
    if i > 1 then
      local origin = self.foldable[i - 1] or 0
      if self.doc.lines[i-1]:find(blocks[1] .. "%s*$") then
        origin = i - 1
      elseif self.doc.lines[i-1]:find(blocks[2] .. "%s*$") then
        origin = self.foldable[self.foldable[i - 1]] or 0
        if self.doc.lines[self.foldable[i - 1]] and self.doc.lines[self.foldable[i - 1]]:find("^%s*" .. blocks[2]) then
          origin = self.foldable[self.foldable[self.foldable[i - 1]]] or 0
        else
          origin = self.foldable[self.foldable[i - 1]] or 0 
        end
      end
      self.foldable[i] = origin
    else
      self.foldable[i] = 0
    end
  end
end


local old_tokenize = DocView.tokenize
function DocView:tokenize(line)
  local blocks = self:get_folding_blocks()
  local tokens = old_tokenize(self, line)
  if not self.foldable or not blocks then return tokens end
  self:compute_fold(line)
  if self.folded[line] then return {} end
  if self:is_foldable(line) and self.folded[line+1] then
    -- remove the newline from the end of the tokens
    local type, line, e = tokens[#tokens - 4], tokens[#tokens - 3], tokens[#tokens - 1]
    if type == "doc" and self.doc.lines[line]:sub(e, e) == "\n" then tokens[#tokens - 1] = tokens[#tokens - 1] - 1 end
    table.insert(tokens, "virtual")
    table.insert(tokens, line)
    table.insert(tokens, " ... ")
    table.insert(tokens, false)
    table.insert(tokens, { color = style.dim })
    table.insert(tokens, "virtual")
    table.insert(tokens, line)
    table.insert(tokens, blocks[2] .. "\n")
    table.insert(tokens, false)
    table.insert(tokens, {  })
  end
  return tokens
end

function DocView:is_foldable(line)
  if line < #self.doc.lines - 1 then
    if not self.foldable[line] or not self.foldable[line+1] then self:compute_fold(line+1) end
    return self.foldable[line] and self.foldable[line+1] > self.foldable[line] and self.foldable[line]
  end
  return false
end

function DocView:toggle_fold(start_doc_line, value)
  local blocks = self:get_folding_blocks()
  if self:is_foldable(start_doc_line) then
    local is_folded = self:is_folded(start_doc_line)
    if value == nil then value = not is_folded end
    if (value and not is_folded) or (is_folded and not value) then
      local starting_fold = self.foldable[start_doc_line]
      local end_doc_line = start_doc_line + 1
      while end_doc_line <= #self.doc.lines do
        if end_doc_line < #self.doc.lines and not self.foldable[end_doc_line] then self:compute_fold(end_doc_line+1) end
        if self.foldable[end_doc_line] <= starting_fold then break end
        self.folded[end_doc_line] = value
        end_doc_line = end_doc_line + 1
      end
      --self:invalidate_cache(start_doc_line, end_doc_line)
      -- TODO: Don't potentially need to invalidate this much, but if we don't then we get a judder if you open/close a thing at the bottom of the screen.
      -- Should probably fix this without invadliating everything.
      self:invalidate_cache(start_doc_line)
    end
  end
end


local old_get_gutter_width = DocView.get_gutter_width
function DocView:get_gutter_width()
  local x,y = old_get_gutter_width(self)
  return x + style.padding.x, y
end

local old_draw_line_gutter = DocView.draw_line_gutter
function DocView:draw_line_gutter(line, x, y, width)
  local lh = old_draw_line_gutter(self, line, x, y, width)
  local size = lh - 8
  local startx = x + 4
  local starty = y + (lh - size) / 2
  if self:is_foldable(line) then
    renderer.draw_rect(startx, starty, size, size, style.accent)
    renderer.draw_rect(startx + 1, starty + 1, size - 2, size - 2, self.hovering_foldable == line and style.dim or style.background)
    common.draw_text(self:get_font(), style.accent, self:is_folded(line) and "+" or "-", "center", startx, starty, size, size)
  end
  if config.plugins.codefolding.debug then
    common.draw_text(self:get_font(), style.accent, self.foldable[line] or 0, "center", startx, starty, size, size)
  end
  return lh
end

local old_mouse_moved = DocView.on_mouse_moved
function DocView:on_mouse_moved(x, y, ...)
  old_mouse_moved(self, x, y, ...)
  self.hovering_foldable = false
  if self.hovering_gutter then
    local line = self:resolve_screen_position(x, y)
    if self:is_foldable(line) then
      self.hovering_foldable = line
      self.cursor = "hand"
    end
  end
end

local old_mouse_pressed = DocView.on_mouse_pressed
function DocView:on_mouse_pressed(button, x, y, clicks)
  if button == "left" and self.hovering_foldable then
    self:toggle_fold(self.hovering_foldable)
  end
  return old_mouse_pressed(button, x, y, clicks)
end

command.add(function()
  if not core.active_view:extends(DocView) then return false end
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
