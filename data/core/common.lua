local common = {}


function common.is_utf8_cont(s, offset)
  local byte = s:byte(offset or 1)
  return byte >= 0x80 and byte < 0xc0
end


function common.utf8_chars(text)
  return text:gmatch("[\0-\x7f\xc2-\xf4][\x80-\xbf]*")
end


function common.clamp(n, lo, hi)
  return math.max(math.min(n, hi), lo)
end


function common.merge(a, b)
  a = type(a) == "table" and a or {}
  local t = {}
  for k, v in pairs(a) do
    t[k] = v
  end
  if b and type(b) == "table" then
    for k, v in pairs(b) do
      t[k] = v
    end
  end
  return t
end


function common.round(n)
  return n >= 0 and math.floor(n + 0.5) or math.ceil(n - 0.5)
end


function common.find_index(tbl, prop)
  for i, o in ipairs(tbl) do
    if o[prop] then return i end
  end
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


function common.distance(x1, y1, x2, y2)
    return math.sqrt(((x2-x1) ^ 2)+((y2-y1) ^ 2))
end


function common.color(str)
  local r, g, b, a = str:match("^#(%x%x)(%x%x)(%x%x)(%x?%x?)$")
  if r then
    r = tonumber(r, 16)
    g = tonumber(g, 16)
    b = tonumber(b, 16)
    a = tonumber(a, 16) or 0xff
  elseif str:match("rgba?%s*%([%d%s%.,]+%)") then
    local f = str:gmatch("[%d.]+")
    r = (f() or 0)
    g = (f() or 0)
    b = (f() or 0)
    a = (f() or 1) * 0xff
  else
    error(string.format("bad color string '%s'", str))
  end
  return r, g, b, a
end


function common.splice(t, at, remove, insert)
  insert = insert or {}
  local offset = #insert - remove
  local old_len = #t
  if offset < 0 then
    for i = at - offset, old_len - offset do
      t[i + offset] = t[i]
    end
  elseif offset > 0 then
    for i = old_len, at, -1 do
      t[i + offset] = t[i]
    end
  end
  for i, item in ipairs(insert) do
    t[at + i - 1] = item
  end
end



local function compare_score(a, b)
  return a.score > b.score
end

local function fuzzy_match_items(items, needle, files)
  local res = {}
  for _, item in ipairs(items) do
    local score = system.fuzzy_match(tostring(item), needle, files)
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


function common.fuzzy_match(haystack, needle, files)
  if type(haystack) == "table" then
    return fuzzy_match_items(haystack, needle, files)
  end
  return system.fuzzy_match(haystack, needle, files)
end


function common.fuzzy_match_with_recents(haystack, recents, needle)
  if needle == "" then
    local recents_ext = {}
    for i = 2, #recents do
      table.insert(recents_ext, recents[i])
    end
    table.insert(recents_ext, recents[1])
    local others = common.fuzzy_match(haystack, "", true)
    for i = 1, #others do
      table.insert(recents_ext, others[i])
    end
    return recents_ext
  else
    return fuzzy_match_items(haystack, needle, true)
  end
end


function common.path_suggest(text, root)
  if root and root:sub(-1) ~= PATHSEP then
    root = root .. PATHSEP
  end
  local path, name = text:match("^(.-)([^/\\]*)$")
  -- ignore root if path is absolute
  local is_absolute = common.is_absolute_path(text)
  if not is_absolute then
    if path == "" then
      path = root or "."
    else
      path = (root or "") .. path
    end
  end

  local files = system.list_dir(path) or {}
  if path:sub(-1) ~= PATHSEP then
    path = path .. PATHSEP
  end
  local res = {}
  for _, file in ipairs(files) do
    file = path .. file
    local info = system.get_file_info(file)
    if info then
      if info.type == "dir" then
        file = file .. PATHSEP
      end
      if root then
        -- remove root part from file path
        local s, e = file:find(root, nil, true)
        if s == 1 then
          file = file:sub(e + 1)
        end
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


