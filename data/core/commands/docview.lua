local core = require "core"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local translate = require "core.doc.translate"
local style = require "core.style"
local DocView = require "core.docview"
local tokenizer = require "core.tokenizer"


local function doc(rv)
  return rv.active_view.doc
end

local function docview(rv)
  return rv.active_view
end

local function append_line_if_last_line(dv, line)
  if line >= #dv.doc.lines then
    dv:insert(line, math.huge, "\n")
  end
end

local function doc_multiline_selections(dv, sort)
  local iter, state, idx, line1, col1, line2, col2 = dv:get_selections(sort)
  return function()
    idx, line1, col1, line2, col2 = iter(state, idx)
    if idx and line2 > line1 and col2 == 1 then
      line2 = line2 - 1
      col2 = #dv.doc.lines[line2]
    end
    return idx, line1, col1, line2, col2
  end
end

local function cut_or_copy(dv, delete)
  local full_text = ""
  local text = ""
  core.cursor_clipboard = {}
  core.cursor_clipboard_whole_line = {}
  for idx, line1, col1, line2, col2 in dv:get_selections(true, true) do
    if line1 ~= line2 or col1 ~= col2 then
      text = dv.doc:get_text(line1, col1, line2, col2)
      full_text = full_text == "" and text or (text .. " " .. full_text)
      core.cursor_clipboard_whole_line[idx] = false
      if delete then
        dv:delete_to_cursor(idx, 0)
      end
    else -- Cut/copy whole line
      -- Remove newline from the text. It will be added as needed on paste.
      text = string.sub(dv.doc.lines[line1], 1, -2)
      full_text = full_text == "" and text .. "\n" or (text .. "\n" .. full_text)
      core.cursor_clipboard_whole_line[idx] = true
      if delete then
        if line1 < #dv.doc.lines then
          dv:remove(line1, 1, line1 + 1, 1)
        elseif #dv.doc.lines == 1 then
          dv:remove(line1, 1, line1, math.huge)
        else
          dv:remove(line1 - 1, math.huge, line1, math.huge)
        end
        dv:set_selections(idx, line1, col1, line2, col2)
      end
    end
    core.cursor_clipboard[idx] = text
  end
  if delete then dv:merge_cursors() end
  core.cursor_clipboard["full"] = full_text
  system.set_clipboard(full_text)
end

local function split_cursor(dv, direction)
  local new_cursors = {}
  for _, line1, col1 in dv:get_selections() do
    if line1 + direction >= 1 and line1 + direction <= #dv.doc.lines then
      table.insert(new_cursors, { line1 + direction, col1 })
    end
  end
  -- add selections in the order that will leave the "last" added one as doc.last_selection
  local start, stop = 1, #new_cursors
  if direction < 0 then
    start, stop = #new_cursors, 1
  end
  for i = start, stop, direction do
    local v = new_cursors[i]
    dv:add_selection(v[1], v[2])
  end
  core.blink_reset()
end

local function set_cursor(dv, x, y, snap_type)
  local line, col = dv:resolve_screen_position(x, y)
  dv:set_selection(line, col, line, col)
  if snap_type == "word" or snap_type == "lines" then
    dv:perform("docview:select-" .. snap_type)
  end
  dv.mouse_selecting = { line, col, snap_type }
  core.blink_reset()
end

