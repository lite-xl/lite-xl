require "core.strict"
require "core.regex"
local common = require "core.common"
local config = require "core.config"
local style = require "colors.default"
local command
local keymap
local dirwatch
local ime
local RootView
local StatusView
local TitleView
local CommandView
local NagView
local DocView
local Doc

local core = {}

local function load_session()
  local ok, t = pcall(dofile, USERDIR .. PATHSEP .. "session.lua")
  return ok and t or {}
end


local function save_session()
  local fp = io.open(USERDIR .. PATHSEP .. "session.lua", "w")
  if fp then
    fp:write("return {recents=", common.serialize(core.recent_projects),
      ", window=", common.serialize(table.pack(system.get_window_size(core.window))),
      ", window_mode=", common.serialize(system.get_window_mode(core.window)),
      ", previous_find=", common.serialize(core.previous_find),
      ", previous_replace=", common.serialize(core.previous_replace),
      "}\n")
    fp:close()
  end
end


local function update_recents_project(action, dir_path_abs)
  local dirname = common.normalize_volume(dir_path_abs)
  if not dirname then return end
  local recents = core.recent_projects
  local n = #recents
  for i = 1, n do
    if dirname == recents[i] then
      table.remove(recents, i)
      break
    end
  end
  if action == "add" then
    table.insert(recents, 1, dirname)
  end
end


function core.set_project_dir(new_dir, change_project_fn)
  local chdir_ok = pcall(system.chdir, new_dir)
  if chdir_ok then
    if change_project_fn then change_project_fn() end
    core.project_dir = common.normalize_volume(new_dir)
    core.project_directories = {}
  end
  return chdir_ok
end


local function reload_customizations()
  local user_error = not core.load_user_directory()
  local project_error = not core.load_project_module()
  if user_error or project_error then
    -- Use core.add_thread to delay opening the LogView, as opening
    -- it directly here disturbs the normal save operations.
    core.add_thread(function()
      local LogView = require "core.logview"
      local rn = core.root_view.root_node
      for _,v in pairs(core.root_view.root_node:get_children()) do
        if v:is(LogView) then
          rn:get_node_for_view(v):set_active_view(v)
          return
        end
      end
      command.perform("core:open-log")
    end)
  end
end


function core.open_folder_project(dir_path_abs)
  if core.set_project_dir(dir_path_abs, core.on_quit_project) then
    core.root_view:close_all_docviews()
    reload_customizations()
    update_recents_project("add", dir_path_abs)
    core.add_project_directory(dir_path_abs)
    core.on_enter_project(dir_path_abs)
  end
end


local function strip_leading_path(filename)
    return filename:sub(2)
end

local function strip_trailing_slash(filename)
  if filename:match("[^:]["..PATHSEP.."]$") then
    return filename:sub(1, -2)
  end
  return filename
end


function core.project_subdir_is_shown(dir, filename)
  return not dir.files_limit or dir.shown_subdir[filename]
end


local function show_max_files_warning(dir)
  local message = dir.slow_filesystem and
    "Filesystem is too slow: project files will not be indexed." or
    "Too many files in project directory: stopped reading at "..
    config.max_project_files.." files. For more information see "..
    "usage.md at https://github.com/lite-xl/lite-xl."
  core.warn(message)
end


-- bisects the sorted file list to get to things in ln(n)
local function file_bisect(files, is_superior, start_idx, end_idx)
  local inf, sup = start_idx or 1, end_idx or #files
  while sup - inf > 8 do
    local curr = math.floor((inf + sup) / 2)
    if is_superior(files[curr]) then
      sup = curr - 1
    else
      inf = curr
    end
  end
  while inf <= sup and not is_superior(files[inf]) do
    inf = inf + 1
  end
  return inf
end


local function file_search(files, info)
  local idx = file_bisect(files, function(file)
    return system.path_compare(info.filename, info.type, file.filename, file.type)
  end)
  if idx > 1 and files[idx-1].filename == info.filename then
    return idx - 1, true
  end
  return idx, false
end


local function files_info_equal(a, b)
  return (a == nil and b == nil) or (a and b and a.filename == b.filename and a.type == b.type)
end


local function project_subdir_bounds(dir, filename, start_index)
  local found = true
  if not start_index then
    start_index, found = file_search(dir.files, { type = "dir", filename = filename })
  end
  if found then
    local end_index = file_bisect(dir.files, function(file)
      return not common.path_belongs_to(file.filename, filename)
    end, start_index + 1)
    return start_index, end_index - start_index, dir.files[start_index]
  end
end


