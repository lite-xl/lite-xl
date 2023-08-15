-- this file is used by lite-xl to setup the Lua environment when starting
VERSION = "@PROJECT_VERSION@"
MOD_VERSION_MAJOR = 3
MOD_VERSION_MINOR = 0
MOD_VERSION_PATCH = 0
MOD_VERSION_STRING = string.format("%d.%d.%d", MOD_VERSION_MAJOR, MOD_VERSION_MINOR, MOD_VERSION_PATCH)

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

local suffix = PLATFORM == "Windows" and 'dll' or 'so'
package.cpath =
  USERDIR .. '/?.' .. ARCH .. "." .. suffix .. ";" ..
  USERDIR .. '/?/init.' .. ARCH .. "." .. suffix .. ";" ..
  USERDIR .. '/?.' .. suffix .. ";" ..
  USERDIR .. '/?/init.' .. suffix .. ";" ..
  DATADIR .. '/?.' .. ARCH .. "." .. suffix .. ";" ..
  DATADIR .. '/?/init.' .. ARCH .. "." .. suffix .. ";" ..
  DATADIR .. '/?.' .. suffix .. ";" ..
  DATADIR .. '/?/init.' .. suffix .. ";"

package.native_plugins = {}

local function sanitize_entrypoint(name)
  return name:match("[^%-]*"):gsub("%.", "_")
end

local function load_function(modname, path)
  local err_msg = {}
  local entrypoint = sanitize_entrypoint(modname)
  for prefix in ipairs { "luaopen_lite_xl_", "luaopen_" } do
    local fn, err = system.loadlib(path, prefix .. entrypoint, prefix == "luaopen_lite_xl_")
    if not fn then
      err_msg[#err_msg+1] = string.format("%s:%s%s: %s", path, prefix, entrypoint, err)
    else
      return fn
    end
  end
  return "no symbol '" .. table.concat(err_msg, "'\n\tno symbol '")
end

---The normal C library searcher, implemented with system.loadlib.
local function clib_searcher(modname)
  local path, err = package.searchpath(modname, package.cpath)
  return (path and load_function(modname, path) or err), path
end

---The normal C root (all-in-one) searcher, implemented with system.loadlib.
local function croot_searcher(modname)
  local root = modname:match("^[^%.]*")
  local path, err = package.searchpath(root, package.cpath)
  return (path and load_function(modname, path) or err), path
end

---Lite XL's own C library searcher.
---This searcher searches for the library file normally, but only uses the last part of the module to resolve symbols.
local function lite_xl_searcher(modname)
  local mod = modname:match("[^%.]*$")
  local path, err = package.searchpath(modname, package.cpath)
  return (path and load_function(mod, path) or err), path
end

package.searchers = { package.searchers[1], package.searchers[2], clib_searcher, croot_searcher, lite_xl_searcher }

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
