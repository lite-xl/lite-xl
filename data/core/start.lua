-- this file is used by lite-xl to setup the Lua environment
-- when starting
VERSION = "1.16.5"

SCALE = tonumber(os.getenv("LITE_SCALE")) or SCALE
PATHSEP = package.config:sub(1, 1)
EXEDIR = EXEFILE:match("^(.+)[/\\][^/\\]+$")

local prefix = EXEDIR:match("^(.+)[/\\]bin$")
DATADIR = prefix and (prefix .. '/share/lite-xl') or (EXEDIR .. '/data')
USERDIR = HOME and (HOME .. '/.config/lite-xl') or (EXEDIR .. '/user')

package.path = DATADIR .. '/?.lua;' .. package.path
package.path = DATADIR .. '/?/init.lua;' .. package.path
package.path = USERDIR .. '/?.lua;' .. package.path
package.path = USERDIR .. '/?/init.lua;' .. package.path