-- Should be called on any directory that registers a change, or on a directory we open if we're over the file limit.
-- Uses relative paths at the project root (i.e. target = "", target = "first-level-directory", target = "first-level-directory/second-level-directory")
local function refresh_directory(topdir, target)
  local directory_start_idx, directory_end_idx = 1, #topdir.files
  if target and target ~= "" then
    directory_start_idx, directory_end_idx = project_subdir_bounds(topdir, target)
    directory_end_idx = directory_start_idx + directory_end_idx - 1
    directory_start_idx = directory_start_idx + 1
  end

  local files = dirwatch.get_directory_files(topdir, topdir.name, (target or ""), 0, function() return false end)
  local change = false

  -- If this file doesn't exist, we should be calling this on our parent directory, assume we'll do that.
  -- Unwatch just in case.
  if files == nil then
    topdir.watch:unwatch(topdir.name .. PATHSEP .. (target or ""))
    return true
  end

  local new_idx, old_idx = 1, directory_start_idx
  local new_directories = {}
  -- Run through each sorted list and compare them. If we find a new entry, insert it and flag as new. If we're missing an entry
  -- remove it and delete the entry from the list.
  while old_idx <= directory_end_idx or new_idx <= #files do
    local old_info, new_info = topdir.files[old_idx], files[new_idx]
    if not files_info_equal(new_info, old_info) then
      change = true
      -- If we're a new file, and we exist *before* the other file in the list, then add to the list.
      if not old_info or (new_info and system.path_compare(new_info.filename, new_info.type, old_info.filename, old_info.type)) then
        table.insert(topdir.files, old_idx, new_info)
        old_idx, new_idx = old_idx + 1, new_idx + 1
        if new_info.type == "dir" then
          table.insert(new_directories, new_info)
        end
        directory_end_idx = directory_end_idx + 1
      else
      -- If it's not there, remove the entry from the list as being out of order.
        table.remove(topdir.files, old_idx)
        if old_info.type == "dir" then
          topdir.watch:unwatch(topdir.name .. PATHSEP .. old_info.filename)
        end
        directory_end_idx = directory_end_idx - 1
      end
    else
      -- If this file is a directory, determine in ln(n) the size of the directory, and skip every file in it.
      local size = old_info and old_info.type == "dir" and select(2, project_subdir_bounds(topdir, old_info.filename, old_idx)) or 1
      old_idx, new_idx = old_idx + size, new_idx + 1
    end
  end
  for i, v in ipairs(new_directories) do
    topdir.watch:watch(topdir.name .. PATHSEP .. v.filename)
    if not topdir.files_limit or core.project_subdir_is_shown(topdir, v.filename) then
      refresh_directory(topdir, v.filename)
    end
  end
  if change then
    core.redraw = true
    topdir.is_dirty = true
  end
  return change
end


-- Predicate function to inhibit directory recursion in get_directory_files
-- based on a time limit and the number of files.
local function timed_max_files_pred(dir, filename, entries_count, t_elapsed)
  local n_limit = entries_count <= config.max_project_files
  local t_limit = t_elapsed < 20 / config.fps
  return n_limit and t_limit and core.project_subdir_is_shown(dir, filename)
end


