local function env_key(str)
  if PLATFORM == "Windows" then return str:upper() else return str end
end

---Sorts the environment variable by its key, converted to uppercase.
---This is only needed on Windows.
local function compare_env(a, b)
  return env_key(a:match("([^=]*)=")) < env_key(b:match("([^=]*)="))
end

local old_start = process.start
function process.start(command, options)
  assert(type(command) == "table" or type(command) == "string", "invalid argument #1 to process.start(), expected string or table, got "..type(command))
  assert(type(options) == "table" or type(options) == "nil", "invalid argument #2 to process.start(), expected table or nil, got "..type(options))
  if PLATFORM == "Windows" then
    if type(command) == "table" then
      -- escape the arguments into a command line string
      -- https://github.com/python/cpython/blob/48f9d3e3faec5faaa4f7c9849fecd27eae4da213/Lib/subprocess.py#L531
      local arglist = {}
      for _, v in ipairs(command) do
        local backslash, arg = 0, {}
        for c in v:gmatch(".") do
          if     c == "\\" then backslash = backslash + 1
          elseif c == '"'  then arg[#arg+1] = string.rep("\\", backslash * 2 + 1)..'"'; backslash = 0
          else                  arg[#arg+1] = string.rep("\\", backslash) .. c;         backslash = 0 end
        end
        arg[#arg+1] = string.rep("\\", backslash) -- add remaining backslashes
        if #v == 0 or v:find("[\t\v\r\n ]") then arglist[#arglist+1] = '"'..table.concat(arg, "")..'"'
        else                                     arglist[#arglist+1] = table.concat(arg, "") end
      end
      command = table.concat(arglist, " ")
    end
  else
    command = type(command) == "table" and command or { command }
  end
  if type(options) == "table" and options.env then
    local user_env = options.env --[[@as table]]
    options.env = function(system_env)
      local final_env, envlist = {}, {}
      for k, v in pairs(system_env) do final_env[env_key(k)] = k.."="..v end
      for k, v in pairs(user_env)   do final_env[env_key(k)] = k.."="..v end
      for _, v in pairs(final_env)  do envlist[#envlist+1] = v end
      if PLATFORM == "Windows" then table.sort(envlist, compare_env) end
      return table.concat(envlist, "\0").."\0\0"
    end
  end
  return old_start(command, options)
end

return process
