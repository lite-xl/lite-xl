-- Highlighter integration check for the background tokenizer thread.
--
--   test/tokenizer/hlthread.sh [dir]
--
-- Drives core.doc.highlighter with config.tokenizer_thread on over a fake Doc
-- for every source file under <dir>, pumping its core.add_thread coroutine by
-- hand until it catches up, and asserts every line's tokens + outgoing state
-- match a synchronous reference. Then repeats with a mid-catch-up edit.
--
-- Exit 0 clean, 1 on mismatch, 2 if the worker isn't built.

local core = require "core"
local syntax = require "core.syntax"
local config = require "core.config"
local tokenizer = require "core.tokenizer"

local M = {}

local captured
core.threads = core.threads or {}
core.add_thread = function(fn) captured = coroutine.create(fn); return captured end
core.redraw = false

local function key(t)
  local b = {}
  for i = 1, #t, 2 do b[#b + 1] = tostring(t[i]) .. "\1" .. tostring(t[i + 1]) end
  return table.concat(b, "\2")
end

local function pump(h, limit)
  local n = 0
  local hard = limit or 200000
  while captured and coroutine.status(captured) ~= "dead" do
    local ok, err = coroutine.resume(captured)
    if not ok then error(err) end
    n = n + 1
    if limit and n >= limit then return false end
    if n >= hard then error("pump did not converge (" .. n .. " iters, fil=" ..
      tostring(h.first_invalid_line) .. " mwl=" .. tostring(h.max_wanted_line) .. ")") end
    if h.first_invalid_line > h.max_wanted_line then break end
    if tokenizer.thread_busy and tokenizer.thread_busy() then system.sleep(0.0005) end
  end
  return true
end

local function reference(syn, lines)
  -- exactly what Highlighter:tokenize_line does: the line verbatim (newline
  -- included), through the same tokenizer.tokenize the highlighter calls
  local out, state = {}, nil
  for i, l in ipairs(lines) do
    local toks, ns, rsm = tokenizer.tokenize(syn, l, state)
    while rsm do toks, ns, rsm = tokenizer.tokenize(syn, l, ns, rsm) end
    out[i] = { k = key(toks), state = ns }
    state = ns
  end
  return out
end

local function check(h, ref, lines, from, tag, path, report)
  for i = from, #lines do
    local ln = h.lines[i]
    if not ln or not ln.tokens then
      report.missing = report.missing + 1
    elseif key(ln.tokens) ~= ref[i].k or (ln.state or false) ~= (ref[i].state or false) then
      report.bad = report.bad + 1
      if report.shown < 10 then
        report.shown = report.shown + 1
        io.stdout:write(string.format("%s:%d  %s  hl != ref\n  line=%q\n  hl : %s  st=%q\n  ref: %s  st=%q\n  hl.init=%q\n",
          path, i, tag, lines[i],
          (key(ln.tokens):gsub("\1","="):gsub("\2"," | ")), tostring(ln.state),
          (ref[i].k:gsub("\1","="):gsub("\2"," | ")), tostring(ref[i].state),
          tostring(ln.init_state)))
      end
    else
      report.ok = report.ok + 1
    end
  end
end

