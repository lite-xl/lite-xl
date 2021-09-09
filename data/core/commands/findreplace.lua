local core = require "core"
local command = require "core.command"
local config = require "core.config"
local search = require "core.doc.search"
local keymap = require "core.keymap"
local DocView = require "core.docview"
local CommandView = require "core.commandview"
local StatusView = require "core.statusview"

local max_last_finds = 50
local last_finds, last_view, last_fn, last_text, last_sel

local case_sensitive = config.find_case_sensitive or false
local find_regex = config.find_regex or false

local function doc()
  return core.active_view:is(DocView) and core.active_view.doc or last_view.doc
end

local function get_find_tooltip()
  local rf = keymap.get_binding("find-replace:repeat-find")
  local ti = keymap.get_binding("find-replace:toggle-sensitivity")
  local tr = keymap.get_binding("find-replace:toggle-regex")
  return (find_regex and "[Regex] " or "") ..
    (case_sensitive and "[Sensitive] " or "") ..
    (rf and ("Press " .. rf .. " to select the next match.") or "") ..
    (ti and (" " .. ti .. " toggles case sensitivity.") or "") ..
    (tr and (" " .. tr .. " toggles regex find.") or "")
end

local function update_preview(sel, search_fn, text)
  local ok, line1, col1, line2, col2 = pcall(search_fn, last_view.doc,
    sel[1], sel[2], text, case_sensitive, find_regex)
  if ok and line1 and text ~= "" then
    last_view.doc:set_selection(line2, col2, line1, col1)
    last_view:scroll_to_line(line2, true)
    return true
  else
    last_view.doc:set_selection(unpack(sel))
    return false
  end
end

local function find(label, search_fn)
  last_view, last_sel, last_finds = core.active_view,
    { core.active_view.doc:get_selection() }, {}
  local text, found = last_view.doc:get_text(unpack(last_sel)), false

  core.command_view:set_text(text, true)
  core.status_view:show_tooltip(get_find_tooltip())

  core.command_view:enter(label, function(text)
    core.status_view:remove_tooltip()
    if found then
      last_fn, last_text = search_fn, text
    else
      core.error("Couldn't find %q", text)
      last_view.doc:set_selection(unpack(last_sel))
      last_view:scroll_to_make_visible(unpack(last_sel))
    end
  end, function(text)
    found = update_preview(last_sel, search_fn, text)
    last_fn, last_text = search_fn, text
  end, function(explicit)
    core.status_view:remove_tooltip()
    if explicit then
      last_view.doc:set_selection(unpack(last_sel))
      last_view:scroll_to_make_visible(unpack(last_sel))
    end
  end)
end


local function replace(kind, default, fn)
  core.command_view:set_text(default, true)

  core.status_view:show_tooltip(get_find_tooltip())
  core.command_view:enter("Find To Replace " .. kind, function(old)
    core.command_view:set_text(old, true)

    local s = string.format("Replace %s %q With", kind, old)
    core.command_view:enter(s, function(new)
      local n = doc():replace(function(text)
        return fn(text, old, new)
      end)
      core.log("Replaced %d instance(s) of %s %q with %q", n, kind, old, new)
    end, function() end, function()
      core.status_view:remove_tooltip()
    end)
  end, function() end, function()
    core.status_view:remove_tooltip()
  end)
end

local function has_selection()
  return core.active_view:is(DocView) and core.active_view.doc:has_selection()
end

local function has_unique_selection()
  if not core.active_view:is(DocView) then return false end
  local text = nil
  for idx, line1, col1, line2, col2 in doc():get_selections(true, true) do
    if line1 == line2 and col1 == col2 then return false end
    local selection = doc():get_text(line1, col1, line2, col2)
    if text ~= nil and text ~= selection then return false end
    text = selection
  end
  return text ~= nil
end

local function is_in_selection(line, col, l1, c1, l2, c2)
  if line < l1 or line > l2 then return false end
  if line == l1 and col <= c1 then return false end
  if line == l2 and col > c2 then return false end
  return true
end

