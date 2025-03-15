local common = {}


---Checks if the byte at offset is a UTF-8 continuation byte.
---
---UTF-8 encodes code points in 1 to 4 bytes.
---For a multi-byte sequence, each byte following the start byte is a continuation byte.
---@param s string
---@param offset? integer The offset of the string to start searching. Defaults to 1.
---@return boolean
function common.is_utf8_cont(s, offset)
  local byte = s:byte(offset or 1)
  return byte >= 0x80 and byte < 0xc0
end


---Returns an iterator that yields a UTF-8 character on each iteration.
---@param text string
---@return fun(): string
function common.utf8_chars(text)
  return text:gmatch("[\0-\x7f\xc2-\xf4][\x80-\xbf]*")
end


---Clamps the number n between lo and hi.
---@param n number
---@param lo number
---@param hi number
---@return number
function common.clamp(n, lo, hi)
  return math.max(math.min(n, hi), lo)
end


---Returns a new table containing the contents of b merged into a.
---@param a table|nil
---@param b table?
---@return table
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


---Returns the value of a number rounded to the nearest integer.
---@param n number
---@return number
function common.round(n)
  return n >= 0 and math.floor(n + 0.5) or math.ceil(n - 0.5)
end


---Returns the first index where a subtable in tbl has prop set.
---If none is found, nil is returned.
---@param tbl table
---@param prop any
---@return number|nil
function common.find_index(tbl, prop)
  for i, o in ipairs(tbl) do
    if o[prop] then return i end
  end
end


---Returns a value between a and b on a linear scale, based on the
---interpolation point t.
---
---If a and b are tables, a table containing the result for all the
---elements in a and b is returned.
---@param a number
---@param b number
---@param t number
---@return number
---@overload fun(a: table, b: table, t: number): table
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


---Returns the euclidean distance between two points.
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return number
function common.distance(x1, y1, x2, y2)
    return math.sqrt(((x2-x1) ^ 2)+((y2-y1) ^ 2))
end


---Parses a CSS color string.
---
---Only these formats are supported:
---* `rgb(r, g, b)`
---* `rgba(r, g, b, a)`
---* `#rrggbbaa`
---* `#rrggbb`
---@param str string
---@return number r
---@return number g
---@return number b
---@return number a
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