local function serialize(val, pretty, indent_str, escape, sort, limit, level)
  local space = pretty and " " or ""
  local indent = pretty and string.rep(indent_str, level) or ""
  local newline = pretty and "\n" or ""
  if type(val) == "string" then
    local out = string.format("%q", val)
    if escape then
      out = string.gsub(out, "\\\n", "\\n")
      out = string.gsub(out, "\\7", "\\a")
      out = string.gsub(out, "\\8", "\\b")
      out = string.gsub(out, "\\9", "\\t")
      out = string.gsub(out, "\\11", "\\v")
      out = string.gsub(out, "\\12", "\\f")
      out = string.gsub(out, "\\13", "\\r")
    end
    return out
  elseif type(val) == "table" then
    -- early exit
    if level >= limit then return tostring(val) end
    local next_indent = pretty and (indent .. indent_str) or ""
    local t = {}
    for k, v in pairs(val) do
      table.insert(t,
        next_indent .. "[" ..
          serialize(k, pretty, indent_str, escape, sort, limit, level + 1) ..
        "]" .. space .. "=" .. space .. serialize(v, pretty, indent_str, escape, sort, limit, level + 1))
    end
    if #t == 0 then return "{}" end
    if sort then table.sort(t) end
    return "{" .. newline .. table.concat(t, "," .. newline) .. newline .. indent .. "}"
  end
  return tostring(val)
end

-- Serialize `val` into a parsable string.
-- Available options
-- * pretty: enable pretty printing
-- * indent_str: indent to use ("  " by default)
-- * escape: use normal escape characters instead of the ones used by string.format("%q", ...)
-- * sort: sort the keys inside tables
-- * limit: limit how deep to serialize
-- * initial_indent: the initial indentation level
function common.serialize(val, opts)
  opts = opts or {}
  local indent_str = opts.indent_str or "  "
  local initial_indent = opts.initial_indent or 0
  local indent = opts.pretty and string.rep(indent_str, initial_indent) or ""
  local limit = (opts.limit or math.huge) + initial_indent
  return indent .. serialize(val, opts.pretty, indent_str,
                   opts.escape, opts.sort, limit, initial_indent)
end


function common.basename(path)
  -- a path should never end by / or \ except if it is '/' (unix root) or
  -- 'X:\' (windows drive)
  return path:match("[^\\/]+$") or path
end


-- can return nil if there is no directory part in the path
function common.dirname(path)
  return path:match("(.+)[\\/][^\\/]+$")
end


function common.home_encode(text)
  if HOME and string.find(text, HOME, 1, true) == 1 then
    local dir_pos = #HOME + 1
    -- ensure we don't replace if the text is just "$HOME" or "$HOME/" so
    -- it must have a "/" following the $HOME and some characters following.
    if string.find(text, PATHSEP, dir_pos, true) == dir_pos and #text > dir_pos then
      return "~" .. text:sub(dir_pos)
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


