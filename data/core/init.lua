require "core.strict"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local command
local keymap
local RootView
local StatusView
local CommandView
local Doc

local core = {}

local function table_serialize(t)
  local ls = {"{"}
  for i = 1, #t do
    ls[#ls + 1] = string.format("  %q,", t[i])
  end
  ls[#ls + 1] = "}"
  return table.concat(ls, "\n")
end

local function load_projects()
  local ok, t = pcall(dofile, USERDIR .. "/recent_projects.lua")
  core.recent_projects = (ok and t or {})
end

local function add_project_to_recents(dirname)
  dirname = system.absolute_path(dirname)
  if not dirname then return end
  local recents = core.recent_projects
  local n = #recents
  for i = 1, n do
    if dirname == recents[i] then
      table.remove(recents, i)
      break
    end
  end
  table.insert(recents, 1, dirname)
end

local function save_projects()
  local fp = io.open(USERDIR .. "/recent_projects.lua", "w")
  if fp then
    fp:write("return ", table_serialize(core.recent_projects), "\n")
    fp:close()
  end
end

function core.open_folder_project(dirname)
  core.root_view:close_all_docviews()
  add_project_to_recents(dirname)
  save_projects()
  core.switch_project = dirname
  core.threads[core.project_scan_thread_id].wake = 0
end

local function project_scan_thread()
  local priority_run = true

  local function diff_files(a, b)
    if #a ~= #b then return true end
    for i, v in ipairs(a) do
      if b[i].filename ~= v.filename
      or b[i].modified ~= v.modified then
        return true
      end
    end
  end

  local function compare_file(a, b)
    return a.filename < b.filename
  end

  local function get_files(path, t)
    if not priority_run then coroutine.yield() end
    t = t or {}
    local size_limit = config.file_size_limit * 10e5
    local all = system.list_dir(path) or {}
    local dirs, files = {}, {}

    local entries_count = 0
    local max_entries = config.max_project_files
    for _, file in ipairs(all) do
      if not common.match_pattern(file, config.ignore_files) then
        local file = (path ~= "." and path .. PATHSEP or "") .. file
        local info = system.get_file_info(file)
        if info and info.size < size_limit then
          info.filename = file
          table.insert(info.type == "dir" and dirs or files, info)
          entries_count = entries_count + 1
          if entries_count > max_entries then break end
        end
      end
    end

    table.sort(dirs, compare_file)
    for _, f in ipairs(dirs) do
      table.insert(t, f)
      if entries_count <= max_entries then
        local subdir_t, subdir_count = get_files(f.filename, t)
        entries_count = entries_count + subdir_count
      end
    end

    table.sort(files, compare_file)
    for _, f in ipairs(files) do
      table.insert(t, f)
    end

    return t, entries_count
  end

  while true do
    -- get project files and replace previous table if the new table is
    -- different
    local t, entries_count = get_files(".")
    if diff_files(core.project_files, t) then
      if entries_count > config.max_project_files then
        core.status_view:show_message("!", style.accent,
          "Too many files in project directory: stopping reading at "..
          config.max_project_files.." files according to config.max_project_files.")
      end
      core.project_files = t
      core.redraw = true
      priority_run = false
    end

    -- wait for next scan
    if core.switch_project then
      system.chdir(core.switch_project)
      priority_run = true
      core.switch_project = nil
    else
      coroutine.yield(config.project_scan_rate)
    end
  end
end


-- create a directory using mkdir but may need to create the parent
-- directories as well.
local function create_user_directory()
  local dirname_create = USERDIR
  local basedir
  local subdirs = {}
  while dirname_create and dirname_create ~= "" do
    local success_mkdir = system.mkdir(dirname_create)
    if success_mkdir then break end
    dirname_create, basedir = dirname_create:match("(.*)[/\\](.+)$")
    if basedir then
      subdirs[#subdirs + 1] = basedir
    end
  end
  for _, dirname in ipairs(subdirs) do
    dirname_create = dirname_create .. '/' .. dirname
    if not system.mkdir(dirname_create) then
      error("cannot create directory: \"" .. dirname_create .. "\"")
    end
  end
  for _, modname in ipairs {'plugins', 'colors'} do
    local subdirname = dirname_create .. '/' .. modname
    if not system.mkdir(subdirname) then
      error("cannot create directory: \"" .. subdirname .. "\"")
    end
  end
end


local function write_user_init_file(init_filename)
  local init_file = io.open(init_filename, "w")
  if not init_file then error("cannot create file: \"" .. init_filename .. "\"") end
  init_file:write([[
-- put user settings here
-- this module will be loaded after everything else when the application starts
-- it will be automatically reloaded when saved

local core = require "core"
local keymap = require "core.keymap"
local config = require "core.config"
local style = require "core.style"

-- light theme:
-- core.reload_module("colors.summer")

-- key binding:
-- keymap.add { ["ctrl+escape"] = "core:quit" }

-- customize fonts:
-- style.font = renderer.font.load(DATADIR .. "/fonts/font.ttf", 14 * SCALE)
-- style.code_font = renderer.font.load(DATADIR .. "/fonts/monospace.ttf", 13.5 * SCALE)
--
-- fonts used by the editor:
-- style.font      : user interface
-- style.big_font  : big text in welcome screen
-- style.icon_font : icons
-- style.code_font : code
--
-- the function to load the font accept a 3rd optional argument like:
--
-- {antialiasing="grayscale", hinting="full"}
--
-- possible values are:
-- antialiasing: grayscale, subpixel
-- hinting: none, slight, full
]])
  init_file:close()
end



function core.load_user_directory()
  return core.try(function()
    local stat_dir = system.get_file_info(USERDIR)
    if not stat_dir then
      create_user_directory()
    end
    local init_filename = USERDIR .. "/init.lua"
    local stat_file = system.get_file_info(init_filename)
    if not stat_file then
      write_user_init_file(init_filename)
    end
    dofile(init_filename)
  end)
end


function core.init()
  command = require "core.command"
  keymap = require "core.keymap"
  RootView = require "core.rootview"
  StatusView = require "core.statusview"
  CommandView = require "core.commandview"
  Doc = require "core.doc"

  load_projects()

  local project_dir = core.recent_projects[1] or "."
  local files = {}
  for i = 2, #ARGS do
    local info = system.get_file_info(ARGS[i]) or {}
    if info.type == "file" then
      table.insert(files, system.absolute_path(ARGS[i]))
    elseif info.type == "dir" then
      project_dir = ARGS[i]
      add_project_to_recents(project_dir)
      save_projects()
    end
  end

  system.chdir(project_dir)

  core.frame_start = 0
  core.clip_rect_stack = {{ 0,0,0,0 }}
  core.log_items = {}
  core.docs = {}
  core.threads = setmetatable({}, { __mode = "k" })
  core.project_files = {}
  core.redraw = true
  core.visited_files = {}
  core.restart_request = false

  core.root_view = RootView()
  core.command_view = CommandView()
  core.status_view = StatusView()

  core.root_view.root_node.is_primary_node = true
  core.root_view.root_node:split("down", core.command_view, true)
  core.root_view.root_node.b:split("down", core.status_view, true)

  core.project_scan_thread_id = core.add_thread(project_scan_thread)
  command.add_defaults()
  local got_plugin_error = not core.load_plugins()
  local got_user_error = not core.load_user_directory()

  do
    local pdir, pname = system.absolute_path(project_dir):match("(.*)[/\\\\](.*)")
    core.log("Opening project %q from directory %q", pname, pdir)
  end
  local got_project_error = not core.load_project_module()

  for _, filename in ipairs(files) do
    core.root_view:open_doc(core.open_doc(filename))
  end

  if got_plugin_error or got_user_error or got_project_error then
    command.perform("core:open-log")
  end
end


function core.confirm_close_all()
  local dirty_count = 0
  local dirty_name
  for _, doc in ipairs(core.docs) do
    if doc:is_dirty() then
      dirty_count = dirty_count + 1
      dirty_name = doc:get_name()
    end
  end
  if dirty_count > 0 then
    local text
    if dirty_count == 1 then
      text = string.format("\"%s\" has unsaved changes. Quit anyway?", dirty_name)
    else
      text = string.format("%d docs have unsaved changes. Quit anyway?", dirty_count)
    end
    local confirm = system.show_confirm_dialog("Unsaved Changes", text)
    if not confirm then return false end
  end
  return true
end

local temp_uid = (system.get_time() * 1000) % 0xffffffff
local temp_file_prefix = string.format(".lite_temp_%08x", temp_uid)
local temp_file_counter = 0

local function delete_temp_files()
  for _, filename in ipairs(system.list_dir(EXEDIR)) do
    if filename:find(temp_file_prefix, 1, true) == 1 then
      os.remove(EXEDIR .. PATHSEP .. filename)
    end
  end
end

function core.temp_filename(ext)
  temp_file_counter = temp_file_counter + 1
  return EXEDIR .. PATHSEP .. temp_file_prefix
      .. string.format("%06x", temp_file_counter) .. (ext or "")
end

-- override to perform an operation before quit
function core.on_quit()
end

local function quit_with_function(quit_fn, force)
  if force then
    delete_temp_files()
    core.on_quit()
    quit_fn()
  else
    if core.confirm_close_all() then
      quit_with_function(quit_fn, true)
    end
  end
end

function core.quit(force)
  quit_with_function(os.exit, force)
end


function core.restart()
  quit_with_function(function() core.restart_request = true end)
end


function core.load_plugins()
  local no_errors = true
  for _, root_dir in ipairs {DATADIR, USERDIR} do
    local files = system.list_dir(root_dir .. "/plugins")
    for _, filename in ipairs(files or {}) do
      local modname = "plugins." .. filename:gsub(".lua$", "")
      local ok = core.try(require, modname)
      if ok then
        core.log_quiet("Loaded plugin %q", modname)
      else
        no_errors = false
      end
    end
  end
  return no_errors
end


function core.load_project_module()
  local filename = ".lite_project.lua"
  if system.get_file_info(filename) then
    return core.try(function()
      local fn, err = loadfile(filename)
      if not fn then error("Error when loading project module:\n\t" .. err) end
      fn()
      core.log_quiet("Loaded project module")
    end)
  end
  return true
end


function core.reload_module(name)
  local old = package.loaded[name]
  package.loaded[name] = nil
  local new = require(name)
  if type(old) == "table" then
    for k, v in pairs(new) do old[k] = v end
    package.loaded[name] = old
  end
end


function core.set_visited(filename)
  for i = 1, #core.visited_files do
    if core.visited_files[i] == filename then
      table.remove(core.visited_files, i)
      break
    end
  end
  table.insert(core.visited_files, 1, filename)
end


function core.set_active_view(view)
  assert(view, "Tried to set active view to nil")
  if view ~= core.active_view then
    if view.doc and view.doc.filename then
      core.set_visited(view.doc.filename)
    end
    core.last_active_view = core.active_view
    core.active_view = view
  end
end


function core.add_thread(f, weak_ref)
  local key = weak_ref or #core.threads + 1
  local fn = function() return core.try(f) end
  core.threads[key] = { cr = coroutine.create(fn), wake = 0 }
  return key
end


function core.push_clip_rect(x, y, w, h)
  local x2, y2, w2, h2 = table.unpack(core.clip_rect_stack[#core.clip_rect_stack])
  local r, b, r2, b2 = x+w, y+h, x2+w2, y2+h2
  x, y = math.max(x, x2), math.max(y, y2)
  b, r = math.min(b, b2), math.min(r, r2)
  w, h = r-x, b-y
  table.insert(core.clip_rect_stack, { x, y, w, h })
  renderer.set_clip_rect(x, y, w, h)
end


function core.pop_clip_rect()
  table.remove(core.clip_rect_stack)
  local x, y, w, h = table.unpack(core.clip_rect_stack[#core.clip_rect_stack])
  renderer.set_clip_rect(x, y, w, h)
end


function core.open_doc(filename)
  if filename then
    -- try to find existing doc for filename
    local abs_filename = system.absolute_path(filename)
    for _, doc in ipairs(core.docs) do
      if doc.filename
      and abs_filename == system.absolute_path(doc.filename) then
        return doc
      end
    end
  end
  -- no existing doc for filename; create new
  local doc = Doc(filename)
  table.insert(core.docs, doc)
  core.log_quiet(filename and "Opened doc \"%s\"" or "Opened new doc", filename)
  return doc
end


function core.get_views_referencing_doc(doc)
  local res = {}
  local views = core.root_view.root_node:get_children()
  for _, view in ipairs(views) do
    if view.doc == doc then table.insert(res, view) end
  end
  return res
end


local function log(icon, icon_color, fmt, ...)
  local text = string.format(fmt, ...)
  if icon then
    core.status_view:show_message(icon, icon_color, text)
  end

  local info = debug.getinfo(2, "Sl")
  local at = string.format("%s:%d", info.short_src, info.currentline)
  local item = { text = text, time = os.time(), at = at }
  table.insert(core.log_items, item)
  if #core.log_items > config.max_log_items then
    table.remove(core.log_items, 1)
  end
  return item
end


function core.log(...)
  return log("i", style.text, ...)
end


function core.log_quiet(...)
  return log(nil, nil, ...)
end


function core.error(...)
  return log("!", style.accent, ...)
end


function core.try(fn, ...)
  local err
  local ok, res = xpcall(fn, function(msg)
    local item = core.error("%s", msg)
    item.info = debug.traceback(nil, 2):gsub("\t", "")
    err = msg
  end, ...)
  if ok then
    return true, res
  end
  return false, err
end


function core.on_event(type, ...)
  local did_keymap = false
  if type == "textinput" then
    core.root_view:on_text_input(...)
  elseif type == "keypressed" then
    did_keymap = keymap.on_key_pressed(...)
  elseif type == "keyreleased" then
    keymap.on_key_released(...)
  elseif type == "mousemoved" then
    core.root_view:on_mouse_moved(...)
  elseif type == "mousepressed" then
    core.root_view:on_mouse_pressed(...)
  elseif type == "mousereleased" then
    core.root_view:on_mouse_released(...)
  elseif type == "mousewheel" then
    core.root_view:on_mouse_wheel(...)
  elseif type == "filedropped" then
    local filename, mx, my = ...
    local info = system.get_file_info(filename)
    if info and info.type == "dir" then
      system.exec(string.format("%q %q", EXEFILE, filename))
    else
      local ok, doc = core.try(core.open_doc, filename)
      if ok then
        local node = core.root_view.root_node:get_child_overlapping_point(mx, my)
        node:set_active_view(node.active_view)
        core.root_view:open_doc(doc)
      end
    end
  elseif type == "focuslost" then
    core.root_view:on_focus_lost(...)
  elseif type == "quit" then
    core.quit()
  end
  return did_keymap
end


function core.step()
  -- handle events
  local did_keymap = false
  local mouse_moved = false
  local mouse = { x = 0, y = 0, dx = 0, dy = 0 }

  for type, a,b,c,d in system.poll_event do
    if type == "mousemoved" then
      mouse_moved = true
      mouse.x, mouse.y = a, b
      mouse.dx, mouse.dy = mouse.dx + c, mouse.dy + d
    elseif type == "textinput" and did_keymap then
      did_keymap = false
    else
      local _, res = core.try(core.on_event, type, a, b, c, d)
      did_keymap = res or did_keymap
    end
    core.redraw = true
  end
  if mouse_moved then
    core.try(core.on_event, "mousemoved", mouse.x, mouse.y, mouse.dx, mouse.dy)
  end

  local width, height = renderer.get_size()

  -- update
  core.root_view.size.x, core.root_view.size.y = width, height
  core.root_view:update()
  if not core.redraw then return false end
  core.redraw = false

  -- close unreferenced docs
  for i = #core.docs, 1, -1 do
    local doc = core.docs[i]
    if #core.get_views_referencing_doc(doc) == 0 then
      table.remove(core.docs, i)
      core.log_quiet("Closed doc \"%s\"", doc:get_name())
    end
  end

  -- update window title
  local name = core.active_view:get_name()
  local title = (name ~= "---") and (name .. " - lite") or  "lite"
  if title ~= core.window_title then
    system.set_window_title(title)
    core.window_title = title
  end

  -- draw
  renderer.begin_frame()
  core.clip_rect_stack[1] = { 0, 0, width, height }
  renderer.set_clip_rect(table.unpack(core.clip_rect_stack[1]))
  core.root_view:draw()
  renderer.end_frame()
  return true
end


local run_threads = coroutine.wrap(function()
  while true do
    local max_time = 1 / config.fps - 0.004
    local need_more_work = false

    for k, thread in pairs(core.threads) do
      -- run thread
      if thread.wake < system.get_time() then
        local _, wait = assert(coroutine.resume(thread.cr))
        if coroutine.status(thread.cr) == "dead" then
          if type(k) == "number" then
            table.remove(core.threads, k)
          else
            core.threads[k] = nil
          end
        elseif wait then
          thread.wake = system.get_time() + wait
        else
          need_more_work = true
        end
      end

      -- stop running threads if we're about to hit the end of frame
      if system.get_time() - core.frame_start > max_time then
        coroutine.yield(true)
      end
    end

    if not need_more_work then coroutine.yield(false) end
  end
end)


function core.run()
  local idle_iterations = 0
  local frame_duration = 1 / config.fps
  while true do
    core.frame_start = system.get_time()
    local did_redraw = core.step()
    local need_more_work = run_threads()
    if core.restart_request then break end
    if not did_redraw and not need_more_work then
      idle_iterations = idle_iterations + 1
      -- do not wait of events at idle_iterations = 1 to give a chance at core.step to run
      -- and set "redraw" flag.
      if idle_iterations > 1 then
        if system.window_has_focus() then
          -- keep running even with no events to make the cursor blinks
          system.wait_event(frame_duration)
        else
          system.wait_event()
        end
      end
    else
      idle_iterations = 0
      local elapsed = system.get_time() - core.frame_start
      system.sleep(math.max(0, frame_duration - elapsed))
    end
  end
end


function core.on_error(err)
  -- write error to file
  local fp = io.open(EXEDIR .. "/error.txt", "wb")
  fp:write("Error: " .. tostring(err) .. "\n")
  fp:write(debug.traceback(nil, 4))
  fp:close()
  -- save copy of all unsaved documents
  for _, doc in ipairs(core.docs) do
    if doc:is_dirty() and doc.filename then
      doc:save(doc.filename .. "~")
    end
  end
end


return core
