-- mod-version:2 -- lite-xl 2.0
local core = require "core"
local command = require "core.command"
local DocView = require "core.docview"


local function check_doc()
  local av = core.active_view
  return av:is(DocView) and #av.doc.selections > 4
end


-- returns:
-- * if the doc has selections
-- * if the selections span multiple lines
local function doc_get_selection_status(doc)
  local selections = false
  for _,line1,col1,line2,col2 in doc:get_selections() do
    if line1 ~= line2 then
      return true, true
    end
    if col1 ~= col2 then
      selections = true
    end
  end
  return selections, false
end


local function has_selections()
  if not check_doc() then return false end
  local selections, has_multilines = doc_get_selection_status(core.active_view.doc)
  -- we want this to be true if there are only single lines selections
  return selections and not has_multilines
end


local function has_no_selections()
  if not check_doc() then return false end
  return not doc_get_selection_status(core.active_view.doc)
end


local function align(right)
  local doc = core.active_view.doc
  local max_col = 0
  local done = { }

  -- get alignment column
  for _,line1,col1,_,col2 in doc:get_selections(true) do
    -- only use the first caret in a line
    if not done[line1] then
      done[line1] = true
      max_col = math.max(max_col, right and col2 or col1)
    end
  end

  done = { }
  for idx,line1,col1,line2,col2 in doc:get_selections(true) do
  -- only align the first caret in a line
    if not done[line1] then
      done[line1] = true
      local diff = max_col - (right and col2 or col1)
      if diff > 0 then
        doc:insert(line1, col1, string.rep(" ", diff))
      end
      doc:set_selections(idx, line1, col1 + diff, line2, col2 + diff, right)
    end
  end
end


command.add(has_no_selections, {
  ["doc:align-carets"] = align,
})

command.add(has_selections, {
  ["doc:left-align-selections"] = align,
  ["doc:right-align-selections"] = function() align(true) end,
})