function core.add_project_directory(path)
  -- top directories has a file-like "item" but the item.filename
  -- will be simply the name of the directory, without its path.
  -- The field item.topdir will identify it as a top level directory.
  path = common.normalize_volume(path)
  local topdir = {
    name = path,
    item = {filename = common.basename(path), type = "dir", topdir = true},
    files_limit = false,
    is_dirty = true,
    shown_subdir = {},
    watch_thread = nil,
    watch = dirwatch.new()
  }
  table.insert(core.project_directories, topdir)

  local fstype = PLATFORM == "Linux" and system.get_fs_type(topdir.name) or "unknown"
  topdir.force_scans = (fstype == "nfs" or fstype == "fuse")
  local t, complete, entries_count = dirwatch.get_directory_files(topdir, topdir.name, "", 0, timed_max_files_pred)
  topdir.files = t
  if not complete then
    topdir.slow_filesystem = not complete and (entries_count <= config.max_project_files)
    topdir.files_limit = true
    show_max_files_warning(topdir)
    refresh_directory(topdir)
  else
    for i,v in ipairs(t) do
      if v.type == "dir" then topdir.watch:watch(path .. PATHSEP .. v.filename) end
    end
  end
  topdir.watch:watch(topdir.name)
  -- each top level directory gets a watch thread. if the project is small, or
  -- if the ablity to use directory watches hasn't been compromised in some way
  -- either through error, or amount of files, then this should be incredibly
  -- quick; essentially one syscall per check. Otherwise, this may take a bit of
  -- time; the watch will yield in this coroutine after 0.01 second, for 0.1 seconds.
  topdir.watch_thread = core.add_thread(function()
    while true do
      local changed = topdir.watch:check(function(target)
        if target == topdir.name then return refresh_directory(topdir) end
        local dirpath = target:sub(#topdir.name + 2)
        local abs_dirpath = topdir.name .. PATHSEP .. dirpath
        if dirpath then
          -- check if the directory is in the project files list, if not exit.
          local dir_index, dir_match = file_search(topdir.files, {filename = dirpath, type = "dir"})
          if not dir_match or not core.project_subdir_is_shown(topdir, topdir.files[dir_index].filename) then return end
        end
        return refresh_directory(topdir, dirpath)
      end, 0.01, 0.01)
      -- properly exit coroutine if project not open anymore to clear dir watch
      local project_dir_open = false
      for _, prj in ipairs(core.project_directories) do
        if topdir == prj then
          project_dir_open = true
          break
        end
      end
      if project_dir_open then
        coroutine.yield(changed and 0 or 0.05)
      else
        return
      end
    end
  end)

  if path == core.project_dir then
    core.project_files = topdir.files
  end
  core.redraw = true
  return topdir
end


-- The function below is needed to reload the project directories
-- when the project's module changes.
function core.rescan_project_directories()
  local save_project_dirs = {}
  local n = #core.project_directories
  for i = 1, n do
    local dir = core.project_directories[i]
    save_project_dirs[i] = {name = dir.name, shown_subdir = dir.shown_subdir}
  end
  core.project_directories = {}
  for i = 1, n do -- add again the directories in the project
    local dir = core.add_project_directory(save_project_dirs[i].name)
    if dir.files_limit then
      -- We need to sort the list of shown subdirectories so that higher level
      -- directories are populated first. We use the function system.path_compare
      -- because it order the entries in the appropriate order.
      -- TODO: we may consider storing the table shown_subdir as a sorted table
      -- since the beginning.
      local subdir_list = {}
      for subdir in pairs(save_project_dirs[i].shown_subdir) do
        table.insert(subdir_list, subdir)
      end
      table.sort(subdir_list, function(a, b) return system.path_compare(a, "dir", b, "dir") end)
      for _, subdir in ipairs(subdir_list) do
        local show = save_project_dirs[i].shown_subdir[subdir]
        for j = 1, #dir.files do
          if dir.files[j].filename == subdir then
            -- The instructions below match when happens in TreeView:on_mouse_pressed.
            -- We perform the operations only once iff the subdir is in dir.files.
            -- In theory set_show below may fail and return false but is it is listed
            -- there it means it succeeded before so we are optimistically assume it
            -- will not fail for the sake of simplicity.
            core.update_project_subdir(dir, subdir, show)
            break
          end
        end
      end
    end
  end
end


function core.project_dir_by_name(name)
  for i = 1, #core.project_directories do
    if core.project_directories[i].name == name then
      return core.project_directories[i]
    end
  end
end


function core.update_project_subdir(dir, filename, expanded)
  assert(dir.files_limit, "function should be called only when directory is in files limit mode")
  dir.shown_subdir[filename] = expanded
  if expanded then
    dir.watch:watch(dir.name .. PATHSEP .. filename)
  else
    dir.watch:unwatch(dir.name .. PATHSEP .. filename)
  end
  return refresh_directory(dir, filename)
end


-- Find files and directories recursively reading from the filesystem.
-- Filter files and yields file's directory and info table. This latter
-- is filled to be like required by project directories "files" list.
local function find_files_rec(root, path)
  local all = system.list_dir(root .. path) or {}
  for _, file in ipairs(all) do
    local file = path .. PATHSEP .. file
    local info = system.get_file_info(root .. file)
    if info then
      info.filename = strip_leading_path(file)
      if info.type == "file" then
        coroutine.yield(root, info)
      elseif not common.match_pattern(common.basename(info.filename), config.ignore_files) then
        find_files_rec(root, PATHSEP .. info.filename)
      end
    end
  end
end


-- Iterator function to list all project files
local function project_files_iter(state)
  local dir = core.project_directories[state.dir_index]
  if state.co then
    -- We have a coroutine to fetch for files, use the coroutine.
    -- Used for directories that exceeds the files nuumber limit.
    local ok, name, file = coroutine.resume(state.co, dir.name, "")
    if ok and name then
      return name, file
    else
      -- The coroutine terminated, increment file/dir counter to scan
      -- next project directory.
      state.co = false
      state.file_index = 1
      state.dir_index = state.dir_index + 1
      dir = core.project_directories[state.dir_index]
    end
  else
    -- Increase file/dir counter
    state.file_index = state.file_index + 1
    while dir and state.file_index > #dir.files do
      state.dir_index = state.dir_index + 1
      state.file_index = 1
      dir = core.project_directories[state.dir_index]
    end
  end
  if not dir then return end
  if dir.files_limit then
    -- The current project directory is files limited: create a couroutine
    -- to read files from the filesystem.
    state.co = coroutine.create(find_files_rec)
    return project_files_iter(state)
  end
  return dir.name, dir.files[state.file_index]
end


function core.get_project_files()
  local state = { dir_index = 1, file_index = 0 }
  return project_files_iter, state
end


function core.project_files_number()
  local n = 0
  for i = 1, #core.project_directories do
    if core.project_directories[i].files_limit then return end
    n = n + #core.project_directories[i].files
  end
  return n
end


-- create a directory using mkdir but may need to create the parent
-- directories as well.
local function create_user_directory()
  local success, err = common.mkdirp(USERDIR)
  if not success then
    error("cannot create directory \"" .. USERDIR .. "\": " .. err)
  end
  for _, modname in ipairs {'plugins', 'colors', 'fonts'} do
    local subdirname = USERDIR .. PATHSEP .. modname
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

------------------------------ Themes ----------------------------------------

-- light theme:
-- core.reload_module("colors.summer")

--------------------------- Key bindings -------------------------------------

-- key binding:
-- keymap.add { ["ctrl+escape"] = "core:quit" }

-- pass 'true' for second parameter to overwrite an existing binding
-- keymap.add({ ["ctrl+pageup"] = "root:switch-to-previous-tab" }, true)
-- keymap.add({ ["ctrl+pagedown"] = "root:switch-to-next-tab" }, true)

------------------------------- Fonts ----------------------------------------

-- customize fonts:
-- style.font = renderer.font.load(DATADIR .. "/fonts/FiraSans-Regular.ttf", 14 * SCALE)
-- style.code_font = renderer.font.load(DATADIR .. "/fonts/JetBrainsMono-Regular.ttf", 14 * SCALE)
--
-- DATADIR is the location of the installed Lite XL Lua code, default color
-- schemes and fonts.
-- USERDIR is the location of the Lite XL configuration directory.
--
-- font names used by lite:
-- style.font          : user interface
-- style.big_font      : big text in welcome screen
-- style.icon_font     : icons
-- style.icon_big_font : toolbar icons
-- style.code_font     : code
--
-- the function to load the font accept a 3rd optional argument like:
--
-- {antialiasing="grayscale", hinting="full", bold=true, italic=true, underline=true, smoothing=true, strikethrough=true}
--
-- possible values are:
-- antialiasing: grayscale, subpixel
-- hinting: none, slight, full
-- bold: true, false
-- italic: true, false
-- underline: true, false
-- smoothing: true, false
-- strikethrough: true, false

------------------------------ Plugins ----------------------------------------

-- disable plugin loading setting config entries:

-- disable plugin detectindent, otherwise it is enabled by default:
-- config.plugins.detectindent = false

---------------------------- Miscellaneous -------------------------------------

-- modify list of files to ignore when indexing the project:
-- config.ignore_files = {
--   -- folders
--   "^%.svn/",        "^%.git/",   "^%.hg/",        "^CVS/", "^%.Trash/", "^%.Trash%-.*/",
--   "^node_modules/", "^%.cache/", "^__pycache__/",
--   -- files
--   "%.pyc$",         "%.pyo$",       "%.exe$",        "%.dll$",   "%.obj$", "%.o$",
--   "%.a$",           "%.lib$",       "%.so$",         "%.dylib$", "%.ncb$", "%.sdf$",
--   "%.suo$",         "%.pdb$",       "%.idb$",        "%.class$", "%.psd$", "%.db$",
--   "^desktop%.ini$", "^%.DS_Store$", "^%.directory$",
-- }

]])
  init_file:close()
