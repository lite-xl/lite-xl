-- mod-version:3
local core = require "core"
local common = require "core.common"
local keymap = require "core.keymap"
local command = require "core.command"
local style = require "core.style"
local View = require "core.view"

---@class plugins.projectsearch.resultsview : core.view
local ResultsView = View:extend()

function ResultsView:__tostring() return "ResultsView" end

ResultsView.context = "session"

function ResultsView:new(path, text, fn)
  ResultsView.super.new(self)
  self.scrollable = true
  self.brightness = 0
  self.max_h_scroll = 0
  self:begin_search(path, text, fn)
end


function ResultsView:get_name()
  return "Search Results"
end


local function find_all_matches_in_file(t, filename, fn)
  local fp = io.open(filename)
  if not fp then return t end
  local n = 1
  for line in fp:lines() do
    local s = fn(line)
    if s then
      -- Insert maximum 256 characters. If we insert more, for compiled files, which can have very long lines
      -- things tend to get sluggish. If our line is longer than 80 characters, begin to truncate the thing.
      local start_index = math.max(s - 80, 1)
      local text = (start_index > 1 and "..." or "") .. line:sub(start_index, 256 + start_index)
      if #line > 256 + start_index then text = text .. "..." end
      table.insert(t, { file = filename, text = text, line = n, col = s })
      core.redraw = true
    end
    if n % 100 == 0 then coroutine.yield() end
    n = n + 1
    core.redraw = true
  end
  fp:close()
end


function ResultsView:begin_search(path, text, fn)
  self.search_args = { path, text, fn }
  self.results = {}
  self.last_file_idx = 1
  self.query = text
  self.searching = true
  self.selected_idx = 0

  core.add_thread(function()
    local i = 1
    for dir_name, file in core.get_project_files() do
      if file.type == "file" and (not path or (dir_name .. "/" .. file.filename):find(path, 1, true) == 1) then
        local truncated_path = (dir_name == core.project_dir and "" or (dir_name .. PATHSEP))
        find_all_matches_in_file(self.results, truncated_path .. file.filename, fn)
      end
      self.last_file_idx = i
      i = i + 1
    end
    self.searching = false
    self.brightness = 100
    core.redraw = true
  end, self.results)

  self.scroll.to.y = 0
end


function ResultsView:refresh()
  self:begin_search(table.unpack(self.search_args))
end


function ResultsView:on_mouse_moved(mx, my, ...)
  ResultsView.super.on_mouse_moved(self, mx, my, ...)
  self.selected_idx = 0
  for i, item, x,y,w,h in self:each_visible_result() do
    if mx >= x and my >= y and mx < x + w and my < y + h then
      self.selected_idx = i
      break
    end
  end
end


function ResultsView:on_mouse_pressed(...)
  local caught = ResultsView.super.on_mouse_pressed(self, ...)
  if not caught then
    return self:open_selected_result()
  end
end


function ResultsView:open_selected_result()
  local res = self.results[self.selected_idx]
  if not res then
    return
  end
  core.try(function()
    local dv = core.root_view:open_doc(core.open_doc(res.file))
    core.root_view.root_node:update_layout()
    dv.doc:set_selection(res.line, res.col)
    dv:scroll_to_line(res.line, false, true)
  end)
  return true
end


function ResultsView:update()
  self:move_towards("brightness", 0, 0.1)
  ResultsView.super.update(self)
end


function ResultsView:get_results_yoffset()
  return style.font:get_height() + style.padding.y * 3
end


function ResultsView:get_line_height()
  return style.padding.y + style.font:get_height()
end


function ResultsView:get_scrollable_size()
  return self:get_results_yoffset() + #self.results * self:get_line_height()
end


function ResultsView:get_h_scrollable_size()
  return self.max_h_scroll
end


function ResultsView:get_visible_results_range()
  local lh = self:get_line_height()
  local oy = self:get_results_yoffset()
  local min = self.scroll.y+oy-style.font:get_height()
  min = math.max(1, math.floor(min / lh))
  return min, min + math.floor(self.size.y / lh) + 1
end


