-- this file is used by lite-xl to setup the Lua environment when starting
VERSION = "@PROJECT_VERSION@"
MOD_VERSION = "2"

SCALE = tonumber(os.getenv("LITE_SCALE")) or SCALE
PATHSEP = package.config:sub(1, 1)

EXEDIR = EXEFILE:match("^(.+)[/\\][^/\\]+$")
if MACOS_RESOURCES then
  DATADIR = MACOS_RESOURCES
else
  local prefix = EXEDIR:match("^(.+)[/\\]bin$")
  DATADIR = prefix and (prefix .. '/share/lite-xl') or (EXEDIR .. '/data')
end
USERDIR = (os.getenv("XDG_CONFIG_HOME") and os.getenv("XDG_CONFIG_HOME") .. "/lite-xl")
  or (HOME and (HOME .. '/.config/lite-xl') or (EXEDIR .. '/user'))

package.path = DATADIR .. '/?.lua;' .. package.path
package.path = DATADIR .. '/?/init.lua;' .. package.path
package.path = USERDIR .. '/?.lua;' .. package.path
package.path = USERDIR .. '/?/init.lua;' .. package.path

local dynamic_suffix = MACOS and 'lib' or (WINDOWS and 'dll' or 'so')
package.cpath = DATADIR .. '/?.' .. dynamic_suffix .. ';' .. package.cpath
package.cpath = USERDIR .. '/?.' .. dynamic_suffix .. ';' .. package.cpath
package.searchers[3] = function(modname)
  local s,e = 0
  repeat
    e = package.cpath:find(";", s) or #package.cpath
    local path = package.cpath:sub(s, e - 1):gsub("?", modname:gsub("%.", "/"))
    if system.get_file_info(path) then
      return system.load_native_plugin, path
    end
    s = e + 1
  until s > #package.cpath
end