end


function core.write_init_project_module(init_filename)
  local init_file = io.open(init_filename, "w")
  if not init_file then error("cannot create file: \"" .. init_filename .. "\"") end
  init_file:write([[
-- Put project's module settings here.
-- This module will be loaded when opening a project, after the user module
-- configuration.
-- It will be automatically reloaded when saved.

local config = require "core.config"

-- you can add some patterns to ignore files within the project
-- config.ignore_files = {"^%.", <some-patterns>}

-- Patterns are normally applied to the file's or directory's name, without
-- its path. See below about how to apply filters on a path.
--
-- Here some examples:
--
-- "^%." matches any file of directory whose basename begins with a dot.
--
-- When there is an '/' or a '/$' at the end, the pattern will only match
-- directories. When using such a pattern a final '/' will be added to the name
-- of any directory entry before checking if it matches.
--
-- "^%.git/" matches any directory named ".git" anywhere in the project.
--
-- If a "/" appears anywhere in the pattern (except when it appears at the end or
-- is immediately followed by a '$'), then the pattern will be applied to the full
-- path of the file or directory. An initial "/" will be prepended to the file's
-- or directory's path to indicate the project's root.
--
-- "^/node_modules/" will match a directory named "node_modules" at the project's root.
-- "^/build.*/" will match any top level directory whose name begins with "build".
-- "^/subprojects/.+/" will match any directory inside a top-level folder named "subprojects".

-- You may activate some plugins on a per-project basis to override the user's settings.
-- config.plugins.trimwitespace = true
]])
  init_file:close()
end


function core.load_user_directory()
  return core.try(function()
    local stat_dir = system.get_file_info(USERDIR)
    if not stat_dir then
      create_user_directory()
    end
    local init_filename = USERDIR .. PATHSEP .. "init.lua"
    local stat_file = system.get_file_info(init_filename)
    if not stat_file then
      write_user_init_file(init_filename)
    end
    dofile(init_filename)
  end)
end


function core.remove_project_directory(path)
  -- skip the fist directory because it is the project's directory
  for i = 2, #core.project_directories do
    local dir = core.project_directories[i]
    if dir.name == path then
      table.remove(core.project_directories, i)
      return true
    end
  end
  return false
end


function core.configure_borderless_window()
  system.set_window_bordered(not config.borderless)
  core.title_view:configure_hit_test(config.borderless)
  core.title_view.visible = config.borderless
end


local function add_config_files_hooks()
  -- auto-realod style when user's module is saved by overriding Doc:Save()
  local doc_save = Doc.save
  local user_filename = system.absolute_path(USERDIR .. PATHSEP .. "init.lua")
  function Doc:save(filename, abs_filename)
    local module_filename = system.absolute_path(".lite_project.lua")
    doc_save(self, filename, abs_filename)
    if self.abs_filename == user_filename or self.abs_filename == module_filename then
      reload_customizations()
      core.rescan_project_directories()
      core.configure_borderless_window()
    end
  end
end


-- The function below works like system.absolute_path except it
-- doesn't fail if the file does not exist. We consider that the
-- current dir is core.project_dir so relative filename are considered
-- to be in core.project_dir.
-- Please note that .. or . in the filename are not taken into account.
-- This function should get only filenames normalized using
-- common.normalize_path function.
function core.project_absolute_path(filename)
  if common.is_absolute_path(filename) then
    return common.normalize_path(filename)
  elseif not core.project_dir then
    local cwd = system.absolute_path(".")
    return cwd .. PATHSEP .. common.normalize_path(filename)
  else
    return core.project_dir .. PATHSEP .. filename
  end
end


