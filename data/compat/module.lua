local _G, _VERSION = _G, _VERSION
local lua_version = _VERSION:sub(-3)


local M = _G

if lua_version < "5.3" then

   -- cache globals in upvalues
   local error, ipairs, pairs, pcall, require, select, setmetatable, type =
         error, ipairs, pairs, pcall, require, select, setmetatable, type
   local debug, io, math, package, string, table =
         debug, io, math, package, string, table
   local io_lines = io.lines
   local io_read = io.read
   local unpack = lua_version == "5.1" and unpack or table.unpack

   -- create module table
   M = {}
   local M_meta = {
      __index = _G,
      -- __newindex is set at the end
   }
   setmetatable(M, M_meta)

   -- create subtables
   M.io = setmetatable({}, { __index = io })
   M.math = setmetatable({}, { __index = math })
   M.string = setmetatable({}, { __index = string })
   M.table = setmetatable({}, { __index = table })
   M.utf8 = {}


   -- select the most powerful getmetatable function available
   local gmt = type(debug) == "table" and debug.getmetatable or
               getmetatable or function() return false end

   -- type checking functions
   local checkinteger -- forward declararation

   local function argcheck(cond, i, f, extra)
      if not cond then
         error("bad argument #"..i.." to '"..f.."' ("..extra..")", 0)
      end
   end


   -- load utf8 library
   local utf8_ok, utf8lib = pcall(require, "compat53.utf8")
   if utf8_ok then
      if lua_version == "5.1" then
         utf8lib.charpattern = "[%z\1-\127\194-\244][\128-\191]*"
      end
      for k,v in pairs(utf8lib) do
         M.utf8[k] = v
      end
      package.loaded["utf8"] = M.utf8
   end


   -- load table library
   local table_ok, tablib = pcall(require, "compat53.table")
   if table_ok then
      for k,v in pairs(tablib) do
         M.table[k] = v
      end
   end


   -- load string packing functions
   local str_ok, strlib = pcall(require, "compat53.string")
   if str_ok then
      for k,v in pairs(strlib) do
         M.string[k] = v
      end
   end


   -- try Roberto's struct module for string packing/unpacking if
   -- compat53.string is unavailable
   if not str_ok then
      local struct_ok, struct = pcall(require, "struct")
      if struct_ok then
         M.string.pack = struct.pack
         M.string.packsize = struct.size
         M.string.unpack = struct.unpack
      end
   end


   -- update math library
   do
      local maxint, minint = 1

      while maxint+1 > maxint and 2*maxint > maxint do
         maxint = maxint * 2
      end
      if 2*maxint <= maxint then
         maxint = 2*maxint-1
         minint = -maxint-1
      else
         maxint = maxint
         minint = -maxint
      end
      M.math.maxinteger = maxint
      M.math.mininteger = minint

      function M.math.tointeger(n)
         if type(n) == "number" and n <= maxint and n >= minint and n % 1 == 0 then
            return n
         end
         return nil
      end

      function M.math.type(n)
         if type(n) == "number" then
            if n <= maxint and n >= minint and n % 1 == 0 then
               return "integer"
            else
               return "float"
            end
         else
            return nil
         end
      end

      function checkinteger(x, i, f)
         local t = type(x)
         if t ~= "number" then
            error("bad argument #"..i.." to '"..f..
                  "' (number expected, got "..t..")", 0)
         elseif x > maxint or x < minint or x % 1 ~= 0 then
            error("bad argument #"..i.." to '"..f..
                  "' (number has no integer representation)", 0)
         else
            return x
         end
      end

      function M.math.ult(m, n)
         m = checkinteger(m, "1", "math.ult")
         n = checkinteger(n, "2", "math.ult")
         if m >= 0 and n < 0 then
            return true
         elseif m < 0 and n >= 0 then
            return false
         else
            return m < n
         end
      end
   end


   -- assert should allow non-string error objects
   function M.assert(cond, ...)
      if cond then
         return cond, ...
      elseif select('#', ...) > 0 then
         error((...), 0)
      else
         error("assertion failed!", 0)
      end
   end


   -- ipairs should respect __index metamethod
   do
      local function ipairs_iterator(st, var)
         var = var + 1
         local val = st[var]
         if val ~= nil then
            return var, st[var]
         end
      end
      function M.ipairs(t)
         if gmt(t) ~= nil then -- t has metatable
            return ipairs_iterator, t, 0
         else
            return ipairs(t)
         end
      end
   end


   -- make '*' optional for io.read and io.lines
   do
      local function addasterisk(fmt)
         if type(fmt) == "string" and fmt:sub(1, 1) ~= "*" then
            return "*"..fmt
         else
            return fmt
         end
      end

      function M.io.read(...)
         local n = select('#', ...)
         for i = 1, n do
            local a = select(i, ...)
            local b = addasterisk(a)
            -- as an optimization we only allocate a table for the
            -- modified format arguments when we have a '*' somewhere.
            if a ~= b then
               local args = { ... }
               args[i] = b
               for j = i+1, n do
                  args[j] = addasterisk(args[j])
               end
               return io_read(unpack(args, 1, n))
            end
         end
         return io_read(...)
      end

      -- PUC-Rio Lua 5.1 uses a different implementation for io.lines!
      function M.io.lines(...)
         local n = select('#', ...)
         for i = 2, n do
            local a = select(i, ...)
            local b = addasterisk(a)
            -- as an optimization we only allocate a table for the
            -- modified format arguments when we have a '*' somewhere.
            if a ~= b then
               local args = { ... }
               args[i] = b
               for j = i+1, n do
                  args[j] = addasterisk(args[j])
               end
               return io_lines(unpack(args, 1, n))
            end
         end
         return io_lines(...)
      end
   end


   -- update table library (if C module not available)
   if not table_ok then
      local table_concat = table.concat
      local table_insert = table.insert
      local table_remove = table.remove
      local table_sort = table.sort

      function M.table.concat(list, sep, i, j)
         local mt = gmt(list)
         if type(mt) == "table" and type(mt.__len) == "function" then
            local src = list
            list, i, j  = {}, i or 1, j or mt.__len(src)
            for k = i, j do
               list[k] = src[k]
            end
         end
         return table_concat(list, sep, i, j)
      end

      function M.table.insert(list, ...)
         local mt = gmt(list)
         local has_mt = type(mt) == "table"
         local has_len = has_mt and type(mt.__len) == "function"
         if has_mt and (has_len or mt.__index or mt.__newindex) then
            local e = (has_len and mt.__len(list) or #list)+1
            local nargs, pos, value = select('#', ...), ...
            if nargs == 1 then
               pos, value = e, pos
            elseif nargs == 2 then
               pos = checkinteger(pos, "2", "table.insert")
               argcheck(1 <= pos and pos <= e, "2", "table.insert",
                        "position out of bounds" )
            else
               error("wrong number of arguments to 'insert'", 0)
            end
            for i = e-1, pos, -1 do
               list[i+1] = list[i]
            end
            list[pos] = value
         else
            return table_insert(list, ...)
         end
      end

      function M.table.move(a1, f, e, t, a2)
         a2 = a2 or a1
         f = checkinteger(f, "2", "table.move")
         argcheck(f > 0, "2", "table.move",
                  "initial position must be positive")
         e = checkinteger(e, "3", "table.move")
         t = checkinteger(t, "4", "table.move")
         if e >= f then
            local m, n, d = 0, e-f, 1
            if t > f then m, n, d = n, m, -1 end
            for i = m, n, d do
               a2[t+i] = a1[f+i]
            end
         end
         return a2
      end

      function M.table.remove(list, pos)
         local mt = gmt(list)
         local has_mt = type(mt) == "table"
         local has_len = has_mt and type(mt.__len) == "function"
         if has_mt and (has_len or mt.__index or mt.__newindex) then
            local e = (has_len and mt.__len(list) or #list)
            pos = pos ~= nil and checkinteger(pos, "2", "table.remove") or e
            if pos ~= e then
               argcheck(1 <= pos and pos <= e+1, "2", "table.remove",
                        "position out of bounds" )
            end
            local result = list[pos]
            while pos < e do
               list[pos] = list[pos+1]
               pos = pos + 1
            end
            list[pos] = nil
            return result
         else
            return table_remove(list, pos)
         end
      end

      do
         local function pivot(list, cmp, a, b)
            local m = b - a
            if m > 2 then
               local c = a + (m-m%2)/2
               local x, y, z = list[a], list[b], list[c]
               if not cmp(x, y) then
                  x, y, a, b = y, x, b, a
               end
               if not cmp(y, z) then
                  y, b = z, c
               end
               if not cmp(x, y) then
                  y, b = x, a
               end
               return b, y
            else
               return b, list[b]
            end
         end

         local function lt_cmp(a, b)
            return a < b
         end

         local function qsort(list, cmp, b, e)
            if b < e then
               local i, j, k, val = b, e, pivot(list, cmp, b, e)
               while i < j do
                  while i < j and cmp(list[i], val) do
                     i = i + 1
                  end
                  while i < j and not cmp(list[j], val) do
                     j = j - 1
                  end
                  if i < j then
                     list[i], list[j] = list[j], list[i]
                     if i == k then k = j end -- update pivot position
                     i, j = i+1, j-1
                  end
               end
               if i ~= k and not cmp(list[i], val) then
                  list[i], list[k] = val, list[i]
                  k = i -- update pivot position
               end
               qsort(list, cmp, b, i == k and i-1 or i)
               return qsort(list, cmp, i+1, e)
            end
         end

         function M.table.sort(list, cmp)
            local mt = gmt(list)
            local has_mt = type(mt) == "table"
            local has_len = has_mt and type(mt.__len) == "function"
            if has_len then
               cmp = cmp or lt_cmp
               local len = mt.__len(list)
               return qsort(list, cmp, 1, len)
            else
               return table_sort(list, cmp)
            end
         end
      end

      local function unpack_helper(list, i, j, ...)
         if j < i then
            return ...
         else
            return unpack_helper(list, i, j-1, list[j], ...)
         end
      end
      function M.table.unpack(list, i, j)
         local mt = gmt(list)
         local has_mt = type(mt) == "table"
         local has_len = has_mt and type(mt.__len) == "function"
         if has_mt and (has_len or mt.__index) then
            i, j = i or 1, j or (has_len and mt.__len(list)) or #list
            return unpack_helper(list, i, j)
         else
            return unpack(list, i, j)
         end
      end
   end -- update table library


   -- bring Lua 5.1 (and LuaJIT) up to speed with Lua 5.2
   if lua_version == "5.1" then
      -- detect LuaJIT (including LUAJIT_ENABLE_LUA52COMPAT compilation flag)
      local is_luajit = (string.dump(function() end) or ""):sub(1, 3) == "\027LJ"
      local is_luajit52 = is_luajit and
        #setmetatable({}, { __len = function() return 1 end }) == 1

      -- cache globals in upvalues
      local load, loadfile, loadstring, setfenv, xpcall =
            load, loadfile, loadstring, setfenv, xpcall
      local coroutine, os = coroutine, os
      local coroutine_create = coroutine.create
      local coroutine_resume = coroutine.resume
      local coroutine_running = coroutine.running
      local coroutine_status = coroutine.status
      local coroutine_yield = coroutine.yield
      local io_input = io.input
      local io_open = io.open
      local io_output = io.output
      local io_write = io.write
      local math_log = math.log
      local os_execute = os.execute
      local string_find = string.find
      local string_format = string.format
      local string_gmatch = string.gmatch
      local string_gsub = string.gsub
      local string_match = string.match
      local string_rep = string.rep
      local table_concat = table.concat

      -- create subtables
      M.coroutine = setmetatable({}, { __index = coroutine })
      M.os = setmetatable({}, { __index = os })
      M.package = setmetatable({}, { __index = package })

      -- handle debug functions
      if type(debug) == "table" then
         local debug_setfenv = debug.setfenv
         local debug_getfenv = debug.getfenv
         local debug_setmetatable = debug.setmetatable

         M.debug = setmetatable({}, { __index = debug })

         if not is_luajit52 then
            function M.debug.setuservalue(obj, value)
               if type(obj) ~= "userdata" then
                  error("bad argument #1 to 'setuservalue' (userdata expected, got "..
                        type(obj)..")", 2)
               end
               if value == nil then value = _G end
               if type(value) ~= "table" then
                  error("bad argument #2 to 'setuservalue' (table expected, got "..
                        type(value)..")", 2)
               end
               return debug_setfenv(obj, value)
            end

            function M.debug.getuservalue(obj)
               if type(obj) ~= "userdata" then
                  return nil
               else
                  local v = debug_getfenv(obj)
                  if v == _G or v == package then
                     return nil
                  end
                  return v
               end
            end

            function M.debug.setmetatable(value, tab)
               debug_setmetatable(value, tab)
               return value
            end
         end -- not luajit with compat52 enabled
      end -- debug table available


      if not is_luajit52 then
         function M.pairs(t)
            local mt = gmt(t)
            if type(mt) == "table" and type(mt.__pairs) == "function" then
               return mt.__pairs(t)
            else
               return pairs(t)
            end
         end
      end


      if not is_luajit then
         local function check_mode(mode, prefix)
            local has = { text = false, binary = false }
            for i = 1,#mode do
               local c = mode:sub(i, i)
               if c == "t" then has.text = true end
               if c == "b" then has.binary = true end
            end
            local t = prefix:sub(1, 1) == "\27" and "binary" or "text"
            if not has[t] then
               return "attempt to load a "..t.." chunk (mode is '"..mode.."')"
            end
         end

         function M.load(ld, source, mode, env)
            mode = mode or "bt"
            local chunk, msg
            if type( ld ) == "string" then
               if mode ~= "bt" then
                  local merr = check_mode(mode, ld)
                  if merr then return nil, merr end
               end
               chunk, msg = loadstring(ld, source)
            else
               local ld_type = type(ld)
               if ld_type ~= "function" then
                  error("bad argument #1 to 'load' (function expected, got "..
                        ld_type..")", 2)
               end
               if mode ~= "bt" then
                  local checked, merr = false, nil
                  local function checked_ld()
                     if checked then
                        return ld()
                     else
                        checked = true
                        local v = ld()
                        merr = check_mode(mode, v or "")
                        if merr then return nil end
                        return v
                     end
                  end
                  chunk, msg = load(checked_ld, source)
                  if merr then return nil, merr end
               else
                  chunk, msg = load(ld, source)
               end
            end
            if not chunk then
               return chunk, msg
            end
            if env ~= nil then
               setfenv(chunk, env)
            end
            return chunk
         end

         M.loadstring = M.load

         function M.loadfile(file, mode, env)
            mode = mode or "bt"
            if mode ~= "bt" then
               local f = io_open(file, "rb")
               if f then
                  local prefix = f:read(1)
                  f:close()
                  if prefix then
                     local merr = check_mode(mode, prefix)
                     if merr then return nil, merr end
                  end
               end
            end
            local chunk, msg = loadfile(file)
            if not chunk then
               return chunk, msg
            end
            if env ~= nil then
               setfenv(chunk, env)
            end
            return chunk
         end
      end -- not luajit


      if not is_luajit52 then
         function M.rawlen(v)
            local t = type(v)
            if t ~= "string" and t ~= "table" then
               error("bad argument #1 to 'rawlen' (table or string expected)", 2)
            end
            return #v
         end
      end


      if not is_luajit then
         function M.xpcall(f, msgh, ...)
            local args, n = { ... }, select('#', ...)
            return xpcall(function() return f(unpack(args, 1, n)) end, msgh)
         end
      end


      if not is_luajit52 then
         function M.os.execute(cmd)
            local code = os_execute(cmd)
            -- Lua 5.1 does not report exit by signal.
            if code == 0 then
               return true, "exit", code
            else
               if package.config:sub(1, 1) == '/' then
                  code = code/256 -- only correct on Linux!
               end
               return nil, "exit", code
            end
         end
      end


      if not table_ok and not is_luajit52 then
         M.table.pack = function(...)
            return { n = select('#', ...), ... }
         end
      end


      local main_coroutine = coroutine_create(function() end)

      function M.coroutine.create(func)
         local success, result = pcall(coroutine_create, func)
         if not success then
            if type(func) ~= "function" then
               error("bad argument #1 (function expected)", 0)
             end
            result = coroutine_create(function(...) return func(...) end)
         end
         return result
      end

      if not is_luajit52 then
         function M.coroutine.running()
            local co = coroutine_running()
            if co then
               return co, false
            else
               return main_coroutine, true
            end
         end
      end

      function M.coroutine.yield(...)
         local co, flag = coroutine_running()
         if co and not flag then
            return coroutine_yield(...)
         else
            error("attempt to yield from outside a coroutine", 0)
         end
      end

      if not is_luajit then
         function M.coroutine.resume(co, ...)
            if co == main_coroutine then
               return false, "cannot resume non-suspended coroutine"
            else
               return coroutine_resume(co, ...)
            end
         end

         function M.coroutine.status(co)
            local notmain = coroutine_running()
            if co == main_coroutine then
               return notmain and "normal" or "running"
            else
               return coroutine_status(co)
            end
         end
      end -- not luajit


      if not is_luajit then
         M.math.log = function(x, base)
            if base ~= nil then
               return math_log(x)/math_log(base)
            else
               return math_log(x)
            end
         end
      end


      if not is_luajit then
         function M.package.searchpath(name, path, sep, rep)
            sep = (sep or "."):gsub("(%p)", "%%%1")
            rep = (rep or package.config:sub(1, 1)):gsub("(%%)", "%%%1")
            local pname = name:gsub(sep, rep):gsub("(%%)", "%%%1")
            local msg = {}
            for subpath in path:gmatch("[^;]+") do
               local fpath = subpath:gsub("%?", pname)
               local f = io_open(fpath, "r")
               if f then
                  f:close()
                  return fpath
               end
               msg[#msg+1] = "\n\tno file '" .. fpath .. "'"
            end
            return nil, table_concat(msg)
         end
      end


      local function fix_pattern(pattern)
         return (string_gsub(pattern, "%z", "%%z"))
      end

      function M.string.find(s, pattern, ...)
         return string_find(s, fix_pattern(pattern), ...)
      end

      function M.string.gmatch(s, pattern)
         return string_gmatch(s, fix_pattern(pattern))
      end

      function M.string.gsub(s, pattern, ...)
         return string_gsub(s, fix_pattern(pattern), ...)
      end

      function M.string.match(s, pattern, ...)
         return string_match(s, fix_pattern(pattern), ...)
      end

      if not is_luajit then
         function M.string.rep(s, n, sep)
            if sep ~= nil and sep ~= "" and n >= 2 then
               return s .. string_rep(sep..s, n-1)
            else
               return string_rep(s, n)
            end
         end
      end

      if not is_luajit then
         do
            local addqt = {
               ["\n"] = "\\\n",
               ["\\"] = "\\\\",
               ["\""] = "\\\""
            }

            local function addquoted(c, d)
               return (addqt[c] or string_format(d~="" and "\\%03d" or "\\%d", c:byte()))..d
            end

            function M.string.format(fmt, ...)
               local args, n = { ... }, select('#', ...)
               local i = 0
               local function adjust_fmt(lead, mods, kind)
                  if #lead % 2 == 0 then
                     i = i + 1
                     if kind == "s" then
                        args[i] = _G.tostring(args[i])
                     elseif kind == "q" then
                        args[i] = '"'..string_gsub(args[i], "([%z%c\\\"\n])(%d?)", addquoted)..'"'
                        return lead.."%"..mods.."s"
                     end
                  end
               end
               fmt = string_gsub(fmt, "(%%*)%%([%d%.%-%+%# ]*)(%a)", adjust_fmt)
               return string_format(fmt, unpack(args, 1, n))
            end
         end
      end


      function M.io.write(...)
         local res, msg, errno = io_write(...)
         if res then
            return io_output()
         else
            return nil, msg, errno
         end
      end

      if not is_luajit then
         local function helper(st, var_1, ...)
            if var_1 == nil then
               if st.doclose then st.f:close() end
               if (...) ~= nil then
                  error((...), 2)
               end
            end
            return var_1, ...
         end

         local function lines_iterator(st)
            return helper(st, st.f:read(unpack(st, 1, st.n)))
         end

         function M.io.lines(fname, ...)
            local doclose, file, msg
            if fname ~= nil then
               doclose, file, msg = true, io_open(fname, "r")
               if not file then error(msg, 2) end
            else
               doclose, file = false, io_input()
            end
            local st = { f=file, doclose=doclose, n=select('#', ...), ... }
            for i = 1, st.n do
               local t = type(st[i])
               if t == "string" then
                  local fmt = st[i]:match("^%*?([aln])")
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

   end -- lua 5.1

   -- further write should be forwarded to _G
   M_meta.__newindex = _G

end -- lua < 5.3


-- return module table
return M

-- vi: set expandtab softtabstop=3 shiftwidth=3 :
