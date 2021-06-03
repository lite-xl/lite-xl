-- mod-version:1 -- lite-xl 1.16
local core = require "core"
local common = require "core.common"
local config = require "core.config"
local command = require "core.command"
local style = require "core.style"
local keymap = require "core.keymap"
local translate = require "core.doc.translate"
local RootView = require "core.rootview"
local DocView = require "core.docview"
local Doc = require "core.doc"

-- Amount of characters that need to be written for autocomplete
config.autocomplete_min_len = config.autocomplete_min_len or 1
-- The max amount of visible items
config.autocomplete_max_height = config.autocomplete_max_height or 6
-- The max amount of scrollable items
config.autocomplete_max_suggestions = config.autocomplete_max_suggestions or 100
-- Maximum amount of symbols to cache per document
config.max_symbols = config.max_symbols or 2000

local autocomplete = {}

autocomplete.map = {}
autocomplete.map_manually = {}
autocomplete.on_close = nil

-- Flag that indicates if the autocomplete box was manually triggered
-- with the autocomplete.complete() function to prevent the suggestions
-- from getting cluttered with arbitrary document symbols by using the
-- autocomplete.map_manually table.
local triggered_manually = false

local mt = { __tostring = function(t) return t.text end }

function autocomplete.add(t, triggered_manually)
  local items = {}
  for text, info in pairs(t.items) do
    if type(info) == "table" then
      table.insert(
        items,
        setmetatable(
          {
            text = text,
            info = info.info,
            desc = info.desc,  -- Description shown on item selected
            cb = info.cb,      -- A callback called once when item is selected
            data = info.data   -- Optional data that can be used on cb
          },
          mt
        )
      )
    else
      info = (type(info) == "string") and info
      table.insert(items, setmetatable({ text = text, info = info }, mt))
    end
  end

  if not triggered_manually then
    autocomplete.map[t.name] =  { files = t.files or ".*", items = items }
  else
    autocomplete.map_manually[t.name] =  { files = t.files or ".*", items = items }
  end
end

--
-- Thread that scans open document symbols and cache them
--
local max_symbols = config.max_symbols

core.add_thread(function()
  local cache = setmetatable({}, { __mode = "k" })

  local function get_symbols(doc)
    if doc.disable_symbols then return {} end
    local i = 1
    local s = {}
    local symbols_count = 0
    while i < #doc.lines do
      for sym in doc.lines[i]:gmatch(config.symbol_pattern) do
        if not s[sym] then
          symbols_count = symbols_count + 1
          if symbols_count > max_symbols then
            s = nil
            doc.disable_symbols = true
            core.status_view:show_message("!", style.accent,
              "Too many symbols in document "..doc.filename..
              ": stopping auto-complete for this document according to config.max_symbols.")
            collectgarbage('collect')
            return {}
          end
          s[sym] = true
        end
      end
      i = i + 1
      if i % 100 == 0 then coroutine.yield() end
    end
    return s
  end

  local function cache_is_valid(doc)
    local c = cache[doc]
    return c and c.last_change_id == doc:get_change_id()
  end

  while true do
    local symbols = {}

    -- lift all symbols from all docs
    for _, doc in ipairs(core.docs) do
      -- update the cache if the doc has changed since the last iteration
      if not cache_is_valid(doc) then
        cache[doc] = {
          last_change_id = doc:get_change_id(),
          symbols = get_symbols(doc)
        }
      end
      -- update symbol set with doc's symbol set
      for sym in pairs(cache[doc].symbols) do
        symbols[sym] = true
      end
      coroutine.yield()
    end

    -- update symbols list
    autocomplete.add { name = "open-docs", items = symbols }

    -- wait for next scan
    local valid = true
    while valid do
      coroutine.yield(1)
      for _, doc in ipairs(core.docs) do
        if not cache_is_valid(doc) then
          valid = false
        end
      end
    end

  end
end)


local partial = ""
local suggestions_idx = 1
local suggestions = {}
local last_line, last_col


local function reset_suggestions()
  suggestions_idx = 1
  suggestions = {}

  triggered_manually = false

  local doc = core.active_view.doc
  if autocomplete.on_close then
    autocomplete.on_close(doc, suggestions[suggestions_idx])
    autocomplete.on_close = nil
  end
end