function core.init()
  core.log_items = {}
  core.log_quiet("Lite XL version %s - mod-version %s", VERSION, MOD_VERSION_STRING)

  command = require "core.command"
  keymap = require "core.keymap"
  dirwatch = require "core.dirwatch"
  ime = require "core.ime"
  RootView = require "core.rootview"
  StatusView = require "core.statusview"
  TitleView = require "core.titleview"
  CommandView = require "core.commandview"
  NagView = require "core.nagview"
  DocView = require "core.docview"
  Doc = require "core.doc"

  if PATHSEP == '\\' then
    USERDIR = common.normalize_volume(USERDIR)
    DATADIR = common.normalize_volume(DATADIR)
    EXEDIR  = common.normalize_volume(EXEDIR)
  end

  core.window = renwindow._restore()
  if core.window == nil then
    core.window = renwindow.create("")
  end
  do
    local session = load_session()
    if session.window_mode == "normal" then
      system.set_window_size(core.window, table.unpack(session.window))
    elseif session.window_mode == "maximized" then
      system.set_window_mode(core.window, "maximized")
    end
    core.recent_projects = session.recents or {}
    core.previous_find = session.previous_find or {}
    core.previous_replace = session.previous_replace or {}
  end

  local project_dir = core.recent_projects[1] or "."
  local project_dir_explicit = false
  local files = {}
  for i = 2, #ARGS do
    local arg_filename = strip_trailing_slash(ARGS[i])
    local info = system.get_file_info(arg_filename) or {}
    if info.type == "dir" then
      project_dir = arg_filename
      project_dir_explicit = true
    else
      -- on macOS we can get an argument like "-psn_0_52353" that we just ignore.
      if not ARGS[i]:match("^-psn") then
        local file_abs = core.project_absolute_path(arg_filename)
        if file_abs then
          table.insert(files, file_abs)
          project_dir = file_abs:match("^(.+)[/\\].+$")
        end
      end
    end
  end

  core.frame_start = 0
  core.clip_rect_stack = {{ 0,0,0,0 }}
  core.docs = {}
  core.cursor_clipboard = {}
  core.cursor_clipboard_whole_line = {}
  core.window_mode = "normal"
  core.threads = setmetatable({}, { __mode = "k" })
  core.blink_start = system.get_time()
  core.blink_timer = core.blink_start
  core.redraw = true
  core.visited_files = {}
  core.restart_request = false
  core.quit_request = false

  -- We load core views before plugins that may need them.
  ---@type core.rootview
  core.root_view = RootView()
  ---@type core.commandview
  core.command_view = CommandView()
  ---@type core.statusview
  core.status_view = StatusView()
  ---@type core.nagview
  core.nag_view = NagView()
  ---@type core.titleview
  core.title_view = TitleView()

  -- Some plugins (eg: console) require the nodes to be initialized to defaults
  local cur_node = core.root_view.root_node
  cur_node.is_primary_node = true
  cur_node:split("up", core.title_view, {y = true})
  cur_node = cur_node.b
  cur_node:split("up", core.nag_view, {y = true})
  cur_node = cur_node.b
  cur_node = cur_node:split("down", core.command_view, {y = true})
  cur_node = cur_node:split("down", core.status_view, {y = true})

  -- Load default commands first so plugins can override them
  command.add_defaults()

  -- Load user module, plugins and project module
  local got_user_error, got_project_error = not core.load_user_directory()

  local project_dir_abs = system.absolute_path(project_dir)
  -- We prevent set_project_dir below to effectively add and scan the directory because the
  -- project module and its ignore files is not yet loaded.
  local set_project_ok = project_dir_abs and core.set_project_dir(project_dir_abs)
  if set_project_ok then
    got_project_error = not core.load_project_module()
    if project_dir_explicit then
      update_recents_project("add", project_dir_abs)
    end
  else
    if not project_dir_explicit then
      update_recents_project("remove", project_dir)
    end
    project_dir_abs = system.absolute_path(".")
    if not core.set_project_dir(project_dir_abs, function()
      got_project_error = not core.load_project_module()
    end) then
      system.show_fatal_error("Lite XL internal error", "cannot set project directory to cwd")
      os.exit(1)
    end
  end

  -- Load core and user plugins giving preference to user ones with same name.
  local plugins_success, plugins_refuse_list = core.load_plugins()

  do
    local pdir, pname = project_dir_abs:match("(.*)[/\\\\](.*)")
    core.log("Opening project %q from directory %s", pname, pdir)
  end

  -- We add the project directory now because the project's module is loaded.
  core.add_project_directory(project_dir_abs)

  -- We assume we have just a single project directory here. Now that StatusView
  -- is there show max files warning if needed.
  if core.project_directories[1].files_limit then
    show_max_files_warning(core.project_directories[1])
  end

  for _, filename in ipairs(files) do
    core.root_view:open_doc(core.open_doc(filename))
  end

  if not plugins_success or got_user_error or got_project_error then
    -- defer LogView to after everything is initialized,
    -- so that EmptyView won't be added after LogView.
    core.add_thread(function()
      command.perform("core:open-log")
    end)
  end

  core.configure_borderless_window()

  if #plugins_refuse_list.userdir.plugins > 0 or #plugins_refuse_list.datadir.plugins > 0 then
    local opt = {
      { text = "Exit", default_no = true },
      { text = "Continue", default_yes = true }
    }
    local msg = {}
    for _, entry in pairs(plugins_refuse_list) do
      if #entry.plugins > 0 then
        local msg_list = {}
        for _, p in pairs(entry.plugins) do
          table.insert(msg_list, string.format("%s[%s]", p.file, p.version_string))
        end
        msg[#msg + 1] = string.format("Plugins from directory \"%s\":\n%s", common.home_encode(entry.dir), table.concat(msg_list, "\n"))
      end
    end
    core.nag_view:show(
      "Refused Plugins",
      string.format(
        "Some plugins are not loaded due to version mismatch. Expected version %s.\n\n%s.\n\n" ..
        "Please download a recent version from https://github.com/lite-xl/lite-xl-plugins.",
        MOD_VERSION_STRING, table.concat(msg, ".\n\n")),
      opt, function(item)
        if item.text == "Exit" then os.exit(1) end
      end)
  end

  add_config_files_hooks()
end


function core.confirm_close_docs(docs, close_fn, ...)
  local dirty_count = 0
  local dirty_name
  for _, doc in ipairs(docs or core.docs) do
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
    local args = {...}
    local opt = {
      { text = "Yes", default_yes = true },
      { text = "No", default_no = true }
    }
    core.nag_view:show("Unsaved Changes", text, opt, function(item)
      if item.text == "Yes" then close_fn(table.unpack(args)) end
    end)
  else
    close_fn(...)
  end
end

local temp_uid = math.floor(system.get_time() * 1000) % 0xffffffff
local temp_file_prefix = string.format(".lite_temp_%08x", tonumber(temp_uid))
local temp_file_counter = 0

function core.delete_temp_files(dir)
  dir = type(dir) == "string" and common.normalize_path(dir) or USERDIR
  for _, filename in ipairs(system.list_dir(dir) or {}) do
    if filename:find(temp_file_prefix, 1, true) == 1 then
      os.remove(dir .. PATHSEP .. filename)
    end
  end
end

function core.temp_filename(ext, dir)
  dir = type(dir) == "string" and common.normalize_path(dir) or USERDIR
  temp_file_counter = temp_file_counter + 1
  return dir .. PATHSEP .. temp_file_prefix
      .. string.format("%06x", temp_file_counter) .. (ext or "")
end

-- override to perform an operation before quitting or entering the
-- current project
do
  local do_nothing = function() end
  core.on_quit_project = do_nothing
  core.on_enter_project = do_nothing
end


local function quit_with_function(quit_fn, force)
  if force then
    core.delete_temp_files()
    core.on_quit_project()
    save_session()
    quit_fn()
  else
    core.confirm_close_docs(core.docs, quit_with_function, quit_fn, true)
  end
end

function core.quit(force)
  quit_with_function(function() core.quit_request = true end, force)
end


function core.restart()
  quit_with_function(function()
    core.restart_request = true
    core.window:_persist()
  end)
end


local mod_version_regex =
  regex.compile([[--.*mod-version:(\d+)(?:\.(\d+))?(?:\.(\d+))?(?:$|\s)]])
local function get_plugin_details(filename)
  local info = system.get_file_info(filename)
  if info ~= nil and info.type == "dir" then
    filename = filename .. PATHSEP .. "init.lua"
    info = system.get_file_info(filename)
  end
  if not info or not filename:match("%.lua$") then return false end
  local f = io.open(filename, "r")
  if not f then return false end
  local priority = false
  local version_match = false
  local major, minor, patch

  for line in f:lines() do
    if not version_match then
      local _major, _minor, _patch = mod_version_regex:match(line)
      if _major then
        _major = tonumber(_major) or 0
        _minor = tonumber(_minor) or 0
        _patch = tonumber(_patch) or 0
        major, minor, patch = _major, _minor, _patch

        version_match = major == MOD_VERSION_MAJOR
        if version_match then
          version_match = minor <= MOD_VERSION_MINOR
        end
        if version_match then
          version_match = patch <= MOD_VERSION_PATCH
        end
      end
    end

    if not priority then
      priority = line:match('%-%-.*%f[%a]priority%s*:%s*(%d+)')
      if priority then priority = tonumber(priority) end
    end

    if version_match then
      break
    end
  end
  f:close()
  return true, {
    version_match = version_match,
    version = major and {major, minor, patch} or {},
    priority = priority or 100
  }
end


function core.load_plugins()
  local no_errors = true
  local refused_list = {
    userdir = {dir = USERDIR, plugins = {}},
    datadir = {dir = DATADIR, plugins = {}},
  }
  local files, ordered = {}, {}
  for _, root_dir in ipairs {DATADIR, USERDIR} do
    local plugin_dir = root_dir .. PATHSEP .. "plugins"
    for _, filename in ipairs(system.list_dir(plugin_dir) or {}) do
      if not files[filename] then
        table.insert(
          ordered, {file = filename}
        )
      end
      -- user plugins will always replace system plugins
      files[filename] = plugin_dir
    end
  end

  for _, plugin in ipairs(ordered) do
    local dir = files[plugin.file]
    local name = plugin.file:match("(.-)%.lua$") or plugin.file
    local is_lua_file, details = get_plugin_details(dir .. PATHSEP .. plugin.file)

    plugin.valid = is_lua_file
    plugin.name = name
    plugin.dir = dir
    plugin.priority = details and details.priority or 100
    plugin.version_match = details and details.version_match or false
    plugin.version = details and details.version or {}
    plugin.version_string = #plugin.version > 0 and table.concat(plugin.version, ".") or "unknown"
  end

  -- sort by priority or name for plugins that have same priority
  table.sort(ordered, function(a, b)
    if a.priority ~= b.priority then
      return a.priority < b.priority
    end
    return a.name < b.name
  end)

  local load_start = system.get_time()
  for _, plugin in ipairs(ordered) do
    if plugin.valid then
      if not config.skip_plugins_version and not plugin.version_match then
        core.log_quiet(
          "Version mismatch for plugin %q[%s] from %s",
          plugin.name,
          plugin.version_string,
          plugin.dir
        )
        local rlist = plugin.dir:find(USERDIR, 1, true) == 1
          and 'userdir' or 'datadir'
        local list = refused_list[rlist].plugins
        table.insert(list, plugin)
      elseif config.plugins[plugin.name] ~= false then
        local start = system.get_time()
        local ok, loaded_plugin = core.try(require, "plugins." .. plugin.name)
        if ok then
          local plugin_version = ""
          if plugin.version_string ~= MOD_VERSION_STRING then
            plugin_version = "["..plugin.version_string.."]"
          end
          core.log_quiet(
            "Loaded plugin %q%s from %s in %.1fms",
            plugin.name,
            plugin_version,
            plugin.dir,
            (system.get_time() - start) * 1000
          )
        end
        if not ok then
          no_errors = false
        elseif config.plugins[plugin.name].onload then
          core.try(config.plugins[plugin.name].onload, loaded_plugin)
        end
      end
    end
  end
  core.log_quiet(
    "Loaded all plugins in %.1fms",
    (system.get_time() - load_start) * 1000
  )
  return no_errors, refused_list
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
  -- Reset the IME even if the focus didn't change
  ime.stop()
  if view ~= core.active_view then
    system.text_input(view:supports_text_input())
    if core.active_view and core.active_view.force_focus then
      core.next_active_view = view
      return
    end
    core.next_active_view = nil
    if view.doc and view.doc.filename then
      core.set_visited(view.doc.filename)
    end
    core.last_active_view = core.active_view
    core.active_view = view
  end
end


function core.show_title_bar(show)
  core.title_view.visible = show
end


local thread_counter = 0
function core.add_thread(f, weak_ref, ...)
  local key = weak_ref
  if not key then
    thread_counter = thread_counter + 1
    key = thread_counter
  end
  assert(core.threads[key] == nil, "Duplicate thread reference")
  local args = {...}
  local fn = function() return core.try(f, table.unpack(args)) end
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


function core.normalize_to_project_dir(filename)
  filename = common.normalize_path(filename)
  if common.path_belongs_to(filename, core.project_dir) then
    filename = common.relative_path(core.project_dir, filename)
  end
  return filename
end


function core.open_doc(filename)
  local new_file = not filename or not system.get_file_info(filename)
  local abs_filename
  if filename then
    -- normalize filename and set absolute filename then
    -- try to find existing doc for filename
    filename = core.normalize_to_project_dir(filename)
    abs_filename = core.project_absolute_path(filename)
    for _, doc in ipairs(core.docs) do
      if doc.abs_filename and abs_filename == doc.abs_filename then
        return doc
      end
    end
  end
  -- no existing doc for filename; create new
  local doc = Doc(filename, abs_filename, new_file)
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


function core.custom_log(level, show, backtrace, fmt, ...)
  local text = string.format(fmt, ...)
  if show then
    local s = style.log[level]
    if core.status_view then
      core.status_view:show_message(s.icon, s.color, text)
    end
  end

  local info = debug.getinfo(2, "Sl")
  local at = string.format("%s:%d", info.short_src, info.currentline)
  local item = {
    level = level,
    text = text,
    time = os.time(),
    at = at,
    info = backtrace and debug.traceback("", 2):gsub("\t", "")
  }
  table.insert(core.log_items, item)
  if #core.log_items > config.max_log_items then
    table.remove(core.log_items, 1)
  end
  return item
end


function core.log(...)
  return core.custom_log("INFO", true, false, ...)
end


function core.log_quiet(...)
  return core.custom_log("INFO", false, false, ...)
end

function core.warn(...)
  return core.custom_log("WARN", true, true, ...)
end

function core.error(...)
  return core.custom_log("ERROR", true, true, ...)
end


function core.get_log(i)
  if i == nil then
    local r = {}
    for _, item in ipairs(core.log_items) do
      table.insert(r, core.get_log(item))
    end
    return table.concat(r, "\n")
  end
  local item = type(i) == "number" and core.log_items[i] or i
  local text = string.format("%s [%s] %s at %s", os.date(nil, item.time), item.level, item.text, item.at)
  if item.info then
    text = string.format("%s\n%s\n", text, item.info)
  end
  return text
end


function core.try(fn, ...)
  local err
  local ok, res = xpcall(fn, function(msg)
    local item = core.error("%s", msg)
    item.info = debug.traceback("", 2):gsub("\t", "")
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
  elseif type == "textediting" then
    ime.on_text_editing(...)
  elseif type == "keypressed" then
    -- In some cases during IME composition input is still sent to us
    -- so we just ignore it.
    if ime.editing then return false end
    did_keymap = keymap.on_key_pressed(...)
  elseif type == "keyreleased" then
    keymap.on_key_released(...)
  elseif type == "mousemoved" then
    core.root_view:on_mouse_moved(...)
  elseif type == "mousepressed" then
    if not core.root_view:on_mouse_pressed(...) then
      did_keymap = keymap.on_mouse_pressed(...)
    end
  elseif type == "mousereleased" then
    core.root_view:on_mouse_released(...)
  elseif type == "mouseleft" then
    core.root_view:on_mouse_left()
  elseif type == "mousewheel" then
    if not core.root_view:on_mouse_wheel(...) then
      did_keymap = keymap.on_mouse_wheel(...)
    end
  elseif type == "touchpressed" then
    core.root_view:on_touch_pressed(...)
  elseif type == "touchreleased" then
    core.root_view:on_touch_released(...)
  elseif type == "touchmoved" then
    core.root_view:on_touch_moved(...)
  elseif type == "resized" then
    core.window_mode = system.get_window_mode(core.window)
  elseif type == "minimized" or type == "maximized" or type == "restored" then
    core.window_mode = type == "restored" and "normal" or type
  elseif type == "filedropped" then
    core.root_view:on_file_dropped(...)
  elseif type == "focuslost" then
    core.root_view:on_focus_lost(...)
  elseif type == "quit" then
    core.quit()
  end
  return did_keymap
end


local function get_title_filename(view)
  local doc_filename = view.get_filename and view:get_filename() or view:get_name()
  if doc_filename ~= "---" then return doc_filename end
  return ""
end


function core.compose_window_title(title)
  return (title == "" or title == nil) and "Lite XL" or title .. " - Lite XL"
end


function core.step()
  -- handle events
  local did_keymap = false

  for type, a,b,c,d in system.poll_event do
    if type == "textinput" and did_keymap then
      did_keymap = false
    elseif type == "mousemoved" then
      core.try(core.on_event, type, a, b, c, d)
    elseif type == "enteringforeground" then
      -- to break our frame refresh in two if we get entering/entered at the same time.
      -- required to avoid flashing and refresh issues on mobile
      core.redraw = true
      break
    else
      local _, res = core.try(core.on_event, type, a, b, c, d)
      did_keymap = res or did_keymap
    end
    core.redraw = true
  end

  local width, height = core.window:get_size()

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
      doc:on_close()
    end
  end

  -- update window title
  local current_title = get_title_filename(core.active_view)
  if current_title ~= nil and current_title ~= core.window_title then
    system.set_window_title(core.window, core.compose_window_title(current_title))
    core.window_title = current_title
  end

  -- draw
  renderer.begin_frame(core.window)
  core.clip_rect_stack[1] = { 0, 0, width, height }
  renderer.set_clip_rect(table.unpack(core.clip_rect_stack[1]))
  core.root_view:draw()
  renderer.end_frame()
  return true
end


local run_threads = coroutine.wrap(function()
  while true do
    local max_time = 1 / config.fps - 0.004
    local minimal_time_to_wake = math.huge

    local threads = {}
    -- We modify core.threads while iterating, both by removing dead threads,
    -- and by potentially adding more threads while we yielded early,
    -- so we need to extract the threads list and iterate over that instead.
    for k, thread in pairs(core.threads) do
      threads[k] = thread
    end

    for k, thread in pairs(threads) do
      -- Run thread if it wasn't deleted externally and it's time to resume it
      if core.threads[k] and thread.wake < system.get_time() then
        local _, wait = assert(coroutine.resume(thread.cr))
        if coroutine.status(thread.cr) == "dead" then
          core.threads[k] = nil
        else
          wait = wait or (1/30)
          thread.wake = system.get_time() + wait
          minimal_time_to_wake = math.min(minimal_time_to_wake, wait)
        end
      else
        minimal_time_to_wake =  math.min(minimal_time_to_wake, thread.wake - system.get_time())
      end

      -- stop running threads if we're about to hit the end of frame
      if system.get_time() - core.frame_start > max_time then
        coroutine.yield(0, false)
      end
    end

    coroutine.yield(minimal_time_to_wake, true)
  end
end)


function core.run()
  local next_step
  local last_frame_time
  local run_threads_full = 0
  while true do
    core.frame_start = system.get_time()
    local time_to_wake, threads_done = run_threads()
    if threads_done then
      run_threads_full = run_threads_full + 1
    end
    local did_redraw = false
    local did_step = false
    local force_draw = core.redraw and last_frame_time and core.frame_start - last_frame_time > (1 / config.fps)
    if force_draw or not next_step or system.get_time() >= next_step then
      if core.step() then
        did_redraw = true
        last_frame_time = core.frame_start
      end
      next_step = nil
      did_step = true
    end
    if core.restart_request or core.quit_request then break end

    if not did_redraw then
      if system.window_has_focus(core.window) or not did_step or run_threads_full < 2 then
        local now = system.get_time()
        if not next_step then -- compute the time until the next blink
          local t = now - core.blink_start
          local h = config.blink_period / 2
          local dt = math.ceil(t / h) * h - t
          local cursor_time_to_wake = dt + 1 / config.fps
          next_step = now + cursor_time_to_wake
        end
        if system.wait_event(math.min(next_step - now, time_to_wake)) then
          next_step = nil -- if we've recevied an event, perform a step
        end
      else
        system.wait_event()
        next_step = nil -- perform a step when we're not in focus if get we an event
      end
    else -- if we redrew, then make sure we only draw at most FPS/sec
      run_threads_full = 0
      local now = system.get_time()
      local elapsed = now - core.frame_start
      local next_frame = math.max(0, 1 / config.fps - elapsed)
      next_step = next_step or (now + next_frame)
      system.sleep(math.min(next_frame, time_to_wake))
    end
  end
end


function core.blink_reset()
  core.blink_start = system.get_time()
end


function core.request_cursor(value)
  core.cursor_change_req = value
end


function core.on_error(err)
  -- write error to file
  local fp = io.open(USERDIR .. PATHSEP .. "error.txt", "wb")
  fp:write("Error: " .. tostring(err) .. "\n")
  fp:write(debug.traceback("", 4) .. "\n")
  fp:close()
  -- save copy of all unsaved documents
  for _, doc in ipairs(core.docs) do
    if doc:is_dirty() and doc.filename then
      doc:save(doc.filename .. "~")
    end
  end
end


local alerted_deprecations = {}
---Show deprecation notice once per `kind`.
---
---@param kind string
function core.deprecation_log(kind)
  if alerted_deprecations[kind] then return end
  alerted_deprecations[kind] = true
  core.warn("Used deprecated functionality [%s]. Check if your plugins are up to date.", kind)
end


return core
