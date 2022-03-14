local lua_version = _VERSION:sub(-3)


if lua_version < "5.3" then

   local _G, pairs, require, select, type =
         _G, pairs, require, select, type
   local debug, io = debug, io
   local unpack = lua_version == "5.1" and unpack or table.unpack

   local M = require("compat.module")

   -- select the most powerful getmetatable function available
   local gmt = type(debug) == "table" and debug.getmetatable or
               getmetatable or function() return false end
   -- metatable for file objects from Lua's standard io library
   local file_meta = gmt(io.stdout)


   -- make '*' optional for file:read and file:lines
   if type(file_meta) == "table" and type(file_meta.__index) == "table" then

      local function addasterisk(fmt)
         if type(fmt) == "string" and fmt:sub(1, 1) ~= "*" then
            return "*"..fmt
         else
            return fmt
         end
      end

      local file_lines = file_meta.__index.lines
      file_meta.__index.lines = function(self, ...)
         local n = select('#', ...)
         for i = 1, n do
            local a = select(i, ...)
            local b = addasterisk(a)
            -- as an optimization we only allocate a table for the
            -- modified format arguments when we have a '*' somewhere
            if a ~= b then
               local args = { ... }
               args[i] = b
               for j = i+1, n do
                  args[j] = addasterisk(args[j])
               end
               return file_lines(self, unpack(args, 1, n))
            end
         end
         return file_lines(self, ...)
      end

      local file_read = file_meta.__index.read
      file_meta.__index.read = function(self, ...)
         local n = select('#', ...)
         for i = 1, n do
            local a = select(i, ...)
            local b = addasterisk(a)
            -- as an optimization we only allocate a table for the
            -- modified format arguments when we have a '*' somewhere
            if a ~= b then
               local args = { ... }
               args[i] = b
               for j = i+1, n do
                  args[j] = addasterisk(args[j])
               end
               return file_read(self, unpack(args, 1, n))
            end
         end
         return file_read(self, ...)
      end

   end -- got a valid metatable for file objects


   -- changes for Lua 5.1 only
   if lua_version == "5.1" then

      -- cache globals
      local error, pcall, rawset, setmetatable, tostring, xpcall =
            error, pcall, rawset, setmetatable, tostring, xpcall
      local coroutine, package, string = coroutine, package, string
      local coroutine_resume = coroutine.resume
      local coroutine_running = coroutine.running
      local coroutine_status = coroutine.status
      local coroutine_yield = coroutine.yield
      local io_type = io.type


      -- detect LuaJIT (including LUAJIT_ENABLE_LUA52COMPAT compilation flag)
      local is_luajit = (string.dump(function() end) or ""):sub(1, 3) == "\027LJ"
      local is_luajit52 = is_luajit and
        #setmetatable({}, { __len = function() return 1 end }) == 1


      -- make package.searchers available as an alias for package.loaders
      local p_index = { searchers = package.loaders }
      setmetatable(package, {
         __index = p_index,
         __newindex = function(p, k, v)
            if k == "searchers" then
               rawset(p, "loaders", v)
               p_index.searchers = v
            else
               rawset(p, k, v)
            end
         end
      })


      if type(file_meta) == "table" and type(file_meta.__index) == "table" then
         if not is_luajit then
            local function helper(_, var_1, ...)
               if var_1 == nil then
                  if (...) ~= nil then
                     error((...), 2)
                  end
               end
               return var_1, ...
            end

            local function lines_iterator(st)
               return helper(st, st.f:read(unpack(st, 1, st.n)))
            end

            local file_write = file_meta.__index.write
            file_meta.__index.write = function(self, ...)
               local res, msg, errno = file_write(self, ...)
               if res then
                  return self
               else
                  return nil, msg, errno
               end
            end

            file_meta.__index.lines = function(self, ...)
               if io_type(self) == "closed file" then
                  error("attempt to use a closed file", 2)
               end
               local st = { f=self, n=select('#', ...), ... }
               for i = 1, st.n do
                  local t = type(st[i])
                  if t == "string" then
                     local fmt = st[i]:match("^*?([aln])")
                     if not fmt then
                        error("bad argument #"..(i+1).." to 'for iterator' (invalid format)", 2)
                     end
                     st[i] = "*"..fmt
                  elseif t ~= "number" then
                     error("bad argument #"..(i+1).." to 'for iterator' (invalid format)", 2)
                  end
               end
               return lines_iterator, st
            end
         end -- not luajit
      end -- file_meta valid


      -- the (x)pcall implementations start a new coroutine internally
      -- to allow yielding even in Lua 5.1. to allow for accurate
      -- stack traces we keep track of the nested coroutine activations
      -- in the weak tables below:
      local weak_meta = { __mode = "kv" }
      -- maps the internal pcall coroutines to the user coroutine that
      -- *should* be running if pcall didn't use coroutines internally
      local pcall_mainOf = setmetatable({}, weak_meta)
      -- table that maps each running coroutine started by pcall to
      -- the coroutine that resumed it (user coroutine *or* pcall
      -- coroutine!)
      local pcall_previous = setmetatable({}, weak_meta)
      -- reverse of `pcall_mainOf`. maps a user coroutine to the
      -- currently active pcall coroutine started within it
      local pcall_callOf = setmetatable({}, weak_meta)
      -- similar to `pcall_mainOf` but is used only while executing
      -- the error handler of xpcall (thus no nesting is necessary!)
      local xpcall_running = setmetatable({}, weak_meta)

      -- handle debug functions
      if type(debug) == "table" then
         local debug_getinfo = debug.getinfo
         local debug_traceback = debug.traceback

         if not is_luajit then
            local function calculate_trace_level(co, level)
               if level ~= nil then
                  for out = 1, 1/0 do
                     local info = (co==nil) and debug_getinfo(out, "") or debug_getinfo(co, out, "")
                     if info == nil then
                        local max = out-1
                        if level <= max then
                           return level
                        end
                        return nil, level-max
                     end
                  end
               end
               return 1
            end

            local stack_pattern = "\nstack traceback:"
            local stack_replace = ""
            function debug.traceback(co, msg, level)
               local lvl
               local nilmsg
               if type(co) ~= "thread" then
                  co, msg, level = coroutine_running(), co, msg
               end
               if msg == nil then
                  msg = ""
                  nilmsg = true
               elseif type(msg) ~= "string" then
                  return msg
               end
               if co == nil then
                  msg = debug_traceback(msg, level or 1)
               else
                  local xpco = xpcall_running[co]
                  if xpco ~= nil then
                     lvl, level = calculate_trace_level(xpco, level)
                     if lvl then
                        msg = debug_traceback(xpco, msg, lvl)
                     else
                        msg = msg..stack_pattern
                     end
                     lvl, level = calculate_trace_level(co, level)
                     if lvl then
                        local trace = debug_traceback(co, "", lvl)
                        msg = msg..trace:gsub(stack_pattern, stack_replace)
                     end
                  else
                     co = pcall_callOf[co] or co
                     lvl, level = calculate_trace_level(co, level)
                     if lvl then
                        msg = debug_traceback(co, msg, lvl)
                     else
                        msg = msg..stack_pattern
                     end
                  end
                  co = pcall_previous[co]
                  while co ~= nil do
                     lvl, level = calculate_trace_level(co, level)
                     if lvl then
                        local trace = debug_traceback(co, "", lvl)
                        msg = msg..trace:gsub(stack_pattern, stack_replace)
                     end
                     co = pcall_previous[co]
                  end
               end
               if nilmsg then
                  msg = msg:gsub("^\n", "")
               end
               msg = msg:gsub("\n\t%(tail call%): %?", "\000")
               msg = msg:gsub("\n\t%.%.%.\n", "\001\n")
               msg = msg:gsub("\n\t%.%.%.$", "\001")
               msg = msg:gsub("(%z+)\001(%z+)", function(some, other)
                  return "\n\t(..."..#some+#other.."+ tail call(s)...)"
               end)
               msg = msg:gsub("\001(%z+)", function(zeros)
                  return "\n\t(..."..#zeros.."+ tail call(s)...)"
               end)
               msg = msg:gsub("(%z+)\001", function(zeros)
                  return "\n\t(..."..#zeros.."+ tail call(s)...)"
               end)
               msg = msg:gsub("%z+", function(zeros)
                  return "\n\t(..."..#zeros.." tail call(s)...)"
               end)
               msg = msg:gsub("\001", function()
                  return "\n\t..."
               end)
               return msg
            end
         end -- is not luajit
      end -- debug table available


      if not is_luajit52 then
         local coroutine_running52 = M.coroutine.running
         function M.coroutine.running()
            local co, ismain = coroutine_running52()
            if ismain then
               return co, true
            else
               return pcall_mainOf[co] or co, false
            end
         end
      end

      if not is_luajit then
         local function pcall_results(current, call, success, ...)
            if coroutine_status(call) == "suspended" then
               return pcall_results(current, call, coroutine_resume(call, coroutine_yield(...)))
            end
            if pcall_previous then
               pcall_previous[call] = nil
               local main = pcall_mainOf[call]
               if main == current then current = nil end
               pcall_callOf[main] = current
            end
            pcall_mainOf[call] = nil
            return success, ...
         end

         local function pcall_exec(current, call, ...)
            local main = pcall_mainOf[current] or current
            pcall_mainOf[call] = main
            if pcall_previous then
               pcall_previous[call] = current
               pcall_callOf[main] = call
            end
            return pcall_results(current, call, coroutine_resume(call, ...))
         end

         local coroutine_create52 = M.coroutine.create

         local function pcall_coroutine(func)
            if type(func) ~= "function" then
               local callable = func
               func = function (...) return callable(...) end
            end
            return coroutine_create52(func)
         end

         function M.pcall(func, ...)
            local current = coroutine_running()
            if not current then return pcall(func, ...) end
            return pcall_exec(current, pcall_coroutine(func), ...)
         end

         local function xpcall_catch(current, call, msgh, success, ...)
            if not success then
               xpcall_running[current] = call
               local ok, result = pcall(msgh, ...)
               xpcall_running[current] = nil
               if not ok then
                  return false, "error in error handling ("..tostring(result)..")"
               end
               return false, result
            end
            return true, ...
         end

         function M.xpcall(f, msgh, ...)
            local current = coroutine_running()
            if not current then
               local args, n = { ... }, select('#', ...)
               return xpcall(function() return f(unpack(args, 1, n)) end, msgh)
            end
            local call = pcall_coroutine(f)
            return xpcall_catch(current, call, msgh, pcall_exec(current, call, ...))
         end
      end -- not luajit

   end -- lua 5.1


   -- handle exporting to global scope
   local function extend_table(from, to)
      if from ~= to then
         for k,v in pairs(from) do
            if type(v) == "table" and
               type(to[k]) == "table" and
               v ~= to[k] then
               extend_table(v, to[k])
            else
               to[k] = v
            end
         end
      end
   end

   extend_table(M, _G)

end -- lua < 5.3

-- vi: set expandtab softtabstop=3 shiftwidth=3 :