local function insert_paste(dv, value, whole_line, idx)
  if whole_line then
    local line1, col1 = dv:get_selection_idx(idx)
    dv.doc:insert(line1, 1, value:gsub("\r", "").."\n")
    -- Because we're inserting at the start of the line,
    -- if the cursor is in the middle of the line
    -- it gets carried to the next line along with the old text.
    -- If it's at the start of the line it doesn't get carried,
    -- so we move it of as many characters as we're adding.
    if col1 == 1 then
      dv:move_to_cursor(idx, #value+1)
    end
  else
    dv:text_input(value:gsub("\r", ""), idx)
  end
end

local write_commands = {
  ["docview:cut"] = function(dv)
    cut_or_copy(dv, true)
  end,

  ["docview:undo"] = function(dv)
    dv:undo()
  end,

  ["docview:redo"] = function(dv)
    dv:redo()
  end,

  ["docview:paste"] = function(dv)
    local clipboard = system.get_clipboard()
    -- If the clipboard has changed since our last look, use that instead
    if core.cursor_clipboard["full"] ~= clipboard then
      core.cursor_clipboard = {}
      core.cursor_clipboard_whole_line = {}
      for idx in dv:get_selections() do
        insert_paste(dv, clipboard, false, idx)
      end
      return
    end
    -- Use internal clipboard(s)
    -- If there are mixed whole lines and normal lines, consider them all as normal
    local only_whole_lines = true
    for _,whole_line in pairs(core.cursor_clipboard_whole_line) do
      if not whole_line then
        only_whole_lines = false
        break
      end
    end
    if #core.cursor_clipboard_whole_line == (#dv.selections/4) then
    -- If we have the same number of clipboards and selections,
    -- paste each clipboard into its corresponding selection
      for idx in dv:get_selections() do
        insert_paste(dv, core.cursor_clipboard[idx], only_whole_lines, idx)
      end
    else
      -- Paste every clipboard and add a selection at the end of each one
      local new_selections = {}
      for idx in dv:get_selections() do
        for cb_idx in ipairs(core.cursor_clipboard_whole_line) do
          insert_paste(dv, core.cursor_clipboard[cb_idx], only_whole_lines, idx)
          if not only_whole_lines then
            table.insert(new_selections, {dv:get_selection_idx(idx)})
          end
        end
        if only_whole_lines then
          table.insert(new_selections, {dv:get_selection_idx(idx)})
        end
      end
      local first = true
      for _,selection in pairs(new_selections) do
        if first then
          dv:set_selection(table.unpack(selection))
          first = false
        else
          dv:add_selection(table.unpack(selection))
        end
      end
    end
  end,

  ["docview:newline"] = function(dv)
    for idx, line, col in dv:get_selections(false, true) do
      local indent = dv.doc.lines[line]:match("^[\t ]*")
      if col <= #indent then
        indent = indent:sub(#indent + 2 - col)
      end
      -- Remove current line if it contains only whitespace
      if not config.keep_newline_whitespace and dv.doc.lines[line]:match("^%s+$") then
        dv.doc:remove(line, 1, line, math.huge)
      end
      dv:text_input("\n" .. indent, idx)
    end
  end,

  ["docview:newline-below"] = function(dv)
    for idx, line in dv:get_selections(false, true) do
      local indent = dv.doc.lines[line]:match("^[\t ]*")
      dv.doc:insert(line, math.huge, "\n" .. indent)
      dv:set_selections(idx, line + 1, math.huge)
    end
  end,

  ["docview:newline-above"] = function(dv)
    for idx, line in dv:get_selections(false, true) do
      local indent = dv.lines[line]:match("^[\t ]*")
      dv.doc:insert(line, 1, indent .. "\n")
      dv:set_selections(idx, line, math.huge)
    end
  end,

  ["docview:delete"] = function(dv)
    for idx, line1, col1, line2, col2 in dv:get_selections(true, true) do
      if line1 == line2 and col1 == col2 and dv.doc.lines[line1]:find("^%s*$", col1) then
        dv.doc:remove(line1, col1, line1, math.huge)
      end
      dv:delete_to_cursor(idx, translate.next_char)
    end
  end,

  ["docview:backspace"] = function(dv)
    local _, indent_size = dv.doc:get_indent_info()
    for idx, line1, col1, line2, col2 in dv:get_selections(true, true) do
      if line1 == line2 and col1 == col2 then
        local text = dv.doc:get_text(line1, 1, line1, col1)
        if #text >= indent_size and text:find("^ *$") then
          dv:delete_to_cursor(idx, 0, -indent_size)
          goto continue
        end
      end
      dv:delete_to_cursor(idx, translate.previous_char)
      ::continue::
    end
  end,

  ["docview:join-lines"] = function(dv)
    for idx, line1, col1, line2, col2 in dv.doc:get_selections(true) do
      if line1 == line2 then line2 = line2 + 1 end
      local text = dv.doc:get_text(line1, 1, line2, math.huge)
      text = text:gsub("(.-)\n[\t ]*", function(x)
        return x:find("^%s*$") and x or x .. " "
      end)
      dv.doc:insert(line1, 1, text)
      dv.doc:remove(line1, #text + 1, line2, math.huge)
      if line1 ~= line2 or col1 ~= col2 then
        dv:set_selections(idx, line1, math.huge)
      end
    end
  end,

  ["docview:indent"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(dv, true) do
      local l1, c1, l2, c2 = dv:indent_text(false, line1, col1, line2, col2)
      if l1 then
        dv:set_selections(idx, l1, c1, l2, c2)
      end
    end
  end,

  ["docview:unindent"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(dv, true) do
      local l1, c1, l2, c2 = dv:indent_text(true, line1, col1, line2, col2)
      if l1 then
        dv:set_selections(idx, l1, c1, l2, c2)
      end
    end
  end,

  ["docview:duplicate-lines"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(dv, true) do
      append_line_if_last_line(dv, line2)
      local text = doc():get_text(line1, 1, line2 + 1, 1)
      dv.doc:insert(line2 + 1, 1, text)
      local n = line2 - line1 + 1
      dv:set_selections(idx, line1 + n, col1, line2 + n, col2)
    end
  end,

  ["docview:delete-lines"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(dv, true) do
      append_line_if_last_line(dv, line2)
      dv.doc:remove(line1, 1, line2 + 1, 1)
      dv:set_selections(idx, line1, col1)
    end
  end,

  ["docview:move-lines-up"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(dv, true) do
      append_line_if_last_line(dv, line2)
      if line1 > 1 then
        local text = dv.doc.lines[line1 - 1]
        dv.doc:insert(line2 + 1, 1, text)
        dv.doc:remove(line1 - 1, 1, line1, 1)
        dv:set_selections(idx, line1 - 1, col1, line2 - 1, col2)
      end
    end
  end,

  ["docview:move-lines-down"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(dv, true) do
      append_line_if_last_line(dv, line2 + 1)
      if line2 < #dv.doc.lines then
        local text = dv.doc.lines[line2 + 1]
        dv.doc:remove(line2 + 1, 1, line2 + 2, 1)
        dv.doc:insert(line1, 1, text)
        dv:set_selections(idx, line1 + 1, col1, line2 + 1, col2)
      end
    end
  end,

  ["docview:toggle-block-comments"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(dv, true) do
      local current_syntax = dv.doc.syntax
      if line1 > 1 then
        -- Use the previous line state, as it will be the state
        -- of the beginning of the current line
        local state = dv.doc.highlighter:get_line(line1 - 1).state
        local syntaxes = tokenizer.extract_subsyntaxes(dv.doc.syntax, state)
        -- Go through all the syntaxes until the first with `block_comment` defined
        for _, s in pairs(syntaxes) do
          if s.block_comment then
            current_syntax = s
            break
          end
        end
      end
      local comment = current_syntax.block_comment
      if not comment then
        if dv.doc.syntax.comment then
          dv:perform("doc:toggle-line-comments")
        end
        return
      end
      -- if nothing is selected, toggle the whole line
      if line1 == line2 and col1 == col2 then
        col1 = 1
        col2 = #dv.doc.lines[line2]
      end
      dv:set_selections(idx, dv.doc:block_comment(comment, line1, col1, line2, col2))
    end
  end,

  ["docview:toggle-line-comments"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(dv, true) do
      local current_syntax = dv.doc.syntax
      if line1 > 1 then
        -- Use the previous line state, as it will be the state
        -- of the beginning of the current line
        local state = dv.doc.highlighter:get_line(line1 - 1).state
        local syntaxes = tokenizer.extract_subsyntaxes(dv.doc.syntax, state)
        -- Go through all the syntaxes until the first with comments defined
        for _, s in pairs(syntaxes) do
          if s.comment or s.block_comment then
            current_syntax = s
            break
          end
        end
      end
      local comment = current_syntax.comment or current_syntax.block_comment
      if comment then
        dv:set_selections(idx, dv.doc:line_comment(comment, line1, col1, line2, col2))
      end
    end
  end,

  ["docview:upper-case"] = function(dv)
    dv:replace(string.uupper)
  end,

  ["docview:lower-case"] = function(dv)
    dv:replace(string.ulower)
  end
}

local read_commands = {
  ["docview:select-none"] = function(dv)
    local l1, c1 = dv:get_selection_idx(dv.last_selection)
    if not l1 then
      l1, c1 = dv.doc:get_selection_idx(1)
    end
    dv:set_selection(l1, c1)
  end,

  ["docview:copy"] = function(dv)
    cut_or_copy(dv, false)
  end,

  ["docview:select-all"] = function(dv)
    dv:set_selection(1, 1, math.huge, math.huge)
    -- avoid triggering DocView:scroll_to_make_visible
    dv.last_line1 = 1
    dv.last_col1 = 1
    dv.last_line2 = #dv.doc.lines
    dv.last_col2 = #dv.doc.lines[#dv.doc.lines]
  end,

  ["docview:select-lines"] = function(dv)
    for idx, line1, _, line2 in dv:get_selections(true) do
      append_line_if_last_line(dv, line2)
      dv:set_selections(idx, line2 + 1, 1, line1, 1)
    end
  end,

  ["docview:select-word"] = function(dv)
    for idx, line, col in dv:get_selections(true) do
      local line1, col1 = translate.start_of_word(dv, line, col)
      local line2, col2 = translate.end_of_word(dv, line, col)
      dv:set_selections(idx, line2, col2, line1, col1)
    end
  end,

  ["docview:go-to-line"] = function(dv)
    local items
    local function init_items()
      if items then return end
      items = {}
      local mt = { __tostring = function(x) return x.text end }
      for i, line in ipairs(dv.doc.lines) do
        local item = { text = line:sub(1, -2), line = i, info = "line: " .. i }
        table.insert(items, setmetatable(item, mt))
      end
    end

    dv.root_view.command_view:enter("Go To Line", {
      submit = function(text, item)
        local line = item and item.line or tonumber(text)
        if not line then
          core.error("Invalid line number or unmatched string")
          return
        end
        dv:set_selection(line, 1  )
        dv:scroll_to_line(line, true)
      end,
      suggest = function(text)
        if not text:find("^%d*$") then
          init_items()
          return common.fuzzy_match(items, text)
        end
      end
    })
  end,

  ["docview:toggle-overwrite"] = function(dv)
    dv.overwrite = not dv.overwrite
    core.blink_reset() -- to show the cursor has changed edit modes
  end,

  ["docview:select-to-cursor"] = function(dv, options)
    local x, y = options.x, options.y
    local line1, col1 = select(3, dv:get_selection())
    local line2, col2 = dv:resolve_screen_position(x, y)
    dv.mouse_selecting = { line1, col1, nil }
    dv:set_selection(line2, col2, line1, col1)
  end,

  ["docview:create-cursor-previous-line"] = function(dv)
    split_cursor(dv, -1)
    dv:merge_cursors()
  end,

  ["docview:create-cursor-next-line"] = function(dv)
    split_cursor(dv, 1)
    dv:merge_cursors()
  end

}

command.add(function(rv, options)
  local x, y = options.x, options.y
  if x == nil or y == nil or not rv.active_view:extends(DocView) then return false end
  local dv = rv.active_view
  local x1,y1,x2,y2 = dv.position.x, dv.position.y, dv.position.x + dv.size.x, dv.position.y + dv.size.y
  return x >= x1 + dv:get_gutter_width() and x < x2 and y >= y1 and y < y2, dv, x, y
end, {
  ["docview:set-cursor"] = function(dv, x, y)
    set_cursor(dv, x, y, "set")
  end,

  ["docview:set-cursor-word"] = function(dv, x, y)
    set_cursor(dv, x, y, "word")
  end,

  ["docview:set-cursor-line"] = function(dv, x, y, clicks)
    set_cursor(dv, x, y, "lines")
  end,

  ["docview:split-cursor"] = function(dv, x, y, clicks)
    local line, col = dv:resolve_screen_position(x, y)
    local removal_target = nil
    for idx, line1, col1 in dv:get_selections(true) do
      if line1 == line and col1 == col and #dv.selections > 4 then
        removal_target = idx
      end
    end
    if removal_target then
      dv:remove_selection(removal_target)
    else
      dv:add_selection(line, col, line, col)
    end
    dv.mouse_selecting = { line, col, "set" }
  end
})

local translations = {
  ["previous-char"] = DocView.translate,
  ["next-char"] = DocView.translate,
  ["previous-word-start"] = translate,
  ["next-word-end"] = translate,
  ["previous-block-start"] = translate,
  ["next-block-end"] = translate,
  ["start-of-doc"] = translate,
  ["end-of-doc"] = translate,
  ["start-of-line"] = DocView.translate,
  ["end-of-line"] = DocView.translate,
  ["start-of-word"] = translate,
  ["start-of-indentation"] = DocView.translate,
  ["end-of-word"] = translate,
  ["previous-line"] = DocView.translate,
  ["next-line"] = DocView.translate,
  ["previous-page"] = DocView.translate,
  ["next-page"] = DocView.translate,
}

for name, obj in pairs(translations) do
  read_commands["docview:move-to-" .. name] = function(dv) dv:move_to(obj[name:gsub("-", "_")], dv) end
  read_commands["docview:select-to-" .. name] = function(dv) dv:select_to(obj[name:gsub("-", "_")], dv) end
  write_commands["docview:delete-to-" .. name] = function(dv) dv:delete_to(obj[name:gsub("-", "_")], dv) end
end

read_commands["docview:move-to-previous-char"] = function(dv)
  for idx, line1, col1, line2, col2 in dv:get_selections(true) do
    if line1 ~= line2 or col1 ~= col2 then
      dv:set_selections(idx, line1, col1)
    else
      dv:move_to_cursor(idx, DocView.translate.previous_char)
    end
  end
  dv:merge_cursors()
end

read_commands["docview:move-to-next-char"] = function(dv)
  for idx, line1, col1, line2, col2 in dv:get_selections(true) do
    if line1 ~= line2 or col1 ~= col2 then
      dv:set_selections(idx, line2, col2)
    else
      dv:move_to_cursor(idx, DocView.translate.next_char)
    end
  end
  dv:merge_cursors()
end

command.add(function(rv) return rv.active_view:extends(DocView) and not rv.active_view.read_only, rv.active_view end, write_commands)
command.add("core.docview", read_commands)