local function in_table(value, table_array)
  for i, element in pairs(table_array) do
    if element == value then
      return true
    end
  end

  return false
end

local function update_suggestions()
  local doc = core.active_view.doc
  local filename = doc and doc.filename or ""

  local map = autocomplete.map

  if triggered_manually then
    map = autocomplete.map_manually
  end

  -- get all relevant suggestions for given filename
  local items = {}
  for _, v in pairs(map) do
    if common.match_pattern(filename, v.files) then
      for _, item in pairs(v.items) do
        table.insert(items, item)
      end
    end
  end

  -- fuzzy match, remove duplicates and store
  items = common.fuzzy_match(items, partial)
  local j = 1
  for i = 1, config.autocomplete_max_suggestions do
    suggestions[i] = items[j]
    while items[j] and items[i].text == items[j].text do
      items[i].info = items[i].info or items[j].info
      j = j + 1
    end
  end
end

local function get_partial_symbol()
  local doc = core.active_view.doc
  local line2, col2 = doc:get_selection()
  local line1, col1 = doc:position_offset(line2, col2, translate.start_of_word)
  return doc:get_text(line1, col1, line2, col2)
end

local function get_active_view()
  if getmetatable(core.active_view) == DocView then
    return core.active_view
  end
end

local function get_suggestions_rect(av)
  if #suggestions == 0 then
    return 0, 0, 0, 0
  end

  local line, col = av.doc:get_selection()
  local x, y = av:get_line_screen_position(line)
  x = x + av:get_col_x_offset(line, col - #partial)
  y = y + av:get_line_height() + style.padding.y
  local font = av:get_font()
  local th = font:get_height()

  local max_width = 0
  for _, s in ipairs(suggestions) do
    local w = font:get_width(s.text)
    if s.info then
      w = w + style.font:get_width(s.info) + style.padding.x
    end
    max_width = math.max(max_width, w)
  end

  local ah = config.autocomplete_max_height

  local max_items = #suggestions
  if max_items > ah then
    max_items = ah
  end

  -- additional line to display total items
  max_items = max_items + 1

  if max_width < 150 then
    max_width = 150
  end

  return
    x - style.padding.x,
    y - style.padding.y,
    max_width + style.padding.x * 2,
    max_items * (th + style.padding.y) + style.padding.y
end

local function draw_description_box(text, av, sx, sy, sw, sh)
  local width = 0

  local lines = {}
  for line in string.gmatch(text.."\n", "(.-)\n") do
    width = math.max(width, style.font:get_width(line))
    table.insert(lines, line)
  end

  local height = #lines * style.font:get_height()

  -- draw background rect
  renderer.draw_rect(
    sx + sw + style.padding.x / 4,
    sy,
    width + style.padding.x * 2,
    height + style.padding.y * 2,
    style.background3
  )

  -- draw text
  local lh = style.font:get_height()
  local y = sy + style.padding.y
  local x = sx + sw + style.padding.x / 4

  for _, line in pairs(lines) do
    common.draw_text(
      style.font, style.text, line, "left", x + style.padding.x, y, width, lh
    )
    y = y + lh
  end
end

local function draw_suggestions_box(av)
  if #suggestions <= 0 then
    return
  end

  local ah = config.autocomplete_max_height

  -- draw background rect
  local rx, ry, rw, rh = get_suggestions_rect(av)
  renderer.draw_rect(rx, ry, rw, rh, style.background3)

  -- draw text
  local font = av:get_font()
  local lh = font:get_height() + style.padding.y
  local y = ry + style.padding.y / 2
  local show_count = #suggestions <= ah and #suggestions or ah
  local start_index = suggestions_idx > ah and (suggestions_idx-(ah-1)) or 1

  for i=start_index, start_index+show_count-1, 1 do
    if not suggestions[i] then
      break
    end
    local s = suggestions[i]
    local color = (i == suggestions_idx) and style.accent or style.text
    common.draw_text(font, color, s.text, "left", rx + style.padding.x, y, rw, lh)
    if s.info then
      color = (i == suggestions_idx) and style.text or style.dim
      common.draw_text(style.font, color, s.info, "right", rx, y, rw - style.padding.x, lh)
    end
    y = y + lh
    if suggestions_idx == i then
      if s.cb then
        s.cb(suggestions_idx, s)
        s.cb = nil
        s.data = nil
      end
      if s.desc and #s.desc > 0 then
        draw_description_box(s.desc, av, rx, ry, rw, rh)
      end
    end
  end

  renderer.draw_rect(rx, y, rw, 2, style.caret)
  renderer.draw_rect(rx, y+2, rw, lh, style.background)
  common.draw_text(
    style.font,
    style.accent,
    "Items",
    "left",
    rx + style.padding.x, y, rw, lh
  )
  common.draw_text(
    style.font,
    style.accent,
    tostring(suggestions_idx) .. "/" .. tostring(#suggestions),
    "right",
    rx, y, rw - style.padding.x, lh
  )
end

local function show_autocomplete()
  local av = get_active_view()
  if av then
    -- update partial symbol and suggestions
    partial = get_partial_symbol()

    if #partial >= config.autocomplete_min_len or triggered_manually then
      update_suggestions()

      if not triggered_manually then
        last_line, last_col = av.doc:get_selection()
      else
        local line, col = av.doc:get_selection()
        local char = av.doc:get_char(line, col-1, line, col-1)

        if char:match("%s") or (char:match("%p") and col ~= last_col) then
          reset_suggestions()
        end
      end
    else
      reset_suggestions()
    end

    -- scroll if rect is out of bounds of view
    local _, y, _, h = get_suggestions_rect(av)
    local limit = av.position.y + av.size.y
    if y + h > limit then
      av.scroll.to.y = av.scroll.y + y + h - limit
    end
  end
end

--
-- Patch event logic into RootView and Doc
--
local on_text_input = RootView.on_text_input
local on_text_remove = Doc.remove
local update = RootView.update
local draw = RootView.draw

RootView.on_text_input = function(...)
  on_text_input(...)
  show_autocomplete()
end

Doc.remove = function(self, line1, col1, line2, col2)
  on_text_remove(self, line1, col1, line2, col2)

  if triggered_manually and line1 == line2 then
    if last_col >= col1 then
      reset_suggestions()
    else
      show_autocomplete()
    end
  end
end

RootView.update = function(...)
  update(...)

  local av = get_active_view()
  if av then
    -- reset suggestions if caret was moved
    local line, col = av.doc:get_selection()

    if not triggered_manually then
      if line ~= last_line or col ~= last_col then
        reset_suggestions()
      end
    else
      if line ~= last_line or col < last_col then
        reset_suggestions()
      end
    end
  end
end

RootView.draw = function(...)
  draw(...)

  local av = get_active_view()
  if av then
    -- draw suggestions box after everything else
    core.root_view:defer_draw(draw_suggestions_box, av)
  end
end

--
-- Public functions
--
function autocomplete.open(on_close)
  triggered_manually = true

  if on_close then
    autocomplete.on_close = on_close
  end

  local av = get_active_view()
  last_line, last_col = av.doc:get_selection()
  update_suggestions()
end

function autocomplete.close()
  reset_suggestions()
end

function autocomplete.is_open()
  return #suggestions > 0
end

function autocomplete.complete(completions, on_close)
  reset_suggestions()

  autocomplete.map_manually = {}
  autocomplete.add(completions, true)

  autocomplete.open(on_close)
end

function autocomplete.can_complete()
  if #partial >= config.autocomplete_min_len then
    return true
  end
  return false
end


--
-- Commands
--
local function predicate()
  return get_active_view() and #suggestions > 0
end

command.add(predicate, {
  ["autocomplete:complete"] = function()
    local doc = core.active_view.doc
    local line, col = doc:get_selection()
    local text = suggestions[suggestions_idx].text
    doc:insert(line, col, text)
    doc:remove(line, col, line, col - #partial)
    doc:set_selection(line, col + #text - #partial)
    reset_suggestions()
  end,

  ["autocomplete:previous"] = function()
    suggestions_idx = math.max(suggestions_idx - 1, 1)
  end,

  ["autocomplete:next"] = function()
    suggestions_idx = math.min(suggestions_idx + 1, #suggestions)
  end,

  ["autocomplete:cancel"] = function()
    reset_suggestions()
  end,
})

--
-- Keymaps
--
keymap.add {
  ["tab"]    = "autocomplete:complete",
  ["up"]     = "autocomplete:previous",
  ["down"]   = "autocomplete:next",
  ["escape"] = "autocomplete:cancel",
}


return autocomplete
