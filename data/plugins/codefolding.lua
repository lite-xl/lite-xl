-- mod-version:3
local core = require "core"
local config = require "core.config"
local style = require "core.style"
local Doc = require "core.doc"
local DocView = require "core.docview"
local Node = require "core.node"
local common = require "core.common"

local old_transform = DocView.transform

function DocView:is_folded(doc_line)
  return self.folded[doc_line+1]
end

local old_docview_new = DocView.new
function DocView:new(...)
  self.folded = {}
  self.foldable = {}
  return old_docview_new(self, ...)
end

function DocView:compute_fold(doc_line)
  local start_of_computation = doc_line
  for i = doc_line - 1, 1, -1 do
    if self.foldable[i] then break end
    start_of_computation = i
  end
  for i = start_of_computation, doc_line do
    if i > 1 then
      local origin = self.foldable[i - 1]
      if self.doc.lines[i-1]:find("{%s*$") then
        origin = origin + 1
      elseif self.doc.lines[i-1]:find("}%s*$") and not self.doc.lines[i-1]:find("^%s* }%s*$") then
        origin = origin - 1
      end
      if self.doc.lines[i]:find("^%s*}") then
        origin = origin - 1
      end
      self.foldable[i] = origin
    else
      self.foldable[i] = 0
    end
  end
end

function DocView:transform(doc_line)
  local results = old_transform(self, doc_line)
  self:compute_fold(doc_line)
  if self.folded[doc_line] then return {} end
  if self:is_foldable(doc_line) and self.folded[doc_line+1] then
    -- remove the newline from the end of the tokens
    table.insert(results, "virtual")
    table.insert(results, " ... ")
    table.insert(results, false)
    table.insert(results, false)
    table.insert(results, { color = style.dim })
    table.insert(results, "virtual")
    table.insert(results, "}")
    table.insert(results, false)
    table.insert(results, false)
    table.insert(results, {  })
  end
  return results
end

function DocView:is_foldable(doc_line)
  if doc_line < #self.doc.lines then
    if not self.foldable[doc_line] or not self.foldable[doc_line+1] then self:compute_fold(doc_line+1) end
    return self.foldable[doc_line] and self.foldable[doc_line+1] > self.foldable[doc_line]
  end
  return false
end

function DocView:toggle_fold(doc_line, value)
  if self:is_foldable(doc_line) then
    if value == nil then value = not self:is_folded(doc_line) end
    local starting_fold = self.foldable[doc_line]
    local line = doc_line + 1
    self:invalidate_cache(doc_line)
    while line <= #self.doc.lines do
      if self.foldable[line] <= starting_fold then
        if self.doc.lines[line]:find("}%s*$") then self.folded[line] = value end
        break
      end
      self.folded[line] = value
      line = line + 1
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
  local start = x + 4
  if self:is_foldable(line) then
    renderer.draw_rect(start, y, lh, lh, style.accent)
    renderer.draw_rect(start + 1, y + 1, lh - 2, lh - 2, self.hovering_foldable == line and style.dim or style.background)
    common.draw_text(self:get_font(), style.accent, self:is_folded(line) and "+" or "-", "left", start + 6, y, width, lh)
  end
  -- common.draw_text(self:get_font(), style.accent, self.foldable[line] or "nil", "left", start + 6, y, width, lh)
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

