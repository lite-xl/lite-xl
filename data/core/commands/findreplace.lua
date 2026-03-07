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

local function dv(rv)
  local is_DocView = rv.active_view:is(DocView) and not rv.active_view:is(CommandView)
  return is_DocView and rv.active_view or last_view
end

local function doc(rv)
  local is_DocView = rv.active_view:is(DocView) and not rv.active_view:is(CommandView)
  return is_DocView and rv.active_view.doc or (last_view and last_view.doc)
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
    last_view:set_selection(line2, col2, line1, col1)
    last_view:scroll_to_line(line2, true, nil, col2)
    found_expression = true
  else
    last_view:set_selection(table.unpack(sel))
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


local function find(dv, label, search_fn)
  last_view, last_sel = dv.root_view.active_view,
    { dv.root_view.active_view:get_selection() }
  local text = last_view.doc:get_text(table.unpack(last_sel))
  found_expression = false

  dv.root_view.status_view:show_tooltip(get_find_tooltip())

  dv.root_view.command_view:enter(label, {
    text = text,
    select_text = true,
    show_suggestions = false,
    submit = function(text, item)
      insert_unique(core.previous_find, text)
      dv.root_view.status_view:remove_tooltip()
      if found_expression then
        last_fn, last_text = search_fn, text
      else
        core.error("Couldn't find %q", text)
        last_view:set_selection(table.unpack(last_sel))
        last_view:scroll_to_make_visible(table.unpack(last_sel))
      end
    end,
    suggest = function(text)
      update_preview(last_sel, search_fn, text)
      last_fn, last_text = search_fn, text
      return core.previous_find
    end,
    cancel = function(explicit)
      dv.root_view.status_view:remove_tooltip()
      if explicit then
        last_view:set_selection(table.unpack(last_sel))
        last_view:scroll_to_make_visible(table.unpack(last_sel))
      end
    end
  })
end


