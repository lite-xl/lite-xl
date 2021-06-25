local core = require "core"
local command = require "core.command"
local common = require "core.common"
local DocView = require "core.docview"

local project = {}

local function has_no_locked_children(node)
  if node.locked then return false end
  if node.type == "leaf" then return true end
  return has_no_locked_children(node.a) and has_no_locked_children(node.b)
end


local function get_unlocked_root(node)
  if node.type == "leaf" then
    return not node.locked and node
  end
  if has_no_locked_children(node) then
    return node
  end
  return get_unlocked_root(node.a) or get_unlocked_root(node.b)
end


local function save_view(view)
  local mt = getmetatable(view)
  if mt == DocView then
    return {
      type = "doc",
      active = (core.active_view == view),
      filename = view.doc.filename,
      selection = { view.doc:get_selection() },
      scroll = { x = view.scroll.to.x, y = view.scroll.to.y },
      text = not view.doc.filename and view.doc:get_text(1, 1, math.huge, math.huge)
    }
  end
  for name, mod in pairs(package.loaded) do
    if mod == mt then
      return {
        type = "view",
        active = (core.active_view == view),
        module = name
      }
    end
  end
end


local function load_view(t)
  if t.type == "doc" then
    local ok, doc = pcall(core.open_doc, t.filename)
    if not ok then
      return DocView(core.open_doc())
    end
    local dv = DocView(doc)
    if t.text then doc:insert(1, 1, t.text) end
    doc:set_selection(table.unpack(t.selection))
    dv.last_line, dv.last_col = doc:get_selection()
    dv.scroll.x, dv.scroll.to.x = t.scroll.x, t.scroll.x
    dv.scroll.y, dv.scroll.to.y = t.scroll.y, t.scroll.y
    return dv
  end
  return require(t.module)()
end


local function save_node(node)
  local res = {}
  res.type = node.type
  if node.type == "leaf" then
    res.views = {}
    for _, view in ipairs(node.views) do
      local t = save_view(view)
      if t then
        table.insert(res.views, t)
        if node.active_view == view then
          res.active_view = #res.views
        end
      end
    end
  else
    res.divider = node.divider
    res.a = save_node(node.a)
    res.b = save_node(node.b)
  end
  return res
end


local function load_node(node, t)
  if t.type == "leaf" then
    local res
    for _, v in ipairs(t.views) do
      local view = load_view(v)
      if v.active then res = view end
      node:add_view(view)
    end
    if t.active_view then
      node:set_active_view(node.views[t.active_view])
    end
    return res
  else
    node:split(t.type == "hsplit" and "right" or "down")
    node.divider = t.divider
    local res1 = load_node(node.a, t.a)
    local res2 = load_node(node.b, t.b)
    return res1 or res2
  end
end


function project.save_workspace(filename)
  local root = get_unlocked_root(core.root_view.root_node)
  local fp = io.open(filename, "w")
  if fp then
    local node_text = common.serialize(save_node(root))
    local topdir_entries = {}
    for _, entry in ipairs(core.project_entries) do
      if entry.item.topdir then
        table.insert(topdir_entries, {path = entry.name, type = entry.item.type})
      end
    end
    local project_entries_text = common.serialize(topdir_entries)
    fp:write(string.format(
      "return { project_name = %s, working_dir = %q, documents = %s, project_entries = %s }\n",
      core.project_name and string.format("%q", core.project_name) or "nil", core.working_dir, node_text, project_entries_text))
    fp:close()
  end
end


function project.load(name)
  core.project_name = name
  local filename = common.path_join(USERDIR, "projects", name .. ".lua")
  project.load_workspace(filename)
  core.log("Loaded project %s.", core.project_name)
  core.reschedule_project_scan()
end


function project.save(name)
  name = name or core.project_name
  local filename = common.path_join(USERDIR, "projects", name .. ".lua")
  save_workspace(filename)
  core.log("Saved project %s.", core.project_name)
end

local function workspace_files_for(basename)
  local workspace_dir = USERDIR .. PATHSEP .. "ws"
  local info_wsdir = system.get_file_info(workspace_dir)
  if not info_wsdir then
    local ok, err = system.mkdir(workspace_dir)
    if not ok then
      error("cannot create workspace directory: \"" .. err .. "\"")
    end
  end
  return coroutine.wrap(function()
    local files = system.list_dir(workspace_dir) or {}
    local n = #basename
    for _, file in ipairs(files) do
      if file:sub(1, n) == basename then
        local id = tonumber(file:sub(n + 1):match("^-(%d+)$"))
        if id then
          coroutine.yield(workspace_dir .. PATHSEP .. file, id)
        end
      end
    end
  end)
end

local function get_workspace_filename(basename)
  local id_list = {}
  for filename, id in workspace_files_for(basename) do
    id_list[id] = true
  end
  local id = 1
  while id_list[id] do
    id = id + 1
  end
  return common.path_join(USERDIR, "ws", basename .. "-" .. tostring(id))
end

function project.save_unnamed()
  local name = core.project_workspace_name()
  -- empty projects shoud return nil and we don't wave them
  if name then
    local filename = get_workspace_filename(name)
    save_workspace(filename)
  end
end


function project.load_workspace(filename)
  local load = loadfile(filename)
  local workspace = load and load()
  -- FIXME: decide, error or return a success code
  if not workspace then error("Cannot load workspace") end
  if workspace then
    local root = get_unlocked_root(core.root_view.root_node)
    local active_view = load_node(root, workspace.documents)
    if active_view then
      core.set_active_view(active_view)
    end
    core.project_name = workspace.project_name
    core.project_entries = {}
    for _, entry in ipairs(workspace.project_entries) do
      if entry.type == "dir" then
        core.add_project_directory(entry.path)
      elseif entry.type == "dir" then
        core.add_project_file(entry.path)
      end
    end
    system.chdir(workspace.working_dir)
  end
end

function project.list()
  local all = system.list_dir(USERDIR .. PATHSEP .. "projects")
  
end


local function suggest_directory(text)
  text = common.home_expand(text)
  return common.home_encode_list(text == "" and core.recents_open.dir or common.dir_path_suggest(text))
end

command.add(nil, {
  ["project:save-as"] = function()
    local entry = core.project_entries[1]
    if entry then
        core.command_view:set_text(entry.item.filename)
    end
    core.command_view:enter("Save Project As", function(text)
      -- FIXME: add sanity check of project name.
      core.project_name = text
      project.save()
    end)
  end,

  ["project:save"] = function()
    if core.project_name == "" then
      core.command_view:enter("Save Project As", function(text)
        core.project_name = text
      end)
    end
    project.save()
  end,

  ["project:load"] = function()
    core.command_view:enter("Load Project", function(text)
      project.load(text)
      core.set_recent_project(core.project_name)
    end)
  end,

  ["project:open-directory"] = function()
    core.command_view:enter("Open Directory", function(text, item)
      text = system.absolute_path(common.home_expand(item and item.text or text))
      local path_stat = system.get_file_info(text)
      if not path_stat or path_stat.type ~= 'dir' then
        core.error("Cannot open folder %q", text)
        return
      end
      core.confirm_close_all(core.new_project_from_directory, text)
    end, suggest_directory)
  end,
})

return project
