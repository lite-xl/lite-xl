-- mod-version:3
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

config.plugins.autocomplete = common.merge({
  -- Amount of characters that need to be written for autocomplete
  min_len = 3,
  -- The max amount of visible items
  max_height = 6,
  -- The max amount of scrollable items
  max_suggestions = 100,
  -- Maximum amount of symbols to cache per document
  max_symbols = 4000,
  -- Font size of the description box
  desc_font_size = 12,
  -- The config specification used by gui generators
  config_spec = {
    name = "Autocomplete",
    {
      label = "Minimum Length",
      description = "Amount of characters that need to be written for autocomplete to popup.",
      path = "min_len",
      type = "number",
      default = 3,
      min = 1,
      max = 5
    },
    {
      label = "Maximum Height",
      description = "The maximum amount of visible items.",
      path = "max_height",
      type = "number",
      default = 6,
      min = 1,
      max = 20
    },
    {
      label = "Maximum Suggestions",
      description = "The maximum amount of scrollable items.",
      path = "max_suggestions",
      type = "number",
      default = 100,
      min = 10,
      max = 10000
    },
    {
      label = "Maximum Symbols",
      description = "Maximum amount of symbols to cache per document.",
      path = "max_symbols",
      type = "number",
      default = 4000,
      min = 1000,
      max = 10000
    },
    {
      label = "Description Font Size",
      description = "Font size of the description box.",
      path = "desc_font_size",
      type = "number",
      default = 12,
      min = 8
    }
  }
}, config.plugins.autocomplete)

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

function autocomplete.add(t, manually_triggered)
  local items = {}
  for text, info in pairs(t.items) do
    if type(info) == "table" then
      table.insert(
        items,
        setmetatable(
          {
            text = text,
            info = info.info,
            desc = info.desc,          -- Description shown on item selected
            onhover = info.onhover,    -- A callback called once when item is hovered
            onselect = info.onselect,  -- A callback called when item is selected
            data = info.data           -- Optional data that can be used on cb
          },
          mt
        )
      )
    else
      info = (type(info) == "string") and info
      table.insert(items, setmetatable({ text = text, info = info }, mt))
    end
  end

  if not manually_triggered then
    autocomplete.map[t.name] =  { files = t.files or ".*", items = items }
  else
    autocomplete.map_manually[t.name] =  { files = t.files or ".*", items = items }
  end
end

--
-- Thread that scans open document symbols and cache them
--
local max_symbols = config.plugins.autocomplete.max_symbols

core.add_thread(function()
  local cache = setmetatable({}, { __mode = "k" })

  local function get_syntax_symbols(symbols, doc)
    if doc.syntax then
      for sym in pairs(doc.syntax.symbols) do
        symbols[sym] = true
      end
    end
  end

  local function get_symbols(doc)
    local s = {}
    get_syntax_symbols(s, doc)
    if doc.disable_symbols then return s end
    local i = 1
    local symbols_count = 0
    while i <= #doc.lines do
      for sym in doc.lines[i]:gmatch(config.symbol_pattern) do
        if not s[sym] then
          symbols_count = symbols_count + 1
          if symbols_count > max_symbols then
            s = nil
            doc.disable_symbols = true
            local filename_message
            if doc.filename then
              filename_message = "document " .. doc.filename
            else
              filename_message = "unnamed document"
            end
            core.status_view:show_message("!", style.accent,
              "Too many symbols in "..filename_message..
              ": stopping auto-complete for this document according to "..
              "config.plugins.autocomplete.max_symbols."
            )
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
          break
        end
      end
    end

  end
end)


local partial = ""
local suggestions_offset = 1
local suggestions_idx = 1
local suggestions = {}
local last_line, last_col


local function reset_suggestions()
  suggestions_offset = 1
  suggestions_idx = 1
  suggestions = {}

  triggered_manually = false

  local doc = core.active_view.doc
  if autocomplete.on_close then
    autocomplete.on_close(doc, suggestions[suggestions_idx])
    autocomplete.on_close = nil
  end
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
  for i = 1, config.plugins.autocomplete.max_suggestions do
    suggestions[i] = items[j]
    while items[j] and items[i].text == items[j].text do
      items[i].info = items[i].info or items[j].info
      j = j + 1
    end
  end
  suggestions_idx = 1
  suggestions_offset = 1
end