---Splices a numerically indexed table.
---This function mutates the original table.
---@param t any[]
---@param at number Index at which to start splicing.
---@param remove number Number of elements to remove.
---@param insert? any[] A table containing elements to insert after splicing.
function common.splice(t, at, remove, insert)
  assert(remove >= 0, "bad argument #3 to 'splice' (non-negative value expected)")
  insert = insert or {}
  local len = #insert
  if remove ~= len then table.move(t, at + remove, #t + remove, at + len) end
  table.move(insert, 1, len, at, t)
end


local function compare_score(a, b)
  return a.score > b.score
end

local function fuzzy_match_items(items, needle, files)
  local res = {}
  needle = (PLATFORM == "Windows" and files) and needle:gsub('/', PATHSEP) or needle
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


---Performs fuzzy matching.
---
---If the haystack is a string, a score ranging from 0 to 1 is returned. </br>
---If the haystack is a table, a table containing the haystack sorted in ascending
---order of similarity is returned.
---@param haystack string
---@param needle string
---@param files boolean If true, the matching process will be performed in reverse to better match paths.
---@return number
---@overload fun(haystack: string[], needle: string, files: boolean): string[]
function common.fuzzy_match(haystack, needle, files)
  if type(haystack) == "table" then
    return fuzzy_match_items(haystack, needle, files)
  end
  return system.fuzzy_match(haystack, needle, files)
end


---Performs fuzzy matching and returns recently used strings if needed.
---
---If the needle is empty, then a list of recently used strings
---are added to the result, followed by strings from the haystack.
---@param haystack string[]
---@param recents string[]
---@param needle string
---@return string[]
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


---Returns a list of paths that are relative to the input path.
---
---If a root directory is specified, the function returns paths
---that are relative to the root directory.
---@param text string The input path.
---@param root? string The root directory.
---@return string[]
function common.path_suggest(text, root)
  if root and root:sub(-1) ~= PATHSEP then
    root = root .. PATHSEP
  end

  local pathsep = PATHSEP
  if PLATFORM == "Windows" then
    pathsep = "\\/"
  end
  local path = text:match("^(.-)[^"..pathsep.."]*$")
  local clean_dotslash = false
  -- ignore root if path is absolute
  local is_absolute = common.is_absolute_path(text)
  if not is_absolute then
    if path == "" then
      path = root or "."
      clean_dotslash = not root
    else
      path = (root or "") .. path
    end
  end

  -- Only in Windows allow using both styles of PATHSEP
  if (PATHSEP == "\\" and not string.match(path:sub(-1), "[\\/]")) or
     (PATHSEP ~= "\\" and path:sub(-1) ~= PATHSEP) then
    path = path .. PATHSEP
  end
  local files = system.list_dir(path) or {}
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
      elseif clean_dotslash then
        -- remove added dot slash
        local s, e = file:find("." .. PATHSEP, nil, true)
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


---Returns a list of directories that are related to a path.
---@param text string The input path.
---@return string[]
function common.dir_path_suggest(text)
  local path, name = text:match("^(.-)([^"..PATHSEP.."]*)$")
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


---Filters a list of paths to find those that are related to the input path.
---@param text string The input path.
---@param dir_list string[] A list of paths to filter.
---@return string[]
function common.dir_list_suggest(text, dir_list)
  local path, name = text:match("^(.-)([^"..PATHSEP.."]*)$")
  local res = {}
  for _, dir_path in ipairs(dir_list) do
    if dir_path:lower():find(text:lower(), nil, true) == 1 then
      table.insert(res, dir_path)
    end
  end
  return res
end


---Matches a string against a list of patterns.
---
---If a match was found, its start and end index is returned.
---Otherwise, false is returned.
---@param text string
---@param pattern string|string[]
---@param ... any Other options for string.find().
---@return number|boolean start_index
---@return number|nil end_index
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


---Draws text onto the window.
---The function returns the X and Y coordinates of the bottom-right
---corner of the text.
---@param font renderer.font
---@param color renderer.color
---@param text string
---@param align string
---| '"left"'   # Align text to the left of the bounding box
---| '"right"'  # Align text to the right of the bounding box
---| '"center"' # Center text in the bounding box
---@param x number
---@param y number
---@param w number
---@param h number
---@return number x_advance
---@return number y_advance
function common.draw_text(font, color, text, align, x,y,w,h)
  local tw, th = font:get_width(text), font:get_height()
  if align == "center" then
    x = x + (w - tw) / 2
  elseif align == "right" then
    x = x + (w - tw)
  end
  y = common.round(y + (h - th) / 2)
  return renderer.draw_text(font, text, x, y, color), y + th
end


---Prints the execution time of a function.
---
---The execution time and percentage of frame time
---for the function is printed to standard output. </br>
---The frame rate is always assumed to be 60 FPS, thus
---a value of 100% would mean that the benchmark took
---1/60 of a second to execute.
---@param name string
---@param fn fun(...: any): any
---@return any # The result returned by the function
function common.bench(name, fn, ...)
  local start = system.get_time()
  local res = fn(...)
  local t = system.get_time() - start
  local ms = t * 1000
  local per = (t / (1 / 60)) * 100
  print(string.format("*** %-16s : %8.3fms %6.2f%%", name, ms, per))
  return res
end

-- From gvx/Ser
local oddvals = {[tostring(1/0)] = "1/0", [tostring(-1/0)] = "-1/0", [tostring(-(0/0))] = "-(0/0)", [tostring(0/0)] = "0/0"}

local function serialize(val, pretty, indent_str, escape, sort, limit, level)
  local space = pretty and " " or ""
  local indent = pretty and string.rep(indent_str, level) or ""
  local newline = pretty and "\n" or ""
  local ty = type(val)
  if ty == "string" then
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
  elseif ty == "table" then
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
  if ty == "number" then
    -- tostring is locale-dependent, so we need to replace an eventual `,` with `.`
    local res, _ = tostring(val):gsub(",", ".")
    -- handle inf/nan
    return oddvals[res] or res
  end
  return tostring(val)
end


---@class common.serializeoptions
---@field pretty boolean Enables pretty printing.
---@field indent_str string The indentation character to use. Defaults to `"  "`.
---@field escape boolean Uses normal escape characters ("\n") instead of decimal escape sequences ("\10").
---@field limit number Limits the depth when serializing nested tables. Defaults to `math.huge`.
---@field sort boolean Sorts the output if it is a sortable table.
---@field initial_indent number The initial indentation level. Defaults to 0.

---Serializes a value into a Lua string that is loadable with load().
---
---Only these basic types are supported:
---* nil
---* boolean
---* number (except very large numbers and special constants, e.g. `math.huge`, `inf` and `nan`)
---* integer
---* string
---* table
---
---@param val any
---@param opts? common.serializeoptions
---@return string
function common.serialize(val, opts)
  opts = opts or {}
  local indent_str = opts.indent_str or "  "
  local initial_indent = opts.initial_indent or 0
  local indent = opts.pretty and string.rep(indent_str, initial_indent) or ""
  local limit = (opts.limit or math.huge) + initial_indent
  return indent .. serialize(val, opts.pretty, indent_str,
                   opts.escape, opts.sort, limit, initial_indent)
end


---Returns the last portion of a path.
---@param path string
---@return string
function common.basename(path)
  -- a path should never end by / or \ except if it is '/' (unix root) or
  -- 'X:\' (windows drive)
  return path:match("[^"..PATHSEP.."]+$") or path
end


---Returns the directory name of a path.
---If the path doesn't have a directory, this function may return nil.
---@param path string
---@return string|nil
function common.dirname(path)
  return path:match("(.+)["..PATHSEP.."][^"..PATHSEP.."]+$")
end


---Returns a path where the user's home directory is replaced by `"~"`.
---@param text string
---@return string
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


---Returns a list of paths where the user's home directory is replaced by `"~"`.
---@param paths string[] A list of paths to encode
---@return string[]
function common.home_encode_list(paths)
  local t = {}
  for i = 1, #paths do
    t[i] = common.home_encode(paths[i])
  end
  return t
end


---Expands the `"~"` prefix in a path into the user's home directory.
---This function is not guaranteed to return an absolute path.
---@param text string
---@return string
function common.home_expand(text)
  return HOME and text:gsub("^~", HOME) or text
end


local function split_on_slash(s, sep_pattern)
  local t = {}
  if s:match("^["..PATHSEP.."]") then
    t[#t + 1] = ""
  end
  for fragment in string.gmatch(s, "([^"..PATHSEP.."]+)") do
    t[#t + 1] = fragment
  end
  return t
end


---Normalizes the drive letter in a Windows path to uppercase.
---This function expects an absolute path, e.g. a path from `system.absolute_path`.
---
---This function is needed because the path returned by `system.absolute_path`
---may contain drive letters in upper or lowercase.
---@param filename string|nil The input path.
---@return string|nil
function common.normalize_volume(filename)
  if not filename then return end
  if PATHSEP == '\\' then
    local drive, rem = filename:match('^([a-zA-Z]:\\)(.-)'..PATHSEP..'?$')
    if drive then
      return drive:upper() .. rem
    end
  end
  return filename
end


---Normalizes a path into the same format across platforms.
---
---On Windows, all drive letters are converted to uppercase.
---UNC paths with drive letters are converted back to ordinary Windows paths.
---All path separators (`"/"`, `"\\"`) are converted to platform-specific ones.
---@param filename string|nil
---@return string|nil
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


---Checks whether a path is absolute or relative.
---@param path string
---@return boolean
function common.is_absolute_path(path)
  return path:sub(1, 1) == PATHSEP or path:match("^(%a):\\")
end


---Checks whether a path belongs to a parent directory.
---@param filename string The path to check.
---@param path string The parent path.
---@return boolean
function common.path_belongs_to(filename, path)
  return string.find(filename, path .. PATHSEP, 1, true) == 1
end


---Checks whether a path is relative to another path.
---@param ref_dir string The path to check against.
---@param dir string The input path.
---@return boolean
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


---Creates a directory recursively if necessary.
---@param path string
---@return boolean success
---@return string|nil error
---@return string|nil path The path where an error occured.
function common.mkdirp(path)
  local stat = system.get_file_info(path)
  if stat and stat.type then
    return false, "path exists", path
  end
  local subdirs = {}
  while path and path ~= "" do
    local success_mkdir = system.mkdir(path)
    if success_mkdir then break end
    local updir, basedir = path:match("(.*)["..PATHSEP.."](.+)$")
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


---Removes a path.
---@param path string
---@param recursively boolean If true, the function will attempt to remove everything in the specified path.
---@return boolean success
---@return string|nil error
---@return string|nil path The path where the error occured.
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
