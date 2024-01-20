local core = require "core"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local translate = require "core.doc.translate"
local style = require "core.style"
local DocView = require "core.docview"
local tokenizer = require "core.tokenizer"


local function doc()
  return core.active_view.doc
end


local function doc_multiline_selections(sort)
  local iter, state, idx, line1, col1, line2, col2 = doc():get_selections(sort)
  return function()
    idx, line1, col1, line2, col2 = iter(state, idx)
    if idx and line2 > line1 and col2 == 1 then
      line2 = line2 - 1
      col2 = #doc().lines[line2]
    end
    return idx, line1, col1, line2, col2
  end
end

local function append_line_if_last_line(line)
  if line >= #doc().lines then
    doc():insert(line, math.huge, "\n")
  end
end

local function save(filename)
  local abs_filename
  if filename then
    filename = core.normalize_to_project_dir(filename)
    abs_filename = core.project_absolute_path(filename)
  end
  local ok, err = pcall(doc().save, doc(), filename, abs_filename)
  if ok then
    local saved_filename = doc().filename
    core.log("Saved \"%s\"", saved_filename)
  else
    core.error(err)
    core.nag_view:show("Saving failed", string.format("Couldn't save file \"%s\". Do you want to save to another location?", doc().filename), {
      { text = "Yes", default_yes = true },
      { text = "No", default_no = true }
    }, function(item)
      if item.text == "Yes" then
        core.add_thread(function()
          -- we need to run this in a thread because of the odd way the nagview is.
          command.perform("doc:save-as")
        end)
      end
    end)
  end
end

local function cut_or_copy(delete)
  local full_text = ""
  local text = ""
  core.cursor_clipboard = {}
  core.cursor_clipboard_whole_line = {}
  for idx, line1, col1, line2, col2 in doc():get_selections(true, true) do
    if line1 ~= line2 or col1 ~= col2 then
      text = doc():get_text(line1, col1, line2, col2)
      full_text = full_text == "" and text or (text .. " " .. full_text)
      core.cursor_clipboard_whole_line[idx] = false
      if delete then
        doc():delete_to_cursor(idx, 0)
      end
    else -- Cut/copy whole line
      -- Remove newline from the text. It will be added as needed on paste.
      text = string.sub(doc().lines[line1], 1, -2)
      full_text = full_text == "" and text .. "\n" or (text .. "\n" .. full_text)
      core.cursor_clipboard_whole_line[idx] = true
      if delete then
        if line1 < #doc().lines then
          doc():remove(line1, 1, line1 + 1, 1)
        elseif #doc().lines == 1 then
          doc():remove(line1, 1, line1, math.huge)
        else
          doc():remove(line1 - 1, math.huge, line1, math.huge)
        end
        doc():set_selections(idx, line1, col1, line2, col2)
      end
    end
    core.cursor_clipboard[idx] = text
  end
  if delete then doc():merge_cursors() end
  core.cursor_clipboard["full"] = full_text
  system.set_clipboard(full_text)
end

local function split_cursor(dv, direction)
  local new_cursors = {}
  local dv_translate = direction < 0
    and DocView.translate.previous_line
    or DocView.translate.next_line
  for _, line1, col1 in dv.doc:get_selections() do
    if line1 + direction >= 1 and line1 + direction <= #dv.doc.lines then
      table.insert(new_cursors, { dv_translate(dv.doc, line1, col1, dv) })
    end
  end
  -- add selections in the order that will leave the "last" added one as doc.last_selection
  local start, stop = 1, #new_cursors
  if direction < 0 then
    start, stop = #new_cursors, 1
  end
  for i = start, stop, direction do
    local v = new_cursors[i]
    dv.doc:add_selection(v[1], v[2])
  end
  core.blink_reset()
end

local function set_cursor(dv, x, y, snap_type)
  local line, col = dv:resolve_screen_position(x, y)
  dv.doc:set_selection(line, col, line, col)
  if snap_type == "word" or snap_type == "lines" then
    command.perform("doc:select-" .. snap_type)
  end
  dv.mouse_selecting = { line, col, snap_type }
  core.blink_reset()
end

