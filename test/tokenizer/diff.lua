-- Differential + throughput check for the C tokenizer core.
--
--   test/tokenizer/diff.sh [dir]     # default: the repo itself
--
-- For every line of every source file under <dir>, tokenize with the Lua
-- reference (config.tokenizer_c = false) and with tokenizer_c directly, and
-- assert the token stream and outgoing state are byte-identical. Lines the C
-- core declines (subsyntax) are counted, not failed. Ends with a throughput
-- comparison over the largest file seen.
--
-- Exit 0 on a clean run, 1 on any mismatch, 2 if the C core isn't built.

local M = {}

function M.init()
  local core = require "core"
  local syntax = require "core.syntax"
  local config = require "core.config"
  local tokenizer = require "core.tokenizer"
  core.threads = core.threads or {}
  core.add_thread = function() end
  config.tokenizer_c = false            -- tokenizer.tokenize_lua is the reference

  local tc = rawget(_G, "tokenizer_c")
  if not tc then io.stdout:write("tokenizer_c not built\n"); M.code = 2; return end

  -- bundled languages + anything the plugins dir offers
  for _, l in ipairs({ "c", "cpp", "css", "html", "js", "lua", "md",
                       "python", "xml" }) do
    pcall(require, "plugins.language_" .. l)
  end

  local base = ARGS[3] or ARGS[2] or "."
  local exts = { c=1, h=1, hpp=1, cpp=1, cc=1, cxx=1, lua=1, md=1, markdown=1,
                 py=1, pyi=1, css=1, html=1, htm=1, js=1, mjs=1, cjs=1, json=1,
                 xml=1 }
  local files = {}
  local function walk(dir)
    for _, name in ipairs(system.list_dir(dir) or {}) do
      if name ~= ".git" and name ~= "build" and not name:match("^%.$") then
        local p = dir .. "/" .. name
        local info = system.get_file_info(p)
        if info and info.type == "dir" then
          walk(p)
        elseif info and info.type == "file" then
          local e = name:match("%.([%w]+)$")
          if e and exts[e:lower()] then files[#files + 1] = p end
        end
      end
    end
  end
  walk(base)
  table.sort(files)

  local function key(t)
    local b = {}
    for i = 1, #t, 2 do b[#b + 1] = tostring(t[i]) .. "\1" .. tostring(t[i + 1]) end
    return table.concat(b, "\2")
  end
  local function fmt(t)
    return (key(t):gsub("\1", "="):gsub("\2", " | "))
  end
  local function lua_full(syn, line, st)
    local ok, toks, ns, rsm = pcall(tokenizer.tokenize_lua, syn, line, st)
    while ok and rsm do
      ok, toks, ns, rsm = pcall(tokenizer.tokenize_lua, syn, line, ns, rsm)
    end
    return ok, toks, ns
  end

  local nfiles, nlines, handled, declined, skipped, mismatch = 0, 0, 0, 0, 0, 0
  local shown = 0
  local biggest, biggest_lines, biggest_syn

  for _, path in ipairs(files) do
    local f = io.open(path, "rb"); if f then
      local data = f:read("*a"); f:close()
      local syn = syntax.get(path:match("[^/\\]+$"))
      if #syn.patterns > 0 then
        nfiles = nfiles + 1
        local lines = {}
        for ln in (data .. "\n"):gmatch("(.-)\n") do
          if ln:sub(-1) == "\r" then ln = ln:sub(1, -2) end
          lines[#lines + 1] = ln
        end
        if #lines > (biggest_lines or -1) then
          biggest, biggest_lines, biggest_syn = lines, #lines, syn
        end
        local lstate, cstate = nil, "\0"
        for i, line in ipairs(lines) do
          nlines = nlines + 1
          local lok, lt, ls = lua_full(syn, line, lstate)
          local cok, cr1, cr2, cr3 = pcall(tc.tokenize, syn, line, cstate or "\0")
          if not lok then
            skipped = skipped + 1
            lstate, cstate = nil, "\0"
          elseif not cok then
            mismatch = mismatch + 1
            if shown < 12 then
              shown = shown + 1
              io.stdout:write(string.format("%s:%d  C raised: %s\n",
                path, i, tostring(cr1)))
            end
            lstate, cstate = ls, ls
          elseif cr1 == false then
            declined = declined + 1
            lstate, cstate = ls, ls
          else
            handled = handled + 1
            if key(lt) ~= key(cr2) or ls ~= cr3 then
              mismatch = mismatch + 1
              if shown < 12 then
                shown = shown + 1
                io.stdout:write(string.format(
                  "%s:%d\n  line: %q\n  lua: %s  state=%q\n  c  : %s  state=%q\n",
                  path, i, line, fmt(lt), ls or "", fmt(cr2), cr3 or ""))
              end
            end
            lstate, cstate = ls, cr3
          end
        end
      end
    end
  end

  io.stdout:write(string.format(
    "\n%d files, %d lines  |  C handled %d  declined %d  skipped %d  |  mismatch %d\n",
    nfiles, nlines, handled, declined, skipped, mismatch))

  -- throughput over the biggest file
  if biggest and biggest_lines > 50 then
    local function run_lua()
      local st = nil
      for _, ln in ipairs(biggest) do local _, _, ns = lua_full(biggest_syn, ln, st); st = ns end
    end
    local function run_c()
      local st = "\0"
      for _, ln in ipairs(biggest) do
        local ok, _, ns = tc.tokenize(biggest_syn, ln, st or "\0")
        st = ok and ns or "\0"
      end
    end
    run_lua(); run_c() -- warm
    local reps = 20
    local t0 = system.get_time()
    for _ = 1, reps do run_lua() end
    local lua_t = (system.get_time() - t0) / reps
    t0 = system.get_time()
    for _ = 1, reps do run_c() end
    local c_t = (system.get_time() - t0) / reps
    io.stdout:write(string.format(
      "throughput (%d lines, %s):  lua %.2f ms   c %.2f ms   %.1fx\n",
      biggest_lines, biggest_syn.name or "?", lua_t * 1000, c_t * 1000,
      c_t > 0 and lua_t / c_t or 0))
  end

  M.code = (mismatch == 0) and 0 or 1
end

function M.run() os.exit(M.code or 0) end

return M
