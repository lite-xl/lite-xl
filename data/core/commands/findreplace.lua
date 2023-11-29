local core = require "core"
local command = require "core.command"
local config = require "core.config"
local search = require "core.doc.search"
local keymap = require "core.keymap"
local DocView = require "core.docview"
local CommandView = require "core.commandview"
local StatusView = require "core.statusview"

local last_view, last_fn, last_text, last_sel

local case_sensitive = config.find_case_sensitive or false
local find_regex = config.find_regex or false
local found_expression

local function doc()
  local is_DocView = core.active_view:is(DocView) and not core.active_view:is(CommandView)
  return is_DocView and core.active_view.doc or (last_view and last_view.doc)
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
    found_expression = true
  else
    last_view.doc:set_selection(table.unpack(sel))
    found_expression = false
  end
end


local function insert_unique(t, v)
  local n = #t
  for i = 1, n do
    if t[i] == v then
      table.remove(t, i)
      break
    end
  end
  table.insert(t, 1, v)
end


local function find(label, search_fn)
  last_view, last_sel = core.active_view,
    { core.active_view.doc:get_selection() }
  local text = last_view.doc:get_text(table.unpack(last_sel))
  found_expression = false

  core.status_view:show_tooltip(get_find_tooltip())

  core.command_view:enter(label, {
    text = text,
    select_text = true,
    show_suggestions = false,
    submit = function(text, item)
      insert_unique(core.previous_find, text)
      core.status_view:remove_tooltip()
      if found_expression then
        last_fn, last_text = search_fn, text
      else
        core.error("Couldn't find %q", text)
        last_view.doc:set_selection(table.unpack(last_sel))
        last_view:scroll_to_make_visible(table.unpack(last_sel))
      end
    end,
    suggest = function(text)
      update_preview(last_sel, search_fn, text)
      last_fn, last_text = search_fn, text
      return core.previous_find
    end,
    cancel = function(explicit)
      core.status_view:remove_tooltip()
      if explicit then
        last_view.doc:set_selection(table.unpack(last_sel))
        last_view:scroll_to_make_visible(table.unpack(last_sel))
      end
    end
  })
end


local function replace(kind, default, fn)
  core.status_view:show_tooltip(get_find_tooltip())
  core.command_view:enter("Find To Replace " .. kind, {
    text = default,
    select_text = true,
    show_suggestions = false,
    submit = function(old)
      insert_unique(core.previous_find, old)

      local s = string.format("Replace %s %q With", kind, old)
      core.command_view:enter(s, {
        text = old,
        select_text = true,
        show_suggestions = false,
        submit = function(new)
          core.status_view:remove_tooltip()
          insert_unique(core.previous_replace, new)
          local results = doc():replace(function(text)
            return fn(text, old, new)
          end)
          local n = 0
          for _,v in pairs(results) do
            n = n + v
          end
          core.log("Replaced %d instance(s) of %s %q with %q", n, kind, old, new)
        end,
        suggest = function() return core.previous_replace end,
        cancel = function()
          core.status_view:remove_tooltip()
        end
      })
    end,
    suggest = function() return core.previous_find end,
    cancel = function()
      core.status_view:remove_tooltip()
    end
  })
end

local function has_selection()
  return core.active_view:is(DocView) and core.active_view.doc:has_selection()
end

local function has_unique_selection()
  if not doc() then return false end
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

local function select_add_next(all)
  local il1, ic1
  for _, l1, c1, l2, c2 in doc():get_selections(true, true) do
    if not il1 then
      il1, ic1 = l1, c1
    end
    local text = doc():get_text(l1, c1, l2, c2)
    repeat
      l1, c1, l2, c2 = search.find(doc(), l2, c2, text, { wrap = true })
      if l1 == il1 and c1 == ic1 then break end
      if l2 and not is_in_any_selection(l2, c2) then
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

local function select_next(reverse)
  local l1, c1, l2, c2 = doc():get_selection(true)
  local text = doc():get_text(l1, c1, l2, c2)
  if reverse then
    l1, c1, l2, c2 = search.find(doc(), l1, c1, text, { wrap = true, reverse = true })
  else
    l1, c1, l2, c2 = search.find(doc(), l2, c2, text, { wrap = true })
  end
  if l2 then doc():set_selection(l2, c2, l1, c1) end
end

command.add(has_unique_selection, {
  ["find-replace:select-next"] = select_next,
  ["find-replace:select-previous"] = function() select_next(true) end,
  ["find-replace:select-add-next"] = select_add_next,
  ["find-replace:select-add-all"] = function() select_add_next(true) end
})

command.add("core.docview!", {
  ["find-replace:find"] = function()
    find("Find Text", function(doc, line, col, text, case_sensitive, find_regex, find_reverse)
      local opt = { wrap = true, no_case = not case_sensitive, regex = find_regex, reverse = find_reverse }
      return search.find(doc, line, col, text, opt)
    end)
  end,

  ["find-replace:replace"] = function()
    local l1, c1, l2, c2 = doc():get_selection()
    local selected_text = doc():get_text(l1, c1, l2, c2)
    replace("Text", l1 == l2 and selected_text or "", function(text, old, new)
      if not find_regex then
        return text:gsub(old:gsub("%W", "%%%1"), new:gsub("%%", "%%%%"), nil)
      end
      local result, matches = regex.gsub(regex.compile(old, "m"), text, new)
      return result, matches
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
  -- Allow using this while in the CommandView
  if core.active_view:is(CommandView) and last_view then
    return true, last_view
  end
  return core.active_view:is(DocView), core.active_view
end

command.add(valid_for_finding, {
  ["find-replace:repeat-find"] = function(dv)
    if not last_fn then
      core.error("No find to continue from")
    else
      local sl1, sc1, sl2, sc2 = dv.doc:get_selection(true)
      local line1, col1, line2, col2 = last_fn(dv.doc, sl2, sc2, last_text, case_sensitive, find_regex, false)
      if line1 then
        dv.doc:set_selection(line2, col2, line1, col1)
        dv:scroll_to_line(line2, true)
      else
        core.error("Couldn't find %q", last_text)
      end
    end
  end,

  ["find-replace:previous-find"] = function(dv)
    if not last_fn then
      core.error("No find to continue from")
    else
      local sl1, sc1, sl2, sc2 = dv.doc:get_selection(true)
      local line1, col1, line2, col2 = last_fn(dv.doc, sl1, sc1, last_text, case_sensitive, find_regex, true)
      if line1 then
        dv.doc:set_selection(line2, col2, line1, col1)
        dv:scroll_to_line(line2, true)
      else
        core.error("Couldn't find %q", last_text)
      end
    end
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
