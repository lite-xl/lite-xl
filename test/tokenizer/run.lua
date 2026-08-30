-- Golden-token corpus for the syntax tokenizer.
--
-- Tokenizes every line of every file under corpus/ with the real
-- `core.tokenizer` (exactly as the highlighter drives it -- feeding each
-- line's outgoing state into the next) and reduces the result to one digest
-- per line. `record` writes those digests to golden.txt; `check` (the
-- default) recomputes them and fails on the first divergence.
--
-- The point is a byte-for-byte gate: any change to tokenizer.lua, utf8.c's
-- pattern matcher, regex.c, or a bundled language plugin that alters the
-- token stream for valid input shows up here as a diff.
--
-- Run it through the headless runtime hook -- see run.sh, or:
--   LITE_XL_RUNTIME=run LITE_USERDIR=test/tokenizer \
--     lite-xl check test/tokenizer
--
-- ARGS: [exe] <mode> <base-dir>
--   mode      "check" (default) | "record"
--   base-dir  directory holding corpus/ and golden.txt (default ".")

local core = require "core"
local syntax = require "core.syntax"
local tokenizer = require "core.tokenizer"

local M = {}

local mode = ARGS[2] or "check"
local base = ARGS[3] or "."
local corpus_dir = base .. "/corpus"
local golden_path = base .. "/golden.txt"
local actual_dir = base .. "/actual"

-- Bundled syntaxes. Loading the modules is enough; each one calls
-- syntax.add() at require time.
local LANGUAGES = {
  "language_c", "language_cpp", "language_css", "language_html",
  "language_js", "language_lua", "language_md", "language_python",
  "language_xml",
}

local FNV_OFFSET = 0xcbf29ce484222325
local FNV_PRIME = 0x100000001b3

local function fnv1a(h, s)
  for i = 1, #s do
    h = (h ~ s:byte(i)) * FNV_PRIME
  end
  return h
end

local function read_file(path)
  local f, err = io.open(path, "rb")
  if not f then error(err) end
  local data = f:read("*a")
  f:close()
  return data
end

-- Split into lines the way the editor's document model does: on "\n", with a
-- trailing "\r" (CRLF) dropped. A file with no trailing newline still yields
-- its last partial line.
local function split_lines(data)
  local lines = {}
  local start = 1
  while true do
    local nl = data:find("\n", start, true)
    if not nl then
      if start <= #data then lines[#lines + 1] = data:sub(start) end
      break
    end
    local line = data:sub(start, nl - 1)
    if line:sub(-1) == "\r" then line = line:sub(1, -2) end
    lines[#lines + 1] = line
    start = nl + 1
  end
  return lines
end

-- One digest per line, plus a readable dump for failure triage.
local function tokenize_file(path, syn)
  local lines = split_lines(read_file(path))
  local digests, dump = {}, {}
  local state = nil
  for i, line in ipairs(lines) do
    local ok, tokens, new_state = pcall(tokenizer.tokenize, syn, line, state)
    if not ok then
      -- The tokenizer raised (e.g. invalid UTF-8 on an unpatched tree).
      -- Record that fact -- keyed to the line content only, not the error
      -- text, which carries volatile build paths -- so a fix that makes the
      -- line tokenize shows up here as a diff. Then carry on with cleared
      -- state.
      digests[i] = "raised:" .. string.format("%016x", fnv1a(FNV_OFFSET, line))
      dump[i] = string.format("%4d | <raised> %s", i, tostring(tokens))
      state = nil
      goto continue
    end
    local h = FNV_OFFSET
    h = fnv1a(h, line)
    h = fnv1a(h, "\30" .. tostring(#tokens))
    local parts = {}
    for j = 1, #tokens, 2 do
      local ttype, ttext = tokens[j], tokens[j + 1]
      -- A token type is normally a string; the tokenizer can also emit a
      -- table here (a subsyntax delimiter whose end match captured nothing).
      -- Flatten it deterministically rather than choke on it.
      if type(ttype) == "table" then ttype = "{" .. table.concat(ttype, ",") .. "}" end
      h = fnv1a(h, "\31" .. tostring(ttype) .. "\31" .. tostring(ttext))
      parts[#parts + 1] = tostring(ttype) .. "=" .. tostring(ttext)
    end
    h = fnv1a(h, "\29" .. tostring(new_state))
    digests[i] = string.format("%016x", h)
    dump[i] = string.format("%4d | %s", i, table.concat(parts, "  \194\183  "))
    state = new_state
    ::continue::
  end
  return digests, dump
end

local function list_corpus()
  local names = {}
  for _, name in ipairs(system.list_dir(corpus_dir) or {}) do
    if not name:match("^%.") then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

local function compute()
  -- We never call core.init(), so the thread registry doesn't exist.
  -- language_md registers a cosmetic theme/font thread at require time;
  -- neutralise it -- it has nothing to do with tokenizing.
  core.threads = core.threads or {}
  core.add_thread = function() end
  for _, lang in ipairs(LANGUAGES) do require("plugins." .. lang) end
  local result = {}
  for _, name in ipairs(list_corpus()) do
    local path = corpus_dir .. "/" .. name
    local syn = syntax.get(name)
    local digests, dump = tokenize_file(path, syn)
    result[#result + 1] = {
      name = name, syntax = syn.name or "?", digests = digests, dump = dump,
    }
  end
  return result
end

local function serialize(result)
  local out = { "# lite-xl tokenizer golden corpus",
                "# regenerate with: test/tokenizer/run.sh record",
                "" }
  for _, file in ipairs(result) do
    out[#out + 1] = string.format("## %s\t[%s]\t%d lines",
      file.name, file.syntax, #file.digests)
    for i, d in ipairs(file.digests) do
      out[#out + 1] = i .. " " .. d
    end
    out[#out + 1] = ""
  end
  return table.concat(out, "\n")
end

local function parse_golden(text)
  local files, cur = {}, nil
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local name = line:match("^## ([^\t]+)")
    if name then
      cur = { name = name, digests = {} }
      files[#files + 1] = cur
      files[name] = cur
    elseif cur then
      local i, d = line:match("^(%d+) (%S+)$")
      if i then cur.digests[tonumber(i)] = d end
    end
  end
  return files
end

local function do_record()
  local result = compute()
  local f = assert(io.open(golden_path, "wb"))
  f:write(serialize(result))
  f:close()
  local total = 0
  for _, file in ipairs(result) do total = total + #file.digests end
  io.stdout:write(string.format(
    "recorded %d files, %d lines -> %s\n", #result, total, golden_path))
  return 0
end

local function do_check()
  local gf = io.open(golden_path, "rb")
  if not gf then
    io.stdout:write("no golden.txt; run: test/tokenizer/run.sh record\n")
    return 2
  end
  local golden = parse_golden(gf:read("*a"))
  gf:close()

  local result = compute()
  local mismatches, dumped = {}, {}

  local seen = {}
  for _, file in ipairs(result) do
    seen[file.name] = true
    local want = golden[file.name]
    if not want then
      mismatches[#mismatches + 1] = file.name .. ": not in golden (new corpus file)"
    else
      if #want.digests ~= #file.digests then
        mismatches[#mismatches + 1] = string.format(
          "%s: line count %d -> %d", file.name, #want.digests, #file.digests)
      end
      for i = 1, math.max(#want.digests, #file.digests) do
        if want.digests[i] ~= file.digests[i] then
          mismatches[#mismatches + 1] = string.format(
            "%s:%d  %s -> %s", file.name, i,
            want.digests[i] or "(none)", file.digests[i] or "(none)")
          if not dumped[file.name] then
            dumped[file.name] = true
            pcall(system.mkdir, actual_dir)
            local df = io.open(actual_dir .. "/" .. file.name .. ".tokens", "wb")
            if df then
              df:write(table.concat(file.dump, "\n") .. "\n")
              df:close()
            end
          end
        end
      end
    end
  end
  for name in pairs(golden) do
    if type(name) == "string" and not seen[name] then
      mismatches[#mismatches + 1] = name .. ": in golden but missing from corpus"
    end
  end

  if #mismatches == 0 then
    local total = 0
    for _, file in ipairs(result) do total = total + #file.digests end
    io.stdout:write(string.format("ok: %d files, %d lines match golden\n",
      #result, total))
    return 0
  end

  io.stdout:write(string.format("FAIL: %d mismatch(es)\n", #mismatches))
  for i = 1, math.min(#mismatches, 25) do
    io.stdout:write("  " .. mismatches[i] .. "\n")
  end
  if #mismatches > 25 then
    io.stdout:write(string.format("  ... and %d more\n", #mismatches - 25))
  end
  local names = {}
  for n in pairs(dumped) do names[#names + 1] = n end
  if #names > 0 then
    io.stdout:write("current token streams written under " .. actual_dir .. "/\n")
  end
  return 1
end

function M.init()
  local ok, code_or_err = xpcall(function()
    if mode == "record" then return do_record() end
    if mode == "check" then return do_check() end
    io.stdout:write("usage: run.lua <check|record> [base-dir]\n")
    return 2
  end, debug.traceback)
  if ok then
    M.code = code_or_err
  else
    io.stdout:write(tostring(code_or_err) .. "\n")
    M.code = 3
  end
end

function M.run()
  os.exit(M.code or 0)
end

return M
