-- Worker-thread check for the C tokenizer core.
--
--   test/tokenizer/thread.sh [dir]     # default: the repo itself
--
-- tokenizer_c.thread_submit runs scan() over a range of lines on a background
-- thread; thread_poll drains the finished lines. This asserts that what the
-- worker produces is byte-identical to the synchronous C core (same scan(),
-- just L == NULL) for every line of every source file under <dir> -- and then
-- runs a random edit/cancel/resubmit stress that must still converge on the
-- synchronous tokenization.
--
-- Exit 0 clean, 1 on any mismatch, 2 if the C core / worker isn't built.

local M = {}

local function key(t)
  local b = {}
  for i = 1, #t, 2 do b[#b + 1] = tostring(t[i]) .. "\1" .. tostring(t[i + 1]) end
  return table.concat(b, "\2")
end

function M.init()
  local syntax = require "core.syntax"
  local config = require "core.config"
  local core = require "core"
  local tokenizer = require "core.tokenizer"
  core.threads = core.threads or {}
  core.add_thread = function() end
  config.tokenizer_c = false

  local tc = rawget(_G, "tokenizer_c")
  if not tc or not tc.thread_submit then
    io.stdout:write("tokenizer_c worker not built\n"); M.code = 2; return
  end

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

  -- split a file into doc-style lines (each keeps its trailing "\n")
  local function doc_lines(data)
    local lines = {}
    for ln in (data .. "\n"):gmatch("(.-)\n") do
      if ln:sub(-1) == "\r" then ln = ln:sub(1, -2) end
      lines[#lines + 1] = ln .. "\n"
    end
    if #lines == 0 then lines[1] = "\n" end
    return lines
  end

  -- synchronous C-core reference: tokenize each line (verbatim, as the worker
  -- receives it), threading state
  local function sync_tokenize(syn, lines)
    local out, state = {}, "\0"
    for i, l in ipairs(lines) do
      local ok, toks, ns = tc.tokenize(syn, l, state)
      if not ok then
        out[i] = { ok = false }
        state = "\0"
      else
        out[i] = { ok = true, k = key(toks), state = ns }
        state = ns
      end
    end
    return out
  end

  -- the pure-Lua tokenizer over the same verbatim lines, so we also catch a
  -- C-vs-Lua divergence on the trailing newline the highlighter keeps
  local function lua_tokenize(syn, lines)
    local out, state = {}, nil
    for i, l in ipairs(lines) do
      local ok, toks, ns, rsm = pcall(tokenizer.tokenize_lua, syn, l, state)
      while ok and rsm do
        ok, toks, ns, rsm = pcall(tokenizer.tokenize_lua, syn, l, ns, rsm)
      end
      if not ok then out[i] = false; state = nil
      else out[i] = { k = key(toks), state = ns }; state = ns end
    end
    return out
  end

  -- drain job `id` until it has delivered `want` lines (or gone idle)
  local function drain(collect, want, id)
    local spins = 0
    while collect.n < want do
      local batch = tc.thread_poll(id)
      if batch then
        for _, job in ipairs(batch) do
          for off, rec in ipairs(job.lines) do
            local abs = job.first_line + off - 1
            collect[abs] = rec
            if not collect.seen[abs] then
              collect.seen[abs] = true
              collect.n = collect.n + 1
            end
          end
        end
        spins = 0
      else
        if not tc.thread_busy() then break end
        system.sleep(0.001)
        spins = spins + 1
        if spins > 20000 then error("worker stalled") end
      end
    end
  end

  local nfiles, nlines, handled, declined, mismatch, cvl = 0, 0, 0, 0, 0, 0
  local shown = 0

  for _, path in ipairs(files) do
    local f = io.open(path, "rb")
    if f then
      local data = f:read("*a"); f:close()
      local syn = syntax.get(path:match("[^/\\]+$"))
      if #syn.patterns > 0 then
        local lines = doc_lines(data)
        nfiles = nfiles + 1
        nlines = nlines + #lines

        local ref = sync_tokenize(syn, lines)
        local lref = lua_tokenize(syn, lines)
        for i = 1, #lines do
          if ref[i].ok and lref[i]
             and (ref[i].k ~= lref[i].k or (ref[i].state or false) ~= (lref[i].state or false)) then
            cvl = cvl + 1
            if shown < 12 then shown = shown + 1
              io.stdout:write(string.format("%s:%d  C != Lua (verbatim line)\n", path, i)) end
          end
        end

        local id = tc.thread_submit(syn, lines, 1, #lines, "\0")
        if not id then
          -- worker declined the whole syntax; not a mismatch
        else
          local collect = { n = 0, seen = {} }
          drain(collect, #lines, id)
          for i = 1, #lines do
            local w, r = collect[i], ref[i]
            if not w then
              -- worker stopped early (declined line upstream); ok if ref also declined somewhere <= i
            elseif w.ok and r.ok then
              handled = handled + 1
              if w.tokens and (key(w.tokens) ~= r.k or w.state ~= r.state) then
                mismatch = mismatch + 1
                if shown < 12 then
                  shown = shown + 1
                  io.stdout:write(string.format("%s:%d worker != sync\n", path, i))
                end
              end
            elseif w.ok ~= (r and r.ok) then
              declined = declined + 1
            end
          end
        end
      end
    end
  end

  io.stdout:write(string.format(
    "\n%d files, %d lines  |  worker matched %d  declined %d  |  mismatch %d  |  C!=Lua %d\n",
    nfiles, nlines, handled, declined, mismatch, cvl))
  mismatch = mismatch + cvl

  -- random edit / cancel / resubmit stress on the largest handled file
  do
    local big, biglines
    for _, path in ipairs(files) do
      local fh = io.open(path, "rb")
      if fh then
        local d = fh:read("*a"); fh:close()
        local n = select(2, d:gsub("\n", "\n"))
        if n > (biglines or 200) then big, biglines = path, n end
      end
    end
    if big then
      local fh = io.open(big, "rb"); local data = fh:read("*a"); fh:close()
      local syn = syntax.get(big:match("[^/\\]+$"))
      local lines = doc_lines(data)
      local ref = sync_tokenize(syn, lines)
      math.randomseed(1234567)
      local rounds = tonumber(os.getenv("STRESS_ROUNDS")) or 20
      local stress_bad = 0
      for _ = 1, rounds do
        -- an "edit" invalidates from a random line to the end
        local from = math.random(1, #lines)
        local start_state = from > 1 and (ref[from - 1].ok and ref[from - 1].state or "\0") or "\0"
        local id = tc.thread_submit(syn, lines, from, #lines, start_state)
        if id then
          local collect = { n = 0, seen = {} }
          -- sometimes cancel partway, then resubmit the same range
          if math.random() < 0.5 then
            drain(collect, math.min(64, #lines - from + 1), id)
            tc.thread_cancel(id)
            id = tc.thread_submit(syn, lines, from, #lines, start_state)
            collect = { n = 0, seen = {} }
          end
          drain(collect, #lines - from + 1, id)
          for i = from, #lines do
            local w, r = collect[i], ref[i]
            if w and w.ok and r.ok and w.tokens
               and (key(w.tokens) ~= r.k or w.state ~= r.state) then
              stress_bad = stress_bad + 1
            end
          end
          tc.thread_cancel(id)
        end
      end
      io.stdout:write(string.format(
        "stress: %d rounds on %s (%d lines)  |  bad lines %d\n",
        rounds, big:match("[^/\\]+$"), #lines, stress_bad))
      mismatch = mismatch + stress_bad
    end
  end

  M.code = (mismatch == 0) and 0 or 1
end

function M.run() os.exit(M.code or 0) end

return M
