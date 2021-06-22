local core = require "core"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local translate = require "core.doc.translate"
local DocView = require "core.docview"


local function dv()
  return core.active_view
end


local function doc()
  return core.active_view.doc
end


local function get_indent_string()
  if config.tab_type == "hard" then
    return "\t"
  end
  return string.rep(" ", config.indent_size)
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
  doc():save(filename and core.normalize_to_project_dir(filename))
  local saved_filename = doc().filename
  core.log("Saved \"%s\"", saved_filename)
end

local function cut_or_copy(delete)
  local full_text = ""
  for idx, line1, col1, line2, col2 in doc():get_selections() do
    if line1 ~= line2 or col1 ~= col2 then
      local text = doc():get_text(line1, col1, line2, col2)
      if delete then
        doc():delete_to_cursor(idx, 0)
      end
      full_text = full_text == "" and text or (full_text .. "\n" .. text)
      doc().cursor_clipboard[idx] = text
    else
      doc().cursor_clipboard[idx] = ""
    end
  end
  system.set_clipboard(full_text)
end

local function split_cursor(direction)
  local new_cursors = {}
  for _, line1, col1 in doc():get_selections() do
    if line1 > 1 and line1 < #doc().lines then
      table.insert(new_cursors, { line1 + direction, col1 })
    end
  end
  for i,v in ipairs(new_cursors) do doc():add_selection(v[1], v[2]) end
  core.blink_reset()
end

