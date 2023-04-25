-- mod-version:3 -- lite-xl 2.1 -- priority: 1000

local old_font_load = renderer.font.load
function renderer.font.load(path, size, options)
  options = options or {}
  local key = path .. size .. tostring(options.italic or 0) .. tostring(options.bold or 0) .. tostring(options.underline or 0) .. tostring(options.smoothing or 0) .. tostring(options.strikethrough or 0) .. tostring(options.hinting or 0) .. tostring(options.antialiasing or 0)
  return system.cache(key, system.cache(key) or old_font_load(path, size, options))
end

function renderer.font:copy(size, options)
  if type(self) ~= "table" then return renderer.font.load(self:get_path(), size, options) end
  local t = {}
  for i, font in ipairs(self) do
    table.insert(t, font:copy(options))
  end
  return renderer.font.group(t)
end

