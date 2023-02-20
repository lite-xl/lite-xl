-- replaces a bunch of lua pattern with their escapes
local function escape(str)
  local r = str:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
  return r
end

-- replaces % with %%
local function escape_replace(str)
  local r = str:gsub("%%", "%%%%")
  return r
end

-- implementation of package.searchpath that uses io.open (which we've patched) to search
function package.searchpath(name, path, pathsep, dirsep)
  -- gets the default dirsep, pathsep and mark from package.config so we can patch properly
  local default_dirsep, default_pathsep, default_mark, _, _ = string.match(package.config, "^([^\n]*)\n([^\n]*)\n([^\n]*)\n")

  pathsep = (pathsep and pathsep or "."):sub(1, 1)
  dirsep = dirsep and dirsep or default_dirsep

  -- replace pathsep in name with dirsep (if any)
  name = name:gsub(escape(pathsep), escape_replace(dirsep));

  -- replace marks (usually ?) with names
  path = path:gsub(escape(default_mark), escape_replace(name))

  for p in path:gmatch("([^" .. escape(default_pathsep) .. "]*)") do
    -- try to open each path
    local f = io.open(p, "r")
    if f then
      f:close()
      return p
    end
  end

  -- return an error message
  return nil, "no file '" .. path:gsub(escape(default_pathsep), "'\n\tno file '") .. "'"
end

package.loadlib = system.loadlib