local function split_on_slash(s, sep_pattern)
  local t = {}
  if s:match("^[/\\]") then
    t[#t + 1] = ""
  end
  for fragment in string.gmatch(s, "([^/\\]+)") do
    t[#t + 1] = fragment
  end
  return t
end


-- The filename argument given to the function is supposed to
-- come from system.absolute_path and as such should be an
-- absolute path without . or .. elements.
-- This function exists because on Windows the drive letter returned
-- by system.absolute_path is sometimes with a lower case and sometimes
-- with an upper case to we normalize to upper case.
function common.normalize_volume(filename)
  if not filename then return end
  if PATHSEP == '\\' then
    local drive, rem = filename:match('^([a-zA-Z]:\\)(.*)')
    if drive then
      return drive:upper() .. rem
    end
  end
  return filename
end


function common.normalize_path(filename)
  if not filename then return end
  local volume
  if PATHSEP == '\\' then
    filename = filename:gsub('[/\\]', '\\')
    local drive, rem = filename:match('^([a-zA-Z]:\\)(.*)')
    if drive then
      volume, filename = drive:upper(), rem
    else
      drive, rem = filename:match('^(\\\\[^\\]+\\[^\\]+\\)(.*)')
      if drive then
        volume, filename = drive, rem
      end
    end
  else
    local relpath = filename:match('^/(.+)')
    if relpath then
      volume, filename = "/", relpath
    end
  end
  local parts = split_on_slash(filename, PATHSEP)
  local accu = {}
  for _, part in ipairs(parts) do
    if part == '..' then
      if #accu > 0 and accu[#accu] ~= ".." then
        table.remove(accu)
      elseif volume then
        error("invalid path " .. volume .. filename)
      else
        table.insert(accu, part)
      end
    elseif part ~= '.' then
      table.insert(accu, part)
    end
  end
  local npath = table.concat(accu, PATHSEP)
  return (volume or "") .. (npath == "" and PATHSEP or npath)
end


function common.is_absolute_path(path)
  return path:sub(1, 1) == PATHSEP or path:match("^(%a):\\")
end


function common.path_belongs_to(filename, path)
  return string.find(filename, path .. PATHSEP, 1, true) == 1
end


function common.relative_path(ref_dir, dir)
  local drive_pattern = "^(%a):\\"
  local drive, ref_drive = dir:match(drive_pattern), ref_dir:match(drive_pattern)
  if drive and ref_drive and drive ~= ref_drive then
    -- Windows, different drives, system.absolute_path fails for C:\..\D:\
    return dir
  end
  local ref_ls = split_on_slash(ref_dir)
  local dir_ls = split_on_slash(dir)
  local i = 1
  while i <= #ref_ls do
    if dir_ls[i] ~= ref_ls[i] then
      break
    end
    i = i + 1
  end
  local ups = ""
  for k = i, #ref_ls do
    ups = ups .. ".." .. PATHSEP
  end
  local rel_path = ups .. table.concat(dir_ls, PATHSEP, i)
  return rel_path ~= "" and rel_path or "."
end


function common.mkdirp(path)
  local stat = system.get_file_info(path)
  if stat and stat.type then
    return false, "path exists", path
  end
  local subdirs = {}
  while path and path ~= "" do
    local success_mkdir = system.mkdir(path)
    if success_mkdir then break end
    local updir, basedir = path:match("(.*)[/\\](.+)$")
    table.insert(subdirs, 1, basedir or path)
    path = updir
  end
  for _, dirname in ipairs(subdirs) do
    path = path and path .. PATHSEP .. dirname or dirname
    if not system.mkdir(path) then
      return false, "cannot create directory", path
    end
  end
  return true
end

function common.rm(path, recursively)
  local stat = system.get_file_info(path)
  if not stat or (stat.type ~= "file" and stat.type ~= "dir") then
    return false, "invalid path given", path
  end

  if stat.type == "file" then
    local removed, error = os.remove(path)
    if not removed then
      return false, error, path
    end
  else
    local contents = system.list_dir(path)
    if #contents > 0 and not recursively then
      return false, "directory is not empty", path
    end

    for _, item in pairs(contents) do
      local item_path = path .. PATHSEP .. item
      local item_stat = system.get_file_info(item_path)

      if not item_stat then
        return false, "invalid file encountered", item_path
      end

      if item_stat.type == "dir" then
        local deleted, error, ipath = common.rm(item_path, recursively)
        if not deleted then
          return false, error, ipath
        end
      elseif item_stat.type == "file" then
        local removed, error = os.remove(item_path)
        if not removed then
          return false, error, item_path
        end
      end
    end

    local removed, error = system.rmdir(path)
    if not removed then
      return false, error, path
    end
  end

  return true
end


return common