local commands = {
  ["doc:undo"] = function()
    doc():undo()
  end,

  ["doc:redo"] = function()
    doc():redo()
  end,

  ["doc:cut"] = function()
    cut_or_copy(true)
  end,

  ["doc:copy"] = function()
    cut_or_copy(false)
  end,

  ["doc:paste"] = function()
    for idx, line1, col1, line2, col2 in doc():get_selections() do
      local value = doc().cursor_clipboard[idx] or system.get_clipboard()
      doc():text_input(value:gsub("\r", ""), idx)
    end
  end,

  ["doc:newline"] = function()
    for idx, line, col in doc():get_selections(false, true) do
      local indent = doc().lines[line]:match("^[\t ]*")
      if col <= #indent then
        indent = indent:sub(#indent + 2 - col)
      end
      doc():text_input("\n" .. indent, idx)
    end
  end,

  ["doc:newline-below"] = function()
    for idx, line in doc():get_selections(false, true) do
      local indent = doc().lines[line]:match("^[\t ]*")
      doc():insert(line, math.huge, "\n" .. indent)
      doc():set_selections(idx, line + 1, math.huge)
    end
  end,

  ["doc:newline-above"] = function()
    for idx, line in doc():get_selections(false, true) do
      local indent = doc().lines[line]:match("^[\t ]*")
      doc():insert(line, 1, indent .. "\n")
      doc():set_selections(idx, line, math.huge)
    end
  end,

  ["doc:delete"] = function()
    for idx, line1, col1, line2, col2 in doc():get_selections() do
      if line1 == line2 and col1 == col2 and doc().lines[line1]:find("^%s*$", col1) then
        doc():remove(line1, col1, line1, math.huge)
      end
      doc():delete_to_cursor(idx, translate.next_char)
    end
  end,

  ["doc:backspace"] = function()
    for idx, line1, col1, line2, col2 in doc():get_selections() do
      if line1 == line2 and col1 == col2 then
        local text = doc():get_text(line1, 1, line1, col1)
        if #text >= config.indent_size and text:find("^ *$") then
          doc():delete_to_cursor(idx, 0, -config.indent_size)
          return
        end
      end
      doc():delete_to_cursor(idx, translate.previous_char)
    end
  end,

  ["doc:select-all"] = function()
    doc():set_selection(1, 1, math.huge, math.huge)
  end,

  ["doc:select-none"] = function()
    local line, col = doc():get_selection()
    doc():set_selection(line, col)
  end,


  ["doc:indent"] = function()
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
      local l1, c1, l2, c2 = doc():indent_text(false, line1, col1, line2, col2)
      if l1 then
        doc():set_selections(idx, l1, c1, l2, c2)
      end
    end
  end,

  ["doc:select-lines"] = function()
    for idx, line1, _, line2 in doc():get_selections(true) do
      append_line_if_last_line(line2)
      doc():set_selections(idx, line1, 1, line2 + 1, 1)
    end
  end,

  ["doc:select-word"] = function()
    for idx, line1, col1 in doc():get_selections(true) do
      local line1, col1 = translate.start_of_word(doc(), line1, col1)
      local line2, col2 = translate.end_of_word(doc(), line1, col1)
      doc():set_selections(idx, line2, col2, line1, col1)
    end
  end,

  ["doc:join-lines"] = function()
    for idx, line1, col1, line2, col2 in doc():get_selections(true) do
      if line1 == line2 then line2 = line2 + 1 end
      local text = doc():get_text(line1, 1, line2, math.huge)
      text = text:gsub("(.-)\n[\t ]*", function(x)
        return x:find("^%s*$") and x or x .. " "
      end)
      doc():insert(line1, 1, text)
      doc():remove(line1, #text + 1, line2, math.huge)
      if line1 ~= line2 or col1 ~= col2 then
        doc():set_selections(idx, line1, math.huge)
      end
    end
  end,

  ["doc:indent"] = function()
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
      local l1, c1, l2, c2 = doc():indent_text(false, line1, col1, line2, col2)
      if l1 then
        doc():set_selections(idx, l1, c1, l2, c2)
      end
    end
  end,

  ["doc:unindent"] = function()
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
      local l1, c1, l2, c2 = doc():indent_text(true, line1, col1, line2, col2)
      if l1 then
        doc():set_selections(idx, l1, c1, l2, c2)
      end
    end
  end,

  ["doc:duplicate-lines"] = function()
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
      append_line_if_last_line(line2)
      local text = doc():get_text(line1, 1, line2 + 1, 1)
      doc():insert(line2 + 1, 1, text)
      local n = line2 - line1 + 1
      doc():set_selections(idx, line1 + n, col1, line2 + n, col2)
    end
  end,

  ["doc:delete-lines"] = function()
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
      append_line_if_last_line(line2)
      doc():remove(line1, 1, line2 + 1, 1)
      doc():set_selections(idx, line1, col1)
    end
  end,

  ["doc:move-lines-up"] = function()
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
      append_line_if_last_line(line2)
      if line1 > 1 then
        local text = doc().lines[line1 - 1]
        doc():insert(line2 + 1, 1, text)
        doc():remove(line1 - 1, 1, line1, 1)
        doc():set_selections(idx, line1 - 1, col1, line2 - 1, col2)
      end
    end
  end,

  ["doc:move-lines-down"] = function()
    for idx, line1, col1, line2, col2 in doc_multiline_selections(true) do
      append_line_if_last_line(line2 + 1)
      if line2 < #doc().lines then
        local text = doc().lines[line2 + 1]
        doc():remove(line2 + 1, 1, line2 + 2, 1)
        doc():insert(line1, 1, text)
        doc():set_selections(idx, line1 + 1, col1, line2 + 1, col2)
      end
    end
  end,

  ["doc:toggle-line-comments"] = function()
    local comment = doc().syntax.comment
    if not comment then return end
    local indentation = get_indent_string()
    local comment_text = comment .. " "
    for idx, line1, _, line2 in doc_multiline_selections(true) do
      local uncomment = true
      local start_offset = math.huge
      for line = line1, line2 do
        local text = doc().lines[line]
        local s = text:find("%S")
        local cs, ce = text:find(comment_text, s, true)
        if s and cs ~= s then
          uncomment = false
          start_offset = math.min(start_offset, s)
        end
      end
      for line = line1, line2 do
        local text = doc().lines[line]
        local s = text:find("%S")
        if uncomment then
          local cs, ce = text:find(comment_text, s, true)
          if ce then
            doc():remove(line, cs, line, ce + 1)
          end
        elseif s then
          doc():insert(line, start_offset, comment_text)
        end
      end
    end
  end,

  ["doc:upper-case"] = function()
    doc():replace(string.upper)
  end,

  ["doc:lower-case"] = function()
    doc():replace(string.lower)
  end,

  ["doc:go-to-line"] = function()
    local dv = dv()

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

    core.command_view:enter("Go To Line", function(text, item)
      local line = item and item.line or tonumber(text)
      if not line then
        core.error("Invalid line number or unmatched string")
        return
      end
      dv.doc:set_selection(line, 1  )
      dv:scroll_to_line(line, true)

    end, function(text)
      if not text:find("^%d*$") then
        init_items()
        return common.fuzzy_match(items, text)
      end
    end)
  end,

  ["doc:toggle-line-ending"] = function()
    doc().crlf = not doc().crlf
  end,

  ["doc:save-as"] = function()
    local last_doc = core.last_active_view and core.last_active_view.doc
    if doc().filename then
      core.command_view:set_text(doc().filename)
    elseif last_doc and last_doc.filename then
      local dirname, filename = core.last_active_view.doc.abs_filename:match("(.*)[/\\](.+)$")
      core.command_view:set_text(core.normalize_to_project_dir(dirname) .. PATHSEP)
    end
    core.command_view:enter("Save As", function(filename)
      save(common.home_expand(filename))
    end, function (text)
      return common.home_encode_list(common.path_suggest(common.home_expand(text)))
    end)
  end,

  ["doc:save"] = function()
    if doc().filename then
      save()
    else
      command.perform("doc:save-as")
    end
  end,

  ["file:rename"] = function()
    local old_filename = doc().filename
    if not old_filename then
      core.error("Cannot rename unsaved doc")
      return
    end
    core.command_view:set_text(old_filename)
    core.command_view:enter("Rename", function(filename)
      doc():save(filename)
      core.log("Renamed \"%s\" to \"%s\"", old_filename, filename)
      if filename ~= old_filename then
        os.remove(old_filename)
      end
    end, common.path_suggest)
  end,


  ["file:delete"] = function()
    local filename = doc().abs_filename
    if not filename then
      core.error("Cannot remove unsaved doc")
      return
    end
    for i,docview in ipairs(core.get_views_referencing_doc(doc())) do
      local node = core.root_view.root_node:get_node_for_view(docview)
      node:close_view(core.root_view, docview)
    end
    os.remove(filename)
    core.log("Removed \"%s\"", filename)
  end,

  ["doc:create-cursor-previous-line"] = function()
    split_cursor(-1)
    doc():merge_cursors()
  end,

  ["doc:create-cursor-next-line"] = function()
    split_cursor(1)
    doc():merge_cursors()
  end

}


local translations = {
  ["previous-char"] = translate.previous_char,
  ["next-char"] = translate.next_char,
  ["previous-word-start"] = translate.previous_word_start,
  ["next-word-end"] = translate.next_word_end,
  ["previous-block-start"] = translate.previous_block_start,
  ["next-block-end"] = translate.next_block_end,
  ["start-of-doc"] = translate.start_of_doc,
  ["end-of-doc"] = translate.end_of_doc,
  ["start-of-line"] = translate.start_of_line,
  ["end-of-line"] = translate.end_of_line,
  ["start-of-word"] = translate.start_of_word,
  ["end-of-word"] = translate.end_of_word,
  ["previous-line"] = DocView.translate.previous_line,
  ["next-line"] = DocView.translate.next_line,
  ["previous-page"] = DocView.translate.previous_page,
  ["next-page"] = DocView.translate.next_page,
}

for name, fn in pairs(translations) do
  commands["doc:move-to-" .. name] = function() doc():move_to(fn, dv()) end
  commands["doc:select-to-" .. name] = function() doc():select_to(fn, dv()) end
  commands["doc:delete-to-" .. name] = function() doc():delete_to(fn, dv()) end
end

commands["doc:move-to-previous-char"] = function()
  for idx, line1, col1, line2, col2 in doc():get_selections(true) do
    if line1 ~= line2 or col1 ~= col2 then
      doc():set_selections(idx, line1, col1)
    end
  end
  doc():move_to(translate.previous_char)
end

commands["doc:move-to-next-char"] = function()
  for idx, line1, col1, line2, col2 in doc():get_selections(true) do
    if line1 ~= line2 or col1 ~= col2 then
      doc():set_selections(idx, line2, col2)
    end
  end
  doc():move_to(translate.next_char)
end

command.add("core.docview", commands)
