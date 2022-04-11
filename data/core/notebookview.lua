local core = require "core"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local keymap = require "core.keymap"
local translate = require "core.doc.translate"
local View = require "core.view"
local Doc = require "core.doc"
local DocView = require "core.docview"


local InlineDocView = DocView:extend()

function InlineDocView:new()
  InlineDocView.super.new(self, Doc())
end


function InlineDocView:scroll_to_make_visible()
  -- no-op function to disable this functionality
end


function InlineDocView:get_gutter_width()
  return 0
end


function InlineDocView:draw_line_gutter(idx, x, y)
end


local notebook_margin  = { x = 15 * SCALE, y = 10 * SCALE }
local notebook_padding = { x = 10 * SCALE,  y = 0 * SCALE }
local notebook_border  = 1 * SCALE


local NotebookView = View:extend()

function NotebookView:new()
  NotebookView.super.new(self)
  self.parts = { }
  self.input_view = { } -- Dummy view.
  self.output_view = { }
  self.active_view = self
  self:start_process()
end


function NotebookView:start_process()
  local proc, err = process.start(core.gsl_shell.cmd, { stderr = process.REDIRECT_PIPE })
  if not proc then
    -- FIXME: treat error code and warn the user
    return
  end
  self.process = proc
  -- The following variable is used to hold pending newlines in output.
  -- It is stored in "self" because it can be cleared by the submit() method
  -- when a new output cell is started and the pending newlines are discarded.
  self.pending_newlines = { stdout = "", stderr = "" }
  self.pending_output = { stdout = false, stderr = false }
  local function polling_function(process, channel)
    return function()
      local read_function = process["read_" .. channel]
      while true do
        local text = read_function(process)
        if text ~= nil then
          text = text:gsub("\r\n", "\n")
          local newlines = text:match("%f[\n](\n+)$") or ""
          -- get the text without the pending newlines, if any
          local text_strip = text:sub(1, -#newlines - 1)
          if text_strip ~= "" then
            local output_view = {
              stdout = self.input_view.stdout,
              stderr = self.input_view.stderr,
            }
            if not output_view[channel] then
              self:new_output(self.input_view, channel)
              self.active_view = self:new_input(self.input_view)
              self.input_view[channel] = self.output_view[channel]
            end
            local view = self.output_view[channel]
            local output_doc = view.doc
            output_doc:move_to(translate.end_of_doc, view)
            local line, col = output_doc:get_selection()
            output_doc:insert(line, col, self.pending_newlines[channel] .. text_strip)
            output_doc:move_to(translate.end_of_doc, view)
            self.pending_newlines[channel] = newlines
            self.pending_output[channel] = true
            coroutine.yield()
          else
            self.pending_newlines[channel] = self.pending_newlines[channel] .. newlines
            if #newlines > 0 then
              coroutine.yield()
            else
              coroutine.yield(0.1)
            end
          end
        else
          break
        end
      end
    end
  end
  core.add_thread(polling_function(self.process, "stderr"))
  core.add_thread(polling_function(self.process, "stdout"))
end


function NotebookView:find_insert_index(view)
  for i = 1, #self.parts do
    if self.parts[i] == view then return i + 1 end
  end
  return #self.parts + 1
end


function NotebookView:new_output(input_view, channel)
  local insert_index = self:find_insert_index(input_view)
  local view = InlineDocView()
  view.scroll_tight = true
  view.master_view = self
  view.channel = channel
  table.insert(self.parts, insert_index, view)
  self.pending_newlines.stdout = ""
  self.pending_newlines.stderr = ""
  self.output_view[channel] = view
end


function NotebookView:new_input(input_view)
  local insert_index = self:find_insert_index(input_view)
  for i = insert_index, #self.parts do
    if self.parts[i].channel == "stdin" then
      return self.parts[i]
    end
  end
  local view = InlineDocView()
  view.doc:set_syntax(".lua")
  view.channel = "stdin"
  view.notebook = self
  view.master_view = self
  view.scroll_tight = true
  table.insert(self.parts, view)
  return view
end


function NotebookView:remove_output_view(input_view)
  local i = 1
  while i <= #self.parts do
    if self.parts[i] == input_view.stdout or self.parts[i] == input_view.stderr then
      table.remove(self.parts, i)
    else
      i = i + 1
    end
  end
  input_view.stdout = nil
  input_view.stderr = nil
end


function NotebookView:submit()
  if not self.process or not self.active_view.channel == "stdin" then
    return
  end
  self.input_view = self.active_view
  self:remove_output_view(self.input_view)
  local doc = self.input_view.doc
  for _, line in ipairs(doc.lines) do
    self.process:write(line:gsub("\n$", " "))
  end
  self.process:write("\n")
  self.active_view = self
end


function NotebookView:scroll_to_inline_view(view)
  local pos = self:get_inline_positions()
  for i, coord in ipairs(pos) do
    local view_test = self.parts[i]
    if view_test == view then
      local x, y, w, h = unpack(coord)
      self.scroll.to.y = y + h
      return
    end
  end
end


function NotebookView:get_name()
  return "-- Notebook"
end


function NotebookView:update()
  -- core.active_view can be set to this same NotebookView or one of its input/output
  -- InlineDocView. By looking the "master_view" field we are sure we get the
  -- "NotebookView" in the case the active view is set to one of its InlineDocView.
  local node_level_active_view = core.active_view.master_view or core.active_view
  if node_level_active_view == self then
    if core.active_view ~= self.active_view then
      core.set_active_view(self.active_view)
    end
  end
  for _, channel in ipairs {"stdout", "stderr"} do
    if self.pending_output[channel] then
      self:scroll_to_inline_view(self.output_view[channel])
      self.pending_output[channel] = false
    end
  end
  for _, view in ipairs(self.parts) do
    view:update()
  end
  NotebookView.super.update(self)
end


function NotebookView:get_part_height(view)
  return view:get_line_height() * (#view.doc.lines) + style.padding.y * 2
end


function NotebookView:get_inline_positions(x_offset, y_offset)
  local x, y = notebook_margin.x + (x_offset or 0), notebook_margin.y + (y_offset or 0)
  local w = self.size.x - 2 * notebook_margin.x
  local pos = {}
  for i, view in ipairs(self.parts) do
    local h = self:get_part_height(view) + 2 * notebook_padding.y
    pos[i] = {x, y, w, h, notebook_padding.x, notebook_padding.y}
    y = y + h + notebook_margin.y
  end
  return pos
end


function NotebookView:get_part_drawing_rect(idx)
  local x_offs, y_offs = self:get_content_offset()
  local pos = self:get_inline_positions(x_offs, y_offs)
  return unpack(pos[idx])
end


function NotebookView:get_scrollable_size()
  local pos = self:get_inline_positions()
  if #pos > 0 then
    local x, y, w, h = unpack(pos[#pos])
    return y + h
  else
    return 0
  end
end


function NotebookView:get_overlapping_view(x, y)
  for i, view in ipairs(self.parts) do
    local x_part, y_part, w, h = self:get_part_drawing_rect(i)
    if x >= x_part and x <= x_part + w and y >= y_part and y <= y_part + h then
      return view
    end
  end
end


function NotebookView:on_mouse_pressed(button, x, y, clicks)
  local caught = NotebookView.super.on_mouse_pressed(self, button, x, y, clicks)
  if caught then return end
  local view = self:get_overlapping_view(x, y)
  if view then
    self.active_view = view
    view:on_mouse_pressed(button, x, y, clicks)
    return true
  end
end


function NotebookView:on_mouse_moved(x, y, ...)
  NotebookView.super.on_mouse_moved(self, x, y, ...)
  local view = self:get_overlapping_view(x, y)
  if view then
    view:on_mouse_moved(x, y, ...)
  end
end


function NotebookView:on_mouse_released(button, x, y)
  local caught = NotebookView.super.on_mouse_released(self, button, x, y)
  if caught then return end
  local view = self:get_overlapping_view(x, y)
  if view then
    self.active_view = view
    view:on_mouse_released(button, x, y)
    return true
  end
end


function NotebookView:on_text_input(text)
  if self.active_view:is(InlineDocView) then
    self.active_view:on_text_input(text)
  end
end


local outline_color_by_channel = {
  stdout = style.line_number,
  stderr = style.nagbar,
  stdin  = style.caret,
}

function NotebookView:draw()
  self:draw_background(style.background)
  local pos = self:get_inline_positions(self:get_content_offset())
  for i, coord in ipairs(pos) do
    local view = self.parts[i]
    local x, y, w, h, pad_x, pad_y = unpack(coord)
    local outline_color = outline_color_by_channel[view.channel]
    renderer.draw_rect(x, y, notebook_border, h, outline_color)
    view.size.x, view.size.y = w - 2 * pad_x, h - 2 * pad_y
    view.position.x, view.position.y = x + pad_x, y + pad_y
    view:draw()
  end

  self:draw_scrollbar()
end


command.add(nil, {
  ["notebook:submit"] = function()
    local view = core.active_view
    if view:is(DocView) and view.notebook then
      view.notebook:submit()
    end
  end,
})

keymap.add { ["shift+return"] = "notebook:submit" }


return NotebookView
