local common = {}


function common.is_utf8_cont(char)
  local byte = char:byte()
  return byte >= 0x80 and byte < 0xc0
end


function common.utf8_chars(text)
  return text:gmatch("[\0-\x7f\xc2-\xf4][\x80-\xbf]*")
end


function common.clamp(n, lo, hi)
  return math.max(math.min(n, hi), lo)
end


function common.round(n)
  return n >= 0 and math.floor(n + 0.5) or math.ceil(n - 0.5)
end


function common.lerp(a, b, t)
  if type(a) ~= "table" then
    return a + (b - a) * t
  end
  local res = {}
  for k, v in pairs(b) do
    res[k] = common.lerp(a[k], v, t)
  end
  return res
end


function common.color(str)
  local r, g, b, a = str:match("#(%x%x)(%x%x)(%x%x)")
  if r then
    r = tonumber(r, 16)
    g = tonumber(g, 16)
    b = tonumber(b, 16)
    a = 1
  elseif str:match("rgba?%s*%([%d%s%.,]+%)") then
    local f = str:gmatch("[%d.]+")
    r = (f() or 0)
    g = (f() or 0)
    b = (f() or 0)
    a = f() or 1
  else
    error(string.format("bad color string '%s'", str))
  end
  return r, g, b, a * 0xff
end


local function compare_score(a, b)
  return a.score > b.score
end

local function fuzzy_match_items(items, needle)
  local res = {}
  for _, item in ipairs(items) do
    local score = system.fuzzy_match(tostring(item), needle)
    if score then
      table.insert(res, { text = item, score = score })
    end
  end
  table.sort(res, compare_score)
  for i, item in ipairs(res) do
    res[i] = item.text
  end
  return res
end


function common.fuzzy_match(haystack, needle)
  if type(haystack) == "table" then
    return fuzzy_match_items(haystack, needle)
  end
  return system.fuzzy_match(haystack, needle)
end


function common.fuzzy_match_with_recents(haystack, recents, needle)
  if needle == "" then
    local recents_ext = {}
    for i = 2, #recents do
        table.insert(recents_ext, recents[i])
    end
    table.insert(recents_ext, recents[1])
    local others = common.fuzzy_match(haystack, "")
    for i = 1, #others do
      table.insert(recents_ext, others[i])
    end
    return recents_ext
  else
    return fuzzy_match_items(haystack, needle)
  end
end


function common.path_suggest(text)
  local path, name = text:match("^(.-)([^/\\]*)$")
  local files = system.list_dir(path == "" and "." or path) or {}
  local res = {}
  for _, file in ipairs(files) do
    file = path .. file
    local info = system.get_file_info(file)
    if info then
      if info.type == "dir" then
        file = file .. PATHSEP
      end
      if file:lower():find(text:lower(), nil, true) == 1 then
        table.insert(res, file)
      end
    end
  end
  return res
end


function common.dir_path_suggest(text)
  local path, name = text:match("^(.-)([^/\\]*)$")
  local files = system.list_dir(path == "" and "." or path) or {}
  local res = {}
  for _, file in ipairs(files) do
    file = path .. file
    local info = system.get_file_info(file)
    if info and info.type == "dir" and file:lower():find(text:lower(), nil, true) == 1 then
      table.insert(res, file)
    end
  end
  return res
end


function common.dir_list_suggest(text, dir_list)
  local path, name = text:match("^(.-)([^/\\]*)$")
  local res = {}
  for _, dir_path in ipairs(dir_list) do
    if dir_path:lower():find(text:lower(), nil, true) == 1 then
      table.insert(res, dir_path)
    end
  end
  return res
end


function common.match_pattern(text, pattern, ...)
  if type(pattern) == "string" then
    return text:find(pattern, ...)
  end
  for _, p in ipairs(pattern) do
    local s, e = common.match_pattern(text, p, ...)
    if s then return s, e end
  end
  return false
end


function common.draw_text(font, color, text, align, x,y,w,h)
  local tw, th = font:get_width(text), font:get_height(text)
  if align == "center" then
    x = x + (w - tw) / 2
  elseif align == "right" then
    x = x + (w - tw)
  end
  y = common.round(y + (h - th) / 2)
  return renderer.draw_text(font, text, x, y, color), y + th
end


function common.bench(name, fn, ...)
  local start = system.get_time()
  local res = fn(...)
  local t = system.get_time() - start
  local ms = t * 1000
  local per = (t / (1 / 60)) * 100
  print(string.format("*** %-16s : %8.3fms %6.2f%%", name, ms, per))
  return res
end


function common.serialize(val)
  if type(val) == "string" then
    return string.format("%q", val)
  elseif type(val) == "table" then
    local t = {}
    for k, v in pairs(val) do
      table.insert(t, "[" .. common.serialize(k) .. "]=" .. common.serialize(v))
    end
    return "{" .. table.concat(t, ",") .. "}"
  end
  return tostring(val)
end


function common.basename(path)
  -- a path should never end by / or \ except if it is '/' (unix root) or
  -- 'X:\' (windows drive)
  return path:match("[^\\/]+$") or path
end


function common.home_encode(text)
  if HOME then
    local n = #HOME
    if text:sub(1, n) == HOME and text:sub(n + 1, n + 1):match("[/\\\\]") then
      return "~" .. text:sub(n + 1)
    end
  end
  return text
end


function common.home_encode_list(paths)
  local t = {}
  for i = 1, #paths do
    t[i] = common.home_encode(paths[i])
  end
  return t
end


function common.home_expand(text)
  return HOME and text:gsub("^~", HOME) or text
end


function common.normalize_path(filename)
  if PATHSEP == '\\' then
    filename = filename:gsub('[/\\]', '\\')
    local drive, rem = filename:match('^([a-zA-Z])(:.*)')
    return drive and drive:upper() .. rem or filename
  end
  return filename
end


return common