local function line_comment(comment, line1, col1, line2, col2)
  local start_comment = (type(comment) == 'table' and comment[1] or comment) .. " "
  local end_comment = (type(comment) == 'table' and " " .. comment[2])
  local uncomment = true
  local start_offset = math.huge
  for line = line1, line2 do
    local text = doc().lines[line]
    local s = text:find("%S")
    if s then
      local cs, ce = text:find(start_comment, s, true)
      if cs ~= s then
        uncomment = false
      end
      start_offset = math.min(start_offset, s)
    end
  end

  local end_line = col2 == #doc().lines[line2]
  for line = line1, line2 do
    local text = doc().lines[line]
    local s = text:find("%S")
    if s and uncomment then
      if end_comment and text:sub(#text - #end_comment, #text - 1) == end_comment then
        doc():remove(line, #text - #end_comment, line, #text)
      end
      local cs, ce = text:find(start_comment, s, true)
      if ce then
        doc():remove(line, cs, line, ce + 1)
      end
    elseif s then
      doc():insert(line, start_offset, start_comment)
      if end_comment then
        doc():insert(line, #doc().lines[line], " " .. comment[2])
      end
    end
  end
  col1 = col1 + (col1 > start_offset and #start_comment or 0) * (uncomment and -1 or 1)
  col2 = col2 + (col2 > start_offset and #start_comment or 0) * (uncomment and -1 or 1)
  if end_comment and end_line then
    col2 = col2 + #end_comment * (uncomment and -1 or 1)
  end
  return line1, col1, line2, col2
end

local function block_comment(comment, line1, col1, line2, col2)
  -- automatically skip spaces
  local word_start = doc():get_text(line1, col1, line1, math.huge):find("%S")
  local word_end = doc():get_text(line2, 1, line2, col2):find("%s*$")
  col1 = col1 + (word_start and (word_start - 1) or 0)
  col2 = word_end and word_end or col2

  local block_start = doc():get_text(line1, col1, line1, col1 + #comment[1])
  local block_end = doc():get_text(line2, col2 - #comment[2], line2, col2)

  if block_start == comment[1] and block_end == comment[2] then
    -- remove up to 1 whitespace after the comment
    local start_len, stop_len = #comment[1], #comment[2]
    if doc():get_text(line1, col1 + #comment[1], line1, col1 + #comment[1] + 1):find("%s$") then
      start_len = start_len + 1
    end
    if doc():get_text(line2, col2 - #comment[2] - 1, line2, col2):find("^%s") then
      stop_len = stop_len + 1
    end

    doc():remove(line1, col1, line1, col1 + start_len)
    col2 = col2 - (line1 == line2 and start_len or 0)
    doc():remove(line2, col2 - stop_len, line2, col2)

    return line1, col1, line2, col2 - stop_len
  else
    doc():insert(line1, col1, comment[1] .. " ")
    col2 = col2 + (line1 == line2 and (#comment[1] + 1) or 0)
    doc():insert(line2, col2, " " .. comment[2])

    return line1, col1, line2, col2 + #comment[2] + 1
  end
end

local function insert_paste(doc, value, whole_line, idx)
  if whole_line then
    local line1, col1 = doc:get_selection_idx(idx)
    doc:insert(line1, 1, value:gsub("\r", "").."\n")
    -- Because we're inserting at the start of the line,
    -- if the cursor is in the middle of the line
    -- it gets carried to the next line along with the old text.
    -- If it's at the start of the line it doesn't get carried,
    -- so we move it of as many characters as we're adding.
    if col1 == 1 then
      doc:move_to_cursor(idx, #value+1)
    end
  else
    doc:text_input(value:gsub("\r", ""), idx)
  end
end

local commands = {
  ["doc:select-none"] = function(dv)
    local l1, c1 = dv.doc:get_selection_idx(dv.doc.last_selection)
    if not l1 then
      l1, c1 = dv.doc:get_selection_idx(1)
    end
    dv.doc:set_selection(l1, c1)
  end,

  ["doc:cut"] = function()
    cut_or_copy(true)
  end,

  ["doc:copy"] = function()
    cut_or_copy(false)
  end,

  ["doc:undo"] = function(dv)
    dv.doc:undo()
  end,

  ["doc:redo"] = function(dv)
    dv.doc:redo()
  end,

  ["doc:paste"] = function(dv)
    local clipboard = system.get_clipboard()
    -- If the clipboard has changed since our last look, use that instead
    if core.cursor_clipboard["full"] ~= clipboard then
      core.cursor_clipboard = {}
      core.cursor_clipboard_whole_line = {}
      for idx in dv.doc:get_selections() do
        insert_paste(dv.doc, clipboard, false, idx)
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
    if #core.cursor_clipboard_whole_line == (#dv.doc.selections/4) then
    -- If we have the same number of clipboards and selections,
    -- paste each clipboard into its corresponding selection
      for idx in dv.doc:get_selections() do
        insert_paste(dv.doc, core.cursor_clipboard[idx], only_whole_lines, idx)
      end
    else
      -- Paste every clipboard and add a selection at the end of each one
      local new_selections = {}
      for idx in dv.doc:get_selections() do
        for cb_idx in ipairs(core.cursor_clipboard_whole_line) do
          insert_paste(dv.doc, core.cursor_clipboard[cb_idx], only_whole_lines, idx)
          if not only_whole_lines then
            table.insert(new_selections, {dv.doc:get_selection_idx(idx)})
          end
        end
        if only_whole_lines then
          table.insert(new_selections, {dv.doc:get_selection_idx(idx)})
        end
      end
      local first = true
      for _,selection in pairs(new_selections) do
        if first then
          dv.doc:set_selection(table.unpack(selection))
          first = false
        else
          dv.doc:add_selection(table.unpack(selection))
        end
      end
    end
  end,

  ["doc:newline"] = function(dv)
    for idx, line, col in dv.doc:get_selections(false, true) do
      local indent = dv.doc.lines[line]:match("^[\t ]*")
      if col <= #indent then
        indent = indent:sub(#indent + 2 - col)
      end
      -- Remove current line if it contains only whitespace
      if not config.keep_newline_whitespace and dv.doc.lines[line]:match("^%s+$") then
        dv.doc:remove(line, 1, line, math.huge)
      end
      dv.doc:text_input("\n" .. indent, idx)
    end
  end,

  ["doc:newline-below"] = function(dv)
    for idx, line in dv.doc:get_selections(false, true) do
      local indent = dv.doc.lines[line]:match("^[\t ]*")
      dv.doc:insert(line, math.huge, "\n" .. indent)
      dv.doc:set_selections(idx, line + 1, math.huge)
    end
  end,

  ["doc:newline-above"] = function(dv)
    for idx, line in dv.doc:get_selections(false, true) do
      local indent = dv.doc.lines[line]:match("^[\t ]*")
      dv.doc:insert(line, 1, indent .. "\n")
      dv.doc:set_selections(idx, line, math.huge)
    end
  end,

  ["doc:delete"] = function(dv)
    for idx, line1, col1, line2, col2 in dv.doc:get_selections(true, true) do
      if line1 == line2 and col1 == col2 and dv.doc.lines[line1]:find("^%s*$", col1) then
        dv.doc:remove(line1, col1, line1, math.huge)
      end
      dv.doc:delete_to_cursor(idx, translate.next_char)
    end
  end,

  ["doc:backspace"] = function(dv)
    local _, indent_size = dv.doc:get_indent_info()
    for idx, line1, col1, line2, col2 in dv.doc:get_selections(true, true) do
      if line1 == line2 and col1 == col2 then
        local text = dv.doc:get_text(line1, 1, line1, col1)
        if #text >= indent_size and text:find("^ *$") then
          dv.doc:delete_to_cursor(idx, 0, -indent_size)
          goto continue
        end
      end
      dv.doc:delete_to_cursor(idx, translate.previous_char)
      ::continue::
    end
  end,

  ["doc:select-all"] = function(dv)
    dv.doc:set_selection(1, 1, math.huge, math.huge)
    -- avoid triggering DocView:scroll_to_make_visible
    dv.last_line1 = 1
    dv.last_col1 = 1
    dv.last_line2 = #dv.doc.lines
    dv.last_col2 = #dv.doc.lines[#dv.doc.lines]
  end,

  ["doc:select-lines"] = function(dv)
    for idx, line1, _, line2 in dv.doc:get_selections(true) do
      append_line_if_last_line(line2)
      dv.doc:set_selections(idx, line1, 1, line2 + 1, 1)
    end
  end,

  ["doc:select-word"] = function(dv)
    for idx, line1, col1 in dv.doc:get_selections(true) do
      local line1, col1 = translate.start_of_word(dv.doc, line1, col1)
      local line2, col2 = translate.end_of_word(dv.doc, line1, col1)
      dv.doc:set_selections(idx, line2, col2, line1, col1)
    end
  end,

  ["doc:join-lines"] = function(dv)
    for idx, line1, col1, line2, col2 in dv.doc:get_selections(true) do
      if line1 == line2 then line2 = line2 + 1 end
      local text = dv.doc:get_text(line1, 1, line2, math.huge)
      text = text:gsub("(.-)\n[\t ]*", function(x)
        return x:find("^%s*$") and x or x .. " "
      end)
      dv.doc:insert(line1, 1, text)
      dv.doc:remove(line1, #text + 1, line2, math.huge)
      if line1 ~= line2 or col1 ~= col2 then
        dv.doc:set_selections(idx, line1, math.huge)
      end
    end
  end,

  ["doc:indent"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
      local l1, c1, l2, c2 = dv.doc:indent_text(false, line1, col1, line2, col2)
      if l1 then
        dv.doc:set_selections(idx, l1, c1, l2, c2)
      end
    end
  end,

  ["doc:unindent"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
      local l1, c1, l2, c2 = dv.doc:indent_text(true, line1, col1, line2, col2)
      if l1 then
        dv.doc:set_selections(idx, l1, c1, l2, c2)
      end
    end
  end,

  ["doc:duplicate-lines"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
      append_line_if_last_line(line2)
      local text = doc():get_text(line1, 1, line2 + 1, 1)
      dv.doc:insert(line2 + 1, 1, text)
      local n = line2 - line1 + 1
      dv.doc:set_selections(idx, line1 + n, col1, line2 + n, col2)
    end
  end,

  ["doc:delete-lines"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
      append_line_if_last_line(line2)
      dv.doc:remove(line1, 1, line2 + 1, 1)
      dv.doc:set_selections(idx, line1, col1)
    end
  end,

  ["doc:move-lines-up"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
      append_line_if_last_line(line2)
      if line1 > 1 then
        local text = doc().lines[line1 - 1]
        dv.doc:insert(line2 + 1, 1, text)
        dv.doc:remove(line1 - 1, 1, line1, 1)
        dv.doc:set_selections(idx, line1 - 1, col1, line2 - 1, col2)
      end
    end
  end,

  ["doc:move-lines-down"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
      append_line_if_last_line(line2 + 1)
      if line2 < #dv.doc.lines then
        local text = dv.doc.lines[line2 + 1]
        dv.doc:remove(line2 + 1, 1, line2 + 2, 1)
        dv.doc:insert(line1, 1, text)
        dv.doc:set_selections(idx, line1 + 1, col1, line2 + 1, col2)
      end
    end
  end,

  ["doc:toggle-block-comments"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
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
          command.perform "doc:toggle-line-comments"
        end
        return
      end
      -- if nothing is selected, toggle the whole line
      if line1 == line2 and col1 == col2 then
        col1 = 1
        col2 = #dv.doc.lines[line2]
      end
      dv.doc:set_selections(idx, block_comment(comment, line1, col1, line2, col2))
    end
  end,

  ["doc:toggle-line-comments"] = function(dv)
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
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
        dv.doc:set_selections(idx, line_comment(comment, line1, col1, line2, col2))
      end
    end
  end,

  ["doc:upper-case"] = function(dv)
    dv.doc:replace(string.uupper)
  end,

  ["doc:lower-case"] = function(dv)
    dv.doc:replace(string.ulower)
  end,

  ["doc:go-to-line"] = function(dv)
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

    core.command_view:enter("Go To Line", {
      submit = function(text, item)
        local line = item and item.line or tonumber(text)
        if not line then
          core.error("Invalid line number or unmatched string")
          return
        end
        dv.doc:set_selection(line, 1  )
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

  ["doc:toggle-line-ending"] = function(dv)
    dv.doc.crlf = not dv.doc.crlf
  end,

  ["doc:save-as"] = function(dv)
    local last_doc = core.last_active_view and core.last_active_view.doc
    local text
    if dv.doc.filename then
      text = dv.doc.filename
    elseif last_doc and last_doc.filename then
      local dirname, filename = core.last_active_view.doc.abs_filename:match("(.*)[/\\](.+)$")
      text = core.normalize_to_project_dir(dirname) .. PATHSEP
    end
    core.command_view:enter("Save As", {
      text = text,
      submit = function(filename)
        save(common.home_expand(filename))
      end,
      suggest = function (text)
        return common.home_encode_list(common.path_suggest(common.home_expand(text)))
      end
    })
  end,

  ["doc:save"] = function(dv)
    if dv.doc.filename then
      save()
    else
      command.perform("doc:save-as")
    end
  end,

  ["doc:reload"] = function(dv)
    dv.doc:reload()
  end,

  ["file:rename"] = function(dv)
    local old_filename = dv.doc.filename
    if not old_filename then
      core.error("Cannot rename unsaved doc")
      return
    end
    core.command_view:enter("Rename", {
      text = old_filename,
      submit = function(filename)
        save(common.home_expand(filename))
        core.log("Renamed \"%s\" to \"%s\"", old_filename, filename)
        if filename ~= old_filename then
          os.remove(old_filename)
        end
      end,
      suggest = function (text)
        return common.home_encode_list(common.path_suggest(common.home_expand(text)))
      end
    })
  end,


  ["file:delete"] = function(dv)
    local filename = dv.doc.abs_filename
    if not filename then
      core.error("Cannot remove unsaved doc")
      return
    end
    for i,docview in ipairs(core.get_views_referencing_doc(dv.doc)) do
      local node = core.root_view.root_node:get_node_for_view(docview)
      node:close_view(core.root_view.root_node, docview)
    end
    os.remove(filename)
    core.log("Removed \"%s\"", filename)
  end,

  ["doc:select-to-cursor"] = function(dv, x, y, clicks)
    local line1, col1 = select(3, doc():get_selection())
    local line2, col2 = dv:resolve_screen_position(x, y)
    dv.mouse_selecting = { line1, col1, nil }
    dv.doc:set_selection(line2, col2, line1, col1)
  end,

  ["doc:create-cursor-previous-line"] = function(dv)
    split_cursor(dv, -1)
    dv.doc:merge_cursors()
  end,

  ["doc:create-cursor-next-line"] = function(dv)
    split_cursor(dv, 1)
    dv.doc:merge_cursors()
  end

}

command.add(function(x, y)
  if x == nil or y == nil or not core.active_view:extends(DocView) then return false end
  local dv = core.active_view
  local x1,y1,x2,y2 = dv.position.x, dv.position.y, dv.position.x + dv.size.x, dv.position.y + dv.size.y
  return x >= x1 + dv:get_gutter_width() and x < x2 and y >= y1 and y < y2, dv, x, y
end, {
  ["doc:set-cursor"] = function(dv, x, y)
    set_cursor(dv, x, y, "set")
  end,

  ["doc:set-cursor-word"] = function(dv, x, y)
    set_cursor(dv, x, y, "word")
  end,

  ["doc:set-cursor-line"] = function(dv, x, y, clicks)
    set_cursor(dv, x, y, "lines")
  end,

  ["doc:split-cursor"] = function(dv, x, y, clicks)
    local line, col = dv:resolve_screen_position(x, y)
    local removal_target = nil
    for idx, line1, col1 in dv.doc:get_selections(true) do
      if line1 == line and col1 == col and #doc().selections > 4 then
        removal_target = idx
      end
    end
    if removal_target then
      dv.doc:remove_selection(removal_target)
    else
      dv.doc:add_selection(line, col, line, col)
    end
    dv.mouse_selecting = { line, col, "set" }
  end
})

local translations = {
  ["previous-char"] = translate,
  ["next-char"] = translate,
  ["previous-word-start"] = translate,
  ["next-word-end"] = translate,
  ["previous-block-start"] = translate,
  ["next-block-end"] = translate,
  ["start-of-doc"] = translate,
  ["end-of-doc"] = translate,
  ["start-of-line"] = translate,
  ["end-of-line"] = translate,
  ["start-of-word"] = translate,
  ["start-of-indentation"] = translate,
  ["end-of-word"] = translate,
  ["previous-line"] = DocView.translate,
  ["next-line"] = DocView.translate,
  ["previous-page"] = DocView.translate,
  ["next-page"] = DocView.translate,
}

for name, obj in pairs(translations) do
  commands["doc:move-to-" .. name] = function(dv) dv.doc:move_to(obj[name:gsub("-", "_")], dv) end
  commands["doc:select-to-" .. name] = function(dv) dv.doc:select_to(obj[name:gsub("-", "_")], dv) end
  commands["doc:delete-to-" .. name] = function(dv) dv.doc:delete_to(obj[name:gsub("-", "_")], dv) end
end

commands["doc:move-to-previous-char"] = function(dv)
  for idx, line1, col1, line2, col2 in dv.doc:get_selections(true) do
    if line1 ~= line2 or col1 ~= col2 then
      dv.doc:set_selections(idx, line1, col1)
    else
      dv.doc:move_to_cursor(idx, translate.previous_char)
    end
  end
  dv.doc:merge_cursors()
end

commands["doc:move-to-next-char"] = function(dv)
  for idx, line1, col1, line2, col2 in dv.doc:get_selections(true) do
    if line1 ~= line2 or col1 ~= col2 then
      dv.doc:set_selections(idx, line2, col2)
    else
      dv.doc:move_to_cursor(idx, translate.next_char)
    end
  end
  dv.doc:merge_cursors()
end

command.add("core.docview", commands)