local function get_partial_symbol()
  local doc = core.active_view.doc
  local line2, col2 = doc:get_selection()
  local line1, col1 = doc:position_offset(line2, col2, translate.start_of_word)
  return doc:get_text(line1, col1, line2, col2)
end

local function get_active_view()
  if core.active_view:is(DocView) then
    return core.active_view
  end
end

local last_max_width = 0
local function get_suggestions_rect(av)
  if #suggestions == 0 then
    last_max_width = 0
    return 0, 0, 0, 0
  end

  local line, col = av.doc:get_selection()
  local x, y = av:get_line_screen_position(line, col - #partial)
  y = y + av:get_line_height() + style.padding.y
  local font = av:get_font()
  local th = font:get_height()

  local ah = config.plugins.autocomplete.max_height

  local max_items = math.min(ah, #suggestions)

  local show_count = math.min(#suggestions, ah)
  local start_index = math.max(suggestions_idx-(ah-1), 1)

  local max_width = 0
  for i = start_index, start_index + show_count - 1 do
    local s = suggestions[i]
    local w = font:get_width(s.text)
    if s.info then
      w = w + style.font:get_width(s.info) + style.padding.x
    end
    max_width = math.max(max_width, w)
  end
  max_width = math.max(last_max_width, max_width)
  last_max_width = max_width

  max_width = max_width + style.padding.x * 2
  x = x - style.padding.x

  -- additional line to display total items
  max_items = max_items + 1

  if max_width > core.root_view.size.x then
    max_width = core.root_view.size.x
  end
  if max_width < 150 * SCALE then
    max_width = 150 * SCALE
  end

  -- if portion not visiable to right, reposition to DocView right margin
  if x + max_width > core.root_view.size.x then
    x = (av.size.x + av.position.x) - max_width
  end

  return
    x,
    y - style.padding.y,
    max_width,
    max_items * (th + style.padding.y) + style.padding.y
end

local function wrap_line(line, max_chars)
  if #line > max_chars then
    local lines = {}
    local line_len = #line
    local new_line = ""
    local prev_char = ""
    local position = 0
    local indent = line:match("^%s+")
    for char in line:gmatch(".") do
      position = position + 1
      if #new_line < max_chars then
        new_line = new_line .. char
        prev_char = char
        if position >= line_len then
          table.insert(lines, new_line)
        end
      else
        if
          not prev_char:match("%s")
          and
          not string.sub(line, position+1, 1):match("%s")
          and
          position < line_len
        then
          new_line = new_line .. "-"
        end
        table.insert(lines, new_line)
        if indent then
          new_line = indent .. char
        else
          new_line = char
        end
      end
    end
    return lines
  end
  return line
end

local previous_scale = SCALE
local desc_font = style.code_font:copy(
  config.plugins.autocomplete.desc_font_size * SCALE
)
local function draw_description_box(text, av, sx, sy, sw, sh)
  if previous_scale ~= SCALE then
    desc_font = style.code_font:copy(
      config.plugins.autocomplete.desc_font_size * SCALE
    )
    previous_scale = SCALE
  end

  local font = desc_font
  local lh = font:get_height()
  local y = sy + style.padding.y
  local x = sx + sw + style.padding.x / 4
  local width = 0
  local char_width = font:get_width(" ")
  local draw_left = false;

  local max_chars = 0
  if sx - av.position.x < av.size.x - (sx - av.position.x) - sw then
    max_chars = (((av.size.x+av.position.x) - x) / char_width) - 5
  else
    draw_left = true;
    max_chars = (
      (sx - av.position.x - (style.padding.x / 4) - style.scrollbar_size)
      / char_width
    ) - 5
  end

  local lines = {}
  for line in string.gmatch(text.."\n", "(.-)\n") do
    local wrapper_lines = wrap_line(line, max_chars)
    if type(wrapper_lines) == "table" then
      for _, wrapped_line in pairs(wrapper_lines) do
        width = math.max(width, font:get_width(wrapped_line))
        table.insert(lines, wrapped_line)
      end
    else
      width = math.max(width, font:get_width(line))
      table.insert(lines, line)
    end
  end

  if draw_left then
    x = sx - (style.padding.x / 4) - width - (style.padding.x * 2)
  end

  local height = #lines * font:get_height()

  -- draw background rect
  renderer.draw_rect(
    x,
    sy,
    width + style.padding.x * 2,
    height + style.padding.y * 2,
    style.background3
  )

  -- draw text
  for _, line in pairs(lines) do
    common.draw_text(
      font, style.text, line, "left",
      x + style.padding.x, y, width, lh
    )
    y = y + lh
  end
end

local function draw_suggestions_box(av)
  if #suggestions <= 0 then
    return
  end

  local ah = config.plugins.autocomplete.max_height

  -- draw background rect
  local rx, ry, rw, rh = get_suggestions_rect(av)
  renderer.draw_rect(rx, ry, rw, rh, style.background3)

  -- draw text
  local font = av:get_font()
  local lh = font:get_height() + style.padding.y
  local y = ry + style.padding.y / 2
  local show_count = math.min(#suggestions, ah)
  local start_index = suggestions_offset

  for i=start_index, start_index+show_count-1, 1 do
    if not suggestions[i] then
      break
    end
    local s = suggestions[i]

    local info_size = s.info and (style.font:get_width(s.info) + style.padding.x) or style.padding.x

    local color = (i == suggestions_idx) and style.accent or style.text
    -- Push clip to avoid that the suggestion text gets drawn over suggestion type/icon
    core.push_clip_rect(rx + style.padding.x, y, rw - info_size - style.padding.x, lh)
    local x_adv = common.draw_text(font, color, s.text, "left", rx + style.padding.x, y, rw, lh)
    core.pop_clip_rect()
    -- If the text wasn't fully visible, draw an ellipsis
    if x_adv > rx + rw - info_size then
      local ellipsis_size = font:get_width("…")
      local ell_x = rx + rw - info_size - ellipsis_size
      renderer.draw_rect(ell_x, y, ellipsis_size, lh, style.background3)
      common.draw_text(font, color, "…", "left", ell_x, y, ellipsis_size, lh)
    end
    if s.info then
      color = (i == suggestions_idx) and style.text or style.dim
      common.draw_text(style.font, color, s.info, "right", rx, y, rw - style.padding.x, lh)
    end
    y = y + lh
    if suggestions_idx == i then
      if s.onhover then
        s.onhover(suggestions_idx, s)
        s.onhover = nil
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

    if #partial >= config.plugins.autocomplete.min_len or triggered_manually then
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
  if av then
    partial = get_partial_symbol()
    last_line, last_col = av.doc:get_selection()
    update_suggestions()
  end
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
  if #partial >= config.plugins.autocomplete.min_len then
    return true
  end
  return false
end


--
-- Commands
--
local function predicate()
  local active_docview = get_active_view()
  return active_docview and #suggestions > 0, active_docview
end

command.add(predicate, {
  ["autocomplete:complete"] = function(dv)
    local doc = dv.doc
    local item = suggestions[suggestions_idx]
    local text = item.text
    local inserted = false
    if item.onselect then
      inserted = item.onselect(suggestions_idx, item)
    end
    if not inserted then
      local current_partial = get_partial_symbol()
      local sz = #current_partial

      for _, line1, col1, line2, _ in doc:get_selections(true) do
        local n = col1 - 1
        local line = doc.lines[line1]
        for i = 1, sz + 1 do
          local j = sz - i
          local subline = line:sub(n - j, n)
          local subpartial = current_partial:sub(i, -1)
          if subpartial == subline then
            doc:remove(line1, col1, line2, n - j)
            break
          end
        end
      end

      doc:text_input(item.text)
    end
    reset_suggestions()
  end,

  ["autocomplete:previous"] = function()
    suggestions_idx = (suggestions_idx - 2) % #suggestions + 1

    local ah = math.min(config.plugins.autocomplete.max_height, #suggestions)
    if suggestions_offset > suggestions_idx then
      suggestions_offset = suggestions_idx
    elseif suggestions_offset + ah < suggestions_idx + 1 then
      suggestions_offset = suggestions_idx - ah + 1
    end
  end,

  ["autocomplete:next"] = function()
    suggestions_idx = (suggestions_idx % #suggestions) + 1

    local ah = math.min(config.plugins.autocomplete.max_height, #suggestions)
    if suggestions_offset + ah < suggestions_idx + 1 then
      suggestions_offset = suggestions_idx - ah + 1
    elseif suggestions_offset > suggestions_idx then
      suggestions_offset = suggestions_idx
    end
  end,

  ["autocomplete:cycle"] = function()
    local newidx = suggestions_idx + 1
    suggestions_idx = newidx > #suggestions and 1 or newidx
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