local function replace(dv, kind, default, fn)
  dv.root_view.status_view:show_tooltip(get_find_tooltip())
  dv.root_view.command_view:enter("Find To Replace " .. kind, {
    text = default,
    select_text = true,
    show_suggestions = false,
    submit = function(old)
      insert_unique(core.previous_find, old)

      local s = string.format("Replace %s %q With", kind, old)
      dv.root_view.command_view:enter(s, {
        text = old,
        select_text = true,
        show_suggestions = false,
        submit = function(new)
          dv.root_view.status_view:remove_tooltip()
          insert_unique(core.previous_replace, new)
          local results = dv():replace(function(text)
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
          dv.root_view.status_view:remove_tooltip()
        end
      })
    end,
    suggest = function() return core.previous_find end,
    cancel = function()
      dv.root_view.status_view:remove_tooltip()
    end
  })
end


local function has_unique_selection(rv)
  if not doc(rv) then return false end
  local text = nil
  for idx, line1, col1, line2, col2 in dv(rv):get_selections(true, true) do
    if line1 == line2 and col1 == col2 then return false end
    local selection = doc(rv):get_text(line1, col1, line2, col2)
    if text ~= nil and text ~= selection then return false end
    text = selection
  end
  return text ~= nil, dv(rv)
end

local function is_in_selection(line, col, l1, c1, l2, c2)
  if line < l1 or line > l2 then return false end
  if line == l1 and col <= c1 then return false end
  if line == l2 and col > c2 then return false end
  return true
end

local function is_in_any_selection(dv, line, col)
  for idx, l1, c1, l2, c2 in dv:get_selections(true, false) do
    if is_in_selection(line, col, l1, c1, l2, c2) then return true end
  end
  return false
end

local function select_add_next(dv, all)
  local il1, ic1
  for _, l1, c1, l2, c2 in dv:get_selections(true, true) do
    if not il1 then
      il1, ic1 = l1, c1
    end
    local text = doc(dv.root_view):get_text(l1, c1, l2, c2)
    repeat
      l1, c1, l2, c2 = search.find(doc(dv.root_view), l2, c2, text, { wrap = true })
      if l1 == il1 and c1 == ic1 then break end
      if l2 and not is_in_any_selection(dv, l2, c2) then
        dv:add_selection(l2, c2, l1, c1)
        if not all then
          dv:scroll_to_make_visible(l2, c2)
          return
        end
      end
    until not all or not l2
    if all then break end
  end
end

local function select_next(dv, reverse)
  local l1, c1, l2, c2 = dv:get_selection(true)
  local text = doc():get_text(l1, c1, l2, c2)
  if reverse then
    l1, c1, l2, c2 = search.find(doc(dv.root_view), l1, c1, text, { wrap = true, reverse = true })
  else
    l1, c1, l2, c2 = search.find(doc(dv.root_view), l2, c2, text, { wrap = true })
  end
  if l2 then dv():set_selection(l2, c2, l1, c1) end
end

---@param in_selection? boolean whether to replace in the selections only, or in the whole file.
local function find_replace(dv, in_selection)
  local l1, c1, l2, c2 = dv:get_selection()
  local selected_text = ""
  if not in_selection then
    selected_text = doc(dv.root_view):get_text(l1, c1, l2, c2)
    dv:set_selection(l2, c2, l2, c2)
  end
  replace(dv, "Text", l1 == l2 and selected_text or "", function(text, old, new)
    if not find_regex then
      return text:gsub(old:gsub("%W", "%%%1"), new:gsub("%%", "%%%%"), nil)
    end
    local result, matches = regex.gsub(regex.compile(old, "m"), text, new)
    return result, matches
  end)
end

command.add(has_unique_selection, {
  ["find-replace:select-next"] = select_next,
  ["find-replace:select-previous"] = function(dv) select_next(dv, true) end,
  ["find-replace:select-add-next"] = select_add_next,
  ["find-replace:select-add-all"] = function() select_add_next(dv, true) end
})

command.add("core.docview!", {
  ["find-replace:find"] = function(dv)
    find(dv, "Find Text", function(doc, line, col, text, case_sensitive, find_regex, find_reverse)
      local opt = { wrap = true, no_case = not case_sensitive, regex = find_regex, reverse = find_reverse }
      return search.find(doc, line, col, text, opt)
    end)
  end,

  ["find-replace:replace"] = function(dv)
    find_replace(dv)
  end,

  ["find-replace:replace-in-selection"] = function(dv)
    find_replace(dv, true)
  end,

  ["find-replace:replace-symbol"] = function(dv)
    local first = ""
    if dv:has_selection() then
      local text = doc(dv.root_view):get_text(dv:get_selection())
      first = text:match(config.symbol_pattern) or ""
    end
    replace(dv, "Symbol", first, function(text, old, new)
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

local function valid_for_finding(root_view)
  -- Allow using this while in the CommandView
  if root_view.active_view:is(CommandView) and last_view then
    return true, last_view
  end
  return root_view.active_view:is(DocView), root_view.active_view
end

command.add(valid_for_finding, {
  ["find-replace:repeat-find"] = function(dv)
    if not last_fn then
      core.error("No find to continue from")
    else
      local sl1, sc1, sl2, sc2 = dv:get_selection(true)
      local line1, col1, line2, col2 = last_fn(dv.doc, sl2, sc2, last_text, case_sensitive, find_regex, false)
      if line1 then
        dv:set_selection(line2, col2, line1, col1)
        dv:scroll_to_line(line2, true, nil, col2)
      else
        core.error("Couldn't find %q", last_text)
      end
    end
  end,

  ["find-replace:previous-find"] = function(dv)
    if not last_fn then
      core.error("No find to continue from")
    else
      local sl1, sc1, sl2, sc2 = dv:get_selection(true)
      local line1, col1, line2, col2 = last_fn(dv.doc, sl1, sc1, last_text, case_sensitive, find_regex, true)
      if line1 then
        dv:set_selection(line2, col2, line1, col1)
        dv:scroll_to_line(line2, true, nil, col2)
      else
        core.error("Couldn't find %q", last_text)
      end
    end
  end,
})

command.add(CommandView, {
  ["find-replace:toggle-sensitivity"] = function(cv)
    case_sensitive = not case_sensitive
    cv.root_view.status_view:show_tooltip(get_find_tooltip())
    if last_sel then update_preview(last_sel, last_fn, last_text) end
  end,

  ["find-replace:toggle-regex"] = function(cv)
    find_regex = not find_regex
    cv.root_view.status_view:show_tooltip(get_find_tooltip())
    if last_sel then update_preview(last_sel, last_fn, last_text) end
  end
})
