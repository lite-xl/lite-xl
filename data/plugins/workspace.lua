-- mod-version:3
local core = require "core"
local common = require "core.common"
local DocView = require "core.docview"
local LogView = require "core.logview"


local function workspace_files_for(project_dir)
  local basename = common.basename(project_dir)
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


local function consume_workspace_file(project_dir)
  for filename, id in workspace_files_for(project_dir) do
    local load_f = loadfile(filename)
    local workspace = load_f and load_f()
    if workspace and workspace.path == project_dir then
      os.remove(filename)
      return workspace
    end
  end
end


local function get_workspace_filename(project_dir)
  local id_list = {}
  for filename, id in workspace_files_for(project_dir) do
    id_list[id] = true
  end
  local id = 1
  while id_list[id] do
    id = id + 1
  end
  local basename = common.basename(project_dir)
  return USERDIR .. PATHSEP .. "ws" .. PATHSEP .. basename .. "-" .. tostring(id)
end


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
      crlf = view.doc.crlf,
      text = view.doc.new_file and view.doc:get_text(1, 1, math.huge, math.huge)
    }
  end
  if mt == LogView then return end
  for name, mod in pairs(package.loaded) do
    if mod == mt then
      return {
        type = "view",
        active = (core.active_view == view),
        module = name,
        scroll = { x = view.scroll.to.x, y = view.scroll.to.y, to = { x = view.scroll.to.x, y = view.scroll.to.y } },
      }
    end
  end
end


local function load_view(t)
  if t.type == "doc" then
    local dv
    if not t.filename then
      -- document not associated to a file
      dv = DocView(core.open_doc())
    else
      -- we have a filename, try to read the file
      local ok, doc = pcall(core.open_doc, t.filename)
      if ok then
        dv = DocView(doc)
      end
    end
    if dv and dv.doc then
      if dv.doc.new_file and t.text then
        dv.doc:insert(1, 1, t.text)
        dv.doc.crlf = t.crlf
      end
      dv.doc:set_selection(table.unpack(t.selection))
      dv.last_line1, dv.last_col1, dv.last_line2, dv.last_col2 = dv.doc:get_selection()
      dv.scroll.x, dv.scroll.to.x = t.scroll.x, t.scroll.x
      dv.scroll.y, dv.scroll.to.y = t.scroll.y, t.scroll.y
    end
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
    local active_view
    for i, v in ipairs(t.views) do
      local view = load_view(v)
      if view then
        if v.active then res = view end
        node:add_view(view)
        if t.active_view == i then
          active_view = view
        end
        if not view:is(DocView) then
          view.scroll = v.scroll	
        end
      end
    end
    if active_view then
      node:set_active_view(active_view)
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


local function save_directories()
  local project_dir = core.project_dir
  local dir_list = {}
  for i = 2, #core.project_directories do
    dir_list[#dir_list + 1] = common.relative_path(project_dir, core.project_directories[i].name)
  end
  return dir_list
end


local function save_workspace()
  local root = get_unlocked_root(core.root_view.root_node)
  local workspace_filename = get_workspace_filename(core.project_dir)
  local fp = io.open(workspace_filename, "w")
  if fp then
    local node_text = common.serialize(save_node(root))
    local dir_text = common.serialize(save_directories())
    fp:write(string.format("return { path = %q, documents = %s, directories = %s }\n", core.project_dir, node_text, dir_text))
    fp:close()
  end
end


local function load_workspace()
  local workspace = consume_workspace_file(core.project_dir)
  if workspace then
    local root = get_unlocked_root(core.root_view.root_node)
    local active_view = load_node(root, workspace.documents)
    if active_view then
      core.set_active_view(active_view)
    end
    for i, dir_name in ipairs(workspace.directories) do
      core.add_project_directory(system.absolute_path(dir_name))
    end
  end
end


local run = core.run

function core.run(...)
  if #core.docs == 0 then
    core.try(load_workspace)

    local on_quit_project = core.on_quit_project
    function core.on_quit_project()
      core.try(save_workspace)
      on_quit_project()
    end

    local on_enter_project = core.on_enter_project
    function core.on_enter_project(new_dir)
      on_enter_project(new_dir)
      core.try(load_workspace)
    end
  end

  core.run = run
  return core.run(...)
end