function ResultsView:each_visible_result()
  return coroutine.wrap(function()
    local lh = self:get_line_height()
    local x, y = self:get_content_offset()
    local min, max = self:get_visible_results_range()
    y = y + self:get_results_yoffset() + lh * (min - 1)
    for i = min, max do
      local item = self.results[i]
      if not item then break end
      local _, _, w = self:get_content_bounds()
      coroutine.yield(i, item, x, y, w, lh)
      y = y + lh
    end
  end)
end


function ResultsView:scroll_to_make_selected_visible()
  local h = self:get_line_height()
  local y = h * (self.selected_idx - 1)
  self.scroll.to.y = math.min(self.scroll.to.y, y)
  self.scroll.to.y = math.max(self.scroll.to.y, y + h - self.size.y + self:get_results_yoffset())
end


function ResultsView:draw()
  self:draw_background(style.background)

  -- status
  local ox, oy = self.position.x, self.position.y
  local yoffset = self:get_results_yoffset()
  renderer.draw_rect(self.position.x, self.position.y, self.size.x, yoffset, style.background)
  if self.scroll.y ~= 0 then
    renderer.draw_rect(self.position.x, self.position.y+yoffset, self.size.x, style.divider_size, style.divider)
  end

  local x, y = ox + style.padding.x, oy + style.padding.y
  local files_number = core.project_files_number()
  local per = common.clamp(files_number and self.last_file_idx / files_number or 1, 0, 1)
  local text
  if self.searching then
    if files_number then
      text = string.format("Searching %.f%% (%d of %d files, %d matches) for %q...",
        per * 100, self.last_file_idx, files_number,
        #self.results, self.query)
    else
      text = string.format("Searching (%d files, %d matches) for %q...",
        self.last_file_idx, #self.results, self.query)
    end
  else
    text = string.format("Found %d matches for %q",
      #self.results, self.query)
  end
  local color = common.lerp(style.text, style.accent, self.brightness / 100)
  renderer.draw_text(style.font, text, x, y, color)

  -- horizontal line
  local x = ox + style.padding.x
  local w = self.size.x - style.padding.x * 2
  local h = style.divider_size
  local color = common.lerp(style.dim, style.text, self.brightness / 100)
  renderer.draw_rect(x, oy + yoffset - style.padding.y, w, h, color)
  if self.searching then
    renderer.draw_rect(x, oy + yoffset - style.padding.y, w * per, h, style.text)
  end

  -- results
  local _, _, bw = self:get_content_bounds()
  core.push_clip_rect(ox, oy+yoffset + style.divider_size, bw, self.size.y-yoffset)
  local y1, y2 = self.position.y, self.position.y + self.size.y
  for i, item, x,y,w,h in self:each_visible_result() do
    local color = style.text
    if i == self.selected_idx then
      color = style.accent
      renderer.draw_rect(x, y, w, h, style.line_highlight)
    end
    x = x + style.padding.x
    local text = string.format("%s at line %d (col %d): ", item.file, item.line, item.col)
    x = common.draw_text(style.font, style.dim, text, "left", x, y, w, h)
    x = common.draw_text(style.code_font, color, item.text, "left", x, y, w, h)
    self.max_h_scroll = math.max(self.max_h_scroll, x)
  end
  core.pop_clip_rect()

  self:draw_scrollbar()
end

---@param path string
---@param text string
---@param fn fun(line_text:string):...
---@return plugins.projectsearch.resultsview?
local function begin_search(path, text, fn)
  if text == "" then
    core.error("Expected non-empty string")
    return
  end
  local rv = ResultsView(path, text, fn)
  core.root_view:get_active_node_default():add_view(rv)
  return rv
end


local function get_selected_text()
  local view = core.active_view
  local doc = (view and view.doc) and view.doc or nil
  if doc then
    return doc:get_text(table.unpack({ doc:get_selection() }))
  end
end


local function normalize_path(path)
  if not path then return nil end
  path = common.normalize_path(path)
  for i, project_dir in ipairs(core.project_directories) do
    if common.path_belongs_to(path, project_dir.name) then
      return project_dir.item.filename .. PATHSEP .. common.relative_path(project_dir.name, path)
    end
  end
  return path
end

---@class plugins.projectsearch
local projectsearch = {}

---@type plugins.projectsearch.resultsview
projectsearch.ResultsView = ResultsView

---@param text string
---@param path string
---@param insensitive? boolean
---@return plugins.projectsearch.resultsview?
function projectsearch.search_plain(text, path, insensitive)
  if insensitive then text = text:lower() end
  return begin_search(path, text, function(line_text)
    if insensitive then
      return line_text:lower():find(text, nil, true)
    else
      return line_text:find(text, nil, true)
    end
  end)
end

---@param text string
---@param path string
---@param insensitive? boolean
---@return plugins.projectsearch.resultsview?
function projectsearch.search_regex(text, path, insensitive)
  local re, errmsg
  if insensitive then
    re, errmsg = regex.compile(text, "i")
  else
    re, errmsg = regex.compile(text)
  end
  if not re then core.log("%s", errmsg) return end
  return begin_search(path, text, function(line_text)
    return regex.cmatch(re, line_text)
  end)
end

---@param text string
---@param path string
---@param insensitive? boolean
---@return plugins.projectsearch.resultsview?
function projectsearch.search_fuzzy(text, path, insensitive)
  if insensitive then text = text:lower() end
  return begin_search(path, text, function(line_text)
    if insensitive then
      return common.fuzzy_match(line_text:lower(), text) and 1
    else
      return common.fuzzy_match(line_text, text) and 1
    end
  end)
end


command.add(nil, {
  ["project-search:find"] = function(path)
    core.command_view:enter("Find Text In " .. (normalize_path(path) or "Project"), {
      text = get_selected_text(),
      select_text = true,
      submit = function(text)
        projectsearch.search_plain(text, path, true)
      end
    })
  end,

  ["project-search:find-regex"] = function(path)
    core.command_view:enter("Find Regex In " .. (normalize_path(path) or "Project"), {
      submit = function(text)
        projectsearch.search_regex(text, path, true)
      end
    })
  end,

  ["project-search:fuzzy-find"] = function(path)
    core.command_view:enter("Fuzzy Find Text In " .. (normalize_path(path) or "Project"), {
      text = get_selected_text(),
      select_text = true,
      submit = function(text)
        projectsearch.search_fuzzy(text, path, true)
      end
    })
  end,
})


command.add(ResultsView, {
  ["project-search:select-previous"] = function()
    local view = core.active_view
    view.selected_idx = math.max(view.selected_idx - 1, 1)
    view:scroll_to_make_selected_visible()
  end,

  ["project-search:select-next"] = function()
    local view = core.active_view
    view.selected_idx = math.min(view.selected_idx + 1, #view.results)
    view:scroll_to_make_selected_visible()
  end,

  ["project-search:open-selected"] = function()
    core.active_view:open_selected_result()
  end,

  ["project-search:refresh"] = function()
    core.active_view:refresh()
  end,

  ["project-search:move-to-previous-page"] = function()
    local view = core.active_view
    view.scroll.to.y = view.scroll.to.y - view.size.y
  end,

  ["project-search:move-to-next-page"] = function()
    local view = core.active_view
    view.scroll.to.y = view.scroll.to.y + view.size.y
  end,

  ["project-search:move-to-start-of-doc"] = function()
    local view = core.active_view
    view.scroll.to.y = 0
  end,

  ["project-search:move-to-end-of-doc"] = function()
    local view = core.active_view
    view.scroll.to.y = view:get_scrollable_size()
  end
})

keymap.add {
  ["f5"]                 = "project-search:refresh",
  ["ctrl+shift+f"]       = "project-search:find",
  ["up"]                 = "project-search:select-previous",
  ["down"]               = "project-search:select-next",
  ["return"]             = "project-search:open-selected",
  ["pageup"]             = "project-search:move-to-previous-page",
  ["pagedown"]           = "project-search:move-to-next-page",
  ["ctrl+home"]          = "project-search:move-to-start-of-doc",
  ["ctrl+end"]           = "project-search:move-to-end-of-doc",
  ["home"]               = "project-search:move-to-start-of-doc",
  ["end"]                = "project-search:move-to-end-of-doc"
}


return projectsearch