function M.init()
  local tc = rawget(_G, "tokenizer_c")
  if not tc or not tc.thread_submit then
    io.stdout:write("tokenizer_c worker not built\n"); M.code = 2; return
  end
  for _, l in ipairs({ "c", "cpp", "css", "html", "js", "lua", "md",
                       "python", "xml" }) do
    pcall(require, "plugins.language_" .. l)
  end
  config.tokenizer_c = true
  config.tokenizer_thread = os.getenv("HL_SYNC") == nil

  local Highlighter = require "core.doc.highlighter"

  local base = ARGS[3] or ARGS[2] or "."
  local exts = { c=1, h=1, cpp=1, lua=1, md=1, py=1, css=1, html=1, js=1, json=1, xml=1 }
  local files = {}
  local function walk(dir)
    for _, name in ipairs(system.list_dir(dir) or {}) do
      if name ~= ".git" and name ~= "build" and not name:match("^%.$") then
        local p = dir .. "/" .. name
        local info = system.get_file_info(p)
        if info and info.type == "dir" then walk(p)
        elseif info and info.type == "file" then
          local e = name:match("%.([%w]+)$")
          if e and exts[e:lower()] then files[#files + 1] = p end
        end
      end
    end
  end
  walk(base)
  table.sort(files)

  local report = { ok = 0, bad = 0, missing = 0, shown = 0 }
  local nfiles, edited = 0, 0

  for _, path in ipairs(files) do
    local fh = io.open(path, "rb")
    if fh then
      local data = fh:read("*a"); fh:close()
      local syn = syntax.get(path:match("[^/\\]+$"))
      if #syn.patterns > 0 then
        local lines = {}
        for ln in (data .. "\n"):gmatch("(.-)\n") do
          if ln:sub(-1) == "\r" then ln = ln:sub(1, -2) end
          lines[#lines + 1] = ln .. "\n"
        end
        if #lines == 0 then lines[1] = "\n" end
        nfiles = nfiles + 1

        local ref = reference(syn, lines)
        local doc = { syntax = syn, lines = lines }
        captured = nil
        local h = Highlighter(doc)
        h.max_wanted_line = #lines
        h:start()
        pump(h)
        check(h, ref, lines, 1, "full", path, report)

        -- a mid-catch-up edit on a longer file: change one line, invalidate,
        -- keep pumping, must still converge
        if #lines > 120 then
          edited = edited + 1
          captured = nil
          h = Highlighter(doc)
          h.max_wanted_line = #lines
          h:start()
          pump(h, 2)                       -- partial
          local k = math.max(2, math.floor(#lines / 2))
          lines[k] = "/* edited */ x" .. lines[k]
          local ref2 = reference(syn, lines)
          h:invalidate(k)
          h.max_wanted_line = #lines
          h:start()
          pump(h)
          check(h, ref2, lines, k, "post-edit", path, report)
          lines[k] = lines[k]:gsub("^/%* edited %*/ x", "")
        end
      end
    end
  end

  io.stdout:write(string.format(
    "\n%d files (%d with a mid-edit)  |  lines ok %d  missing %d  |  bad %d\n",
    nfiles, edited, report.ok, report.missing, report.bad))

  -- two highlighters sharing the one worker: pump them interleaved and check
  -- neither steals the other's results (thread_poll is per-job-id)
  do
    local pick = {}
    for _, p in ipairs(files) do
      local fh = io.open(p, "rb")
      if fh then local d = fh:read("*a"); fh:close()
        if select(2, d:gsub("\n", "\n")) > 300 then pick[#pick + 1] = { p, d } end
      end
      if #pick == 2 then break end
    end
    if #pick == 2 then
      local hs, refs, cos = {}, {}, {}
      for m = 1, 2 do
        local syn = syntax.get(pick[m][1]:match("[^/\\]+$"))
        local lines = {}
        for ln in (pick[m][2] .. "\n"):gmatch("(.-)\n") do
          if ln:sub(-1) == "\r" then ln = ln:sub(1, -2) end
          lines[#lines + 1] = ln .. "\n"
        end
        refs[m] = reference(syn, lines)
        captured = nil
        local h = Highlighter({ syntax = syn, lines = lines })
        h.max_wanted_line = #lines
        h:start()
        hs[m], cos[m] = h, captured
      end
      local rounds = 0
      while (coroutine.status(cos[1]) ~= "dead" or coroutine.status(cos[2]) ~= "dead")
            and rounds < 100000 do
        rounds = rounds + 1
        for m = 1, 2 do
          if coroutine.status(cos[m]) ~= "dead" then
            local ok, err = coroutine.resume(cos[m])
            if not ok then error(err) end
          end
        end
        system.sleep(0.0005)
      end
      local mrep = { ok = 0, bad = 0, missing = 0, shown = 0 }
      for m = 1, 2 do
        local lines = hs[m].doc.lines
        check(hs[m], refs[m], lines, 1, "multi", pick[m][1], mrep)
      end
      io.stdout:write(string.format(
        "multi: 2 highlighters, %d lines ok  missing %d  bad %d\n",
        mrep.ok, mrep.missing, mrep.bad))
      report.bad = report.bad + mrep.bad + mrep.missing
    end
  end

  M.code = (report.bad == 0 and report.missing == 0) and 0 or 1
end

function M.run() os.exit(M.code or 0) end

return M
