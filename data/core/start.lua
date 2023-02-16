-- this file is used by lite-xl to setup the Lua environment when starting
VERSION = "@PROJECT_VERSION@"
MOD_VERSION_MAJOR = 3
MOD_VERSION_MINOR = 0
MOD_VERSION_PATCH = 0
MOD_VERSION_STRING = string.format("%d.%d.%d", MOD_VERSION_MAJOR, MOD_VERSION_MINOR, MOD_VERSION_PATCH)

-- patch io and os library before we use them
require("utf8_io").enable()
require("utf8_os").enable()

SCALE = tonumber(os.getenv("LITE_SCALE") or os.getenv("GDK_SCALE") or os.getenv("QT_SCALE_FACTOR")) or SCALE
PATHSEP = package.config:sub(1, 1)

EXEDIR = EXEFILE:match("^(.+)[/\\][^/\\]+$")
if MACOS_RESOURCES then
  DATADIR = MACOS_RESOURCES
else
  local prefix = os.getenv('LITE_PREFIX') or EXEDIR:match("^(.+)[/\\]bin$")
  DATADIR = prefix and (prefix .. PATHSEP .. 'share' .. PATHSEP .. 'lite-xl') or (EXEDIR .. PATHSEP .. 'data')
end
USERDIR = (system.get_file_info(EXEDIR .. PATHSEP .. 'user') and (EXEDIR .. PATHSEP .. 'user'))
       or os.getenv("LITE_USERDIR")
       or ((os.getenv("XDG_CONFIG_HOME") and os.getenv("XDG_CONFIG_HOME") .. PATHSEP .. "lite-xl"))
       or (HOME and (HOME .. PATHSEP .. '.config' .. PATHSEP .. 'lite-xl'))

package.path = DATADIR .. '/?.lua;'
package.path = DATADIR .. '/?/init.lua;' .. package.path
package.path = USERDIR .. '/?.lua;' .. package.path
package.path = USERDIR .. '/?/init.lua;' .. package.path

local suffix = PLATFORM == "Mac OS X" and 'lib' or (PLATFORM == "Windows" and 'dll' or 'so')
package.cpath =
  USERDIR .. '/?.' .. ARCH .. "." .. suffix .. ";" ..
  USERDIR .. '/?/init.' .. ARCH .. "." .. suffix .. ";" ..
  USERDIR .. '/?.' .. suffix .. ";" ..
  USERDIR .. '/?/init.' .. suffix .. ";" ..
  DATADIR .. '/?.' .. ARCH .. "." .. suffix .. ";" ..
  DATADIR .. '/?/init.' .. ARCH .. "." .. suffix .. ";" ..
  DATADIR .. '/?.' .. suffix .. ";" ..
  DATADIR .. '/?/init.' .. suffix .. ";"

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
local function searchpath(name, path, pathsep, dirsep)
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

package.native_plugins = {}
package.searchers = { package.searchers[1], package.searchers[2], function(modname)
  local path, err = searchpath(modname, package.cpath)
  if not path then return err end
  return system.load_native_plugin, path
end }

table.pack = table.pack or pack or function(...) return {...} end
table.unpack = table.unpack or unpack

bit32 = bit32 or require "core.bit"

require "core.utf8string"

-- Because AppImages change the working directory before running the executable,
-- we need to change it back to the original one.
-- https://github.com/AppImage/AppImageKit/issues/172
-- https://github.com/AppImage/AppImageKit/pull/191
local appimage_owd = os.getenv("OWD")
if os.getenv("APPIMAGE") and appimage_owd then
  system.chdir(appimage_owd)
end
