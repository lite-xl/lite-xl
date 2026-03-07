local common = require "core.common"
local Font = {}
Font.__index = Font

-- This value seems to yield a check every 15 seconds or so on an average document.
local CHECK_THRESHOLD = 1000000

function Font.load(path, options)
  local self = {}
  setmetatable(self, Font)
  -- default options should not change after font creation
  self.default_options = common.merge({
    size = 15,
    antialiasing = "subpixel",
    hinting = "slight",
    tab_size = 4
  }, options or {})
  self.path = path
  self.check_counter = 0
  self.fonts = {}
  self.used = {}
  return self
end

function Font:cache(size, options)
  self.check_counter = self.check_counter + 1
  if self.check_counter > CHECK_THRESHOLD then
    -- just check to through the fonts to see if they've all got flags. if they don't, remove them from the map,
    -- and reset the flags for those that remain
    for k, font in pairs(self.fonts) do if not self.used[font] then self.fonts[k] = nil end end
    self.used = {}
    self.check_counter = 0 
  end
  if not size then size = self.default_options.size end
  size = size * SCALE
  if not options and self.fonts[size] then self.used[self.fonts[size]] = true return self.fonts[size] end
  local key
  if options then
    key = size .. (options.antialiasing or self.default_options.antialiasing) .. (options.hinting or self.default_options.hinting) .. (options.bold and 1 or 0) .. (options.italic and 1 or 0) .. (options.underline and 1 or 0)
  else
    key = size .. self.default_options.antialiasing .. self.default_options.hinting
  end
  if not self.fonts[key] then
    self.fonts[key] = renderer.font.load(self.path, size, common.merge(self.default_options, options))
    self.fonts[key]:set_tab_size(self.default_options.tab_size)
    self.fonts[size] = self.fonts[key]
  end
  self.used[self.fonts[key]] = true
  return self.fonts[key]
end

function Font:get_width(text, size)
  return self:cache(size):get_width(text)
end

function Font:get_height(size)
  return self:cache(size):get_height()
end

function Font:draw(text, x, y, color, size, options) 
  return renderer.draw_text(self:cache(size, options), text, x, y, color)
end

function Font:set_tab_size(size)
  self.default_options.tab_size = size
  for i,v in pairs(self.fonts) do
    v:set_tab_size(size)
  end
end

Font.group = {}
Font.group.__index = Font.group
function Font.group.new(fonts)
  local self = {}
  self.groups = {}
  self.fonts = fonts
  setmetatable(self, Font.group)
  return self
end

function Font.group:cache(size, options)
  if not options and self.groups[size] then return self.groups[size] end
  local key = (size or self.fonts[1].default_options.size)*SCALE .. (options.antialiasing or self.fonts[1].default_options.antialiasing) .. (options.hinting or self.fonts[1].default_options.hinting)
  if not self.groups[key] then
    local t = {}
    for i,v in ipairs(self.fonts) do table.insert(t, v:cache(size, options)) end
    self.groups[key] = renderer.font.group(t)
    self.groups[size] = self.groups[key]
  end
  return self.groups[key]
end


function Font.group:draw(text, x, y, color, size, options) 
  return renderer.draw_text(self:cache(size, options), text, x, y, color)
end

return Font