local function is_in_any_selection(line, col)
  for idx, l1, c1, l2, c2 in doc():get_selections(true, false) do
    if is_in_selection(line, col, l1, c1, l2, c2) then return true end
  end
  return false
end

local function select_next(all)
  local il1, ic1 = doc():get_selection(true)
  for idx, l1, c1, l2, c2 in doc():get_selections(true, true) do
    local text = doc():get_text(l1, c1, l2, c2)
    repeat
      l1, c1, l2, c2 = search.find(doc(), l2, c2, text, { wrap = true })
      if l1 == il1 and c1 == ic1 then break end
      if l2 and (all or not is_in_any_selection(l2, c2)) then
        doc():add_selection(l2, c2, l1, c1)
        if not all then
          core.active_view:scroll_to_make_visible(l2, c2)
          return
        end
      end
    until not all or not l2
    if all then break end
  end
end

command.add(has_unique_selection, {
  ["find-replace:select-next"] = function()
    local l1, c1, l2, c2 = doc():get_selection(true)
    local text = doc():get_text(l1, c1, l2, c2)
    l1, c1, l2, c2 = search.find(doc(), l2, c2, text, { wrap = true })
    if l2 then doc():set_selection(l2, c2, l1, c1) end
  end,
  ["find-replace:select-add-next"] = function() select_next(false) end,
  ["find-replace:select-add-all"] = function() select_next(true) end
})

command.add("core.docview", {
  ["find-replace:find"] = function()
    find("Find Text", function(doc, line, col, text, case_sensitive, find_regex)
      local opt = { wrap = true, no_case = not case_sensitive, regex = find_regex }
      return search.find(doc, line, col, text, opt)
    end)
  end,

  ["find-replace:replace"] = function()
    replace("Text", doc():get_text(doc():get_selection(true)), function(text, old, new)
      if not find_regex then
        return text:gsub(old:gsub("%W", "%%%1"), new:gsub("%%", "%%%%"), nil)
      end
      local result, matches = regex.gsub(regex.compile(old, "m"), text, new)
      return result, #matches
    end)
  end,

  ["find-replace:replace-symbol"] = function()
    local first = ""
    if doc():has_selection() then
      local text = doc():get_text(doc():get_selection())
      first = text:match(config.symbol_pattern) or ""
    end
    replace("Symbol", first, function(text, old, new)
      local n = 0
      local res = text:gsub(config.symbol_pattern, function(sym)
        if old == sym then
          n = n + 1
          return new
        end
      end)
      return res, n
    end)
  end,
})

local function valid_for_finding()
  return core.active_view:is(DocView) or core.active_view:is(CommandView)
end

command.add(valid_for_finding, {
  ["find-replace:repeat-find"] = function()
    if not last_fn then
      core.error("No find to continue from")
    else
      local sl1, sc1, sl2, sc2 = doc():get_selection(true)
      local line1, col1, line2, col2 = last_fn(doc(), sl1, sc2, last_text, case_sensitive, find_regex)
      if line1 then
        if last_view.doc ~= doc() then
          last_finds = {}
        end
        if #last_finds >= max_last_finds then
          table.remove(last_finds, 1)
        end
        table.insert(last_finds, { sl1, sc1, sl2, sc2 })
        doc():set_selection(line2, col2, line1, col1)
        last_view:scroll_to_line(line2, true)
      end
    end
  end,

  ["find-replace:previous-find"] = function()
    local sel = table.remove(last_finds)
    if not sel or doc() ~= last_view.doc then
      core.error("No previous finds")
      return
    end
    doc():set_selection(table.unpack(sel))
    last_view:scroll_to_line(sel[3], true)
  end,
})

command.add("core.commandview", {
  ["find-replace:toggle-sensitivity"] = function()
    case_sensitive = not case_sensitive
    core.status_view:show_tooltip(get_find_tooltip())
    if last_sel then update_preview(last_sel, last_fn, last_text) end
  end,

  ["find-replace:toggle-regex"] = function()
    find_regex = not find_regex
    core.status_view:show_tooltip(get_find_tooltip())
    if last_sel then update_preview(last_sel, last_fn, last_text) end
  end
})
