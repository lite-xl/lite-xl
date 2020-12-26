local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"

config.treeview_size = 200 * SCALE

local function get_depth(filename)
  local n = 1
  for sep in filename:gmatch("[\\/]") do
    n = n + 1
  end
  return n
end


local TreeView = View:extend()

function TreeView:new()
  TreeView.super.new(self)
  self.scrollable = true
  self.visible = true
  self.init_size = true
  self.cache = {}
  self.last = {}
end


local function relative_filename(filename, dirname)
  local n = #dirname
  if filename:sub(1, n) == dirname then
    return filename:sub(n + 1):match('[/\\](.*)')
  end
end


local function belongs_to_directory(item, dirname)
  return relative_filename(item.filename, dirname)
end


function TreeView:get_cached(item, dirname)
  local dir_cache = self.cache[dirname]
  if not dir_cache then
    dir_cache = {}
    self.cache[dirname] = dir_cache
  end
  local t = dir_cache[item.filename]
  if not t then
    t = {}
    local rel = relative_filename(item.filename, dirname)
    -- FIXME: rel should never be nil here. to be verified.
    if item.top_dir then
      t.filename = item.filename:match("[^\\/]+$")
      t.depth = 0
    else
      t.filename = rel or item.filename
      t.depth = get_depth(t.filename)
    end
    t.abs_filename = item.filename
    t.name = t.filename:match("[^\\/]+$")
    t.type = item.type
    dir_cache[item.filename] = t
  end
  return t
end


function TreeView:get_name()
  return "Project"
end


function TreeView:get_item_height()
  return style.font:get_height() + style.padding.y
end


function TreeView:check_cache()
  -- invalidate cache's skip values if project_files has changed
  for i = 1, #core.project_directories do
    local dir = core.project_directories[i]
    local last_files = self.last[dir.filename]
    if not last_files then
      self.last[dir.filename] = dir.files
    else
      if dir.files ~= last_files then
        for _, v in pairs(self.cache[dir.filename]) do
          v.skip = nil
        end
        self.last[dir.filename] = dir.files
        -- self.last_project_files = core.project_files
      end
    end
  end
end


function TreeView:each_item()
  return coroutine.wrap(function()
    self:check_cache()
    local ox, oy = self:get_content_offset()
    local y = oy + style.padding.y
    local w = self.size.x
    local h = self:get_item_height()

    for k = 1, #core.project_directories do
      local dir = core.project_directories[k]
      local dir_cached = self:get_cached(dir.item, dir.filename)
      local dir_name = dir.filename
      coroutine.yield(dir_cached, ox, y, w, h)
      y = y + h
      local i = 1
      while i <= #dir.files do
        local item = dir.files[i]
        -- if belongs_to_directory(item, dir_name) then
        local cached = self:get_cached(item, dir_name)

        coroutine.yield(cached, ox, y, w, h)
        y = y + h
        i = i + 1

        if not cached.expanded then
          if cached.skip then
            i = cached.skip
          else
            local depth = cached.depth
            while i <= #dir.files do
              local filename = relative_filename(dir.files[i].filename, dir_name)
              if get_depth(filename) <= depth then break end
              i = i + 1
            end
            cached.skip = i
          end
        end
      end -- while files
    end -- for directories
  end)
end


function TreeView:on_mouse_moved(px, py)
  self.hovered_item = nil
  for item, x,y,w,h in self:each_item() do
    if px > x and py > y and px <= x + w and py <= y + h then
      self.hovered_item = item
      break
    end
  end
end


function TreeView:on_mouse_pressed(button, x, y)
  if not self.hovered_item then
    return
  elseif self.hovered_item.type == "dir" then
    self.hovered_item.expanded = not self.hovered_item.expanded
  else
    core.try(function()
      core.root_view:open_doc(core.open_doc(self.hovered_item.filename))
    end)
  end
end


function TreeView:update()
  -- update width
  local dest = self.visible and config.treeview_size or 0
  if self.init_size then
    self.size.x = dest
    self.init_size = false
  else
    self:move_towards(self.size, "x", dest)
  end

  TreeView.super.update(self)
end


function TreeView:draw()
  self:draw_background(style.background2)

  local icon_width = style.icon_font:get_width("D")
  local spacing = style.font:get_width(" ") * 2

  local doc = core.active_view.doc
  local active_filename = doc and system.absolute_path(doc.filename or "")

  for item, x,y,w,h in self:each_item() do
    local color = style.text

    -- highlight active_view doc
    if item.abs_filename == active_filename then
      color = style.accent
    end

    -- hovered item background
    if item == self.hovered_item then
      renderer.draw_rect(x, y, w, h, style.line_highlight)
      color = style.accent
    end

    -- icons
    x = x + item.depth * style.padding.x + style.padding.x
    if item.type == "dir" then
      local icon1 = item.expanded and "-" or "+"
      local icon2 = item.expanded and "D" or "d"
      common.draw_text(style.icon_font, color, icon1, nil, x, y, 0, h)
      x = x + style.padding.x
      common.draw_text(style.icon_font, color, icon2, nil, x, y, 0, h)
      x = x + icon_width
    else
      x = x + style.padding.x
      common.draw_text(style.icon_font, color, "f", nil, x, y, 0, h)
      x = x + icon_width
    end

    -- text
    x = x + spacing
    x = common.draw_text(style.font, color, item.name, nil, x, y, 0, h)
  end
end


-- init
local view = TreeView()
local node = core.root_view:get_active_node()
node:split("left", view, true)

-- register commands and keymap
command.add(nil, {
  ["treeview:toggle"] = function()
    view.visible = not view.visible
  end,
})

keymap.add { ["ctrl+\\"] = "treeview:toggle" }
