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
local Project

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


function core.add_project(project)
  project = type(project) == "string" and Project(common.normalize_volume(project)) or project
  table.insert(core.projects, project)
  core.redraw = true
  return project
end


function core.remove_project(project, force)
  for i = (force and 1 or 2), #core.projects do
    if project == core.projects[i] or project == core.projects[i].path then
      local project = core.projects[i]
      table.remove(core.projects, i)
      return project
    end
  end
  return false
end


function core.set_project(project)
  while #core.projects > 0 do core.remove_project(core.projects[#core.projects], true) end
  return core.add_project(project)
end


function core.open_project(project)
  local project = core.set_project(project)
  core.root_view:close_all_docviews()
  reload_customizations()
  update_recents_project("add", project.path)
end


local function strip_trailing_slash(filename)
  if filename:match("[^:]["..PATHSEP.."]$") then
    return filename:sub(1, -2)
  end
  return filename
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
    local module_filename = core.project_absolute_path(".lite_project.lua")
    doc_save(self, filename, abs_filename)
    if self.abs_filename == user_filename or self.abs_filename == module_filename then
      reload_customizations()
      core.configure_borderless_window()
    end
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
  Project = require "core.project"
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
  if not RESTARTED then
    for i = 2, #ARGS do
      local arg_filename = strip_trailing_slash(ARGS[i])
      local info = system.get_file_info(arg_filename) or {}
      if info.type == "dir" then
        project_dir = arg_filename
        project_dir_explicit = true
      else
        -- on macOS we can get an argument like "-psn_0_52353" that we just ignore.
        if not ARGS[i]:match("^-psn") then
          local file_abs = common.is_absolute_path(arg_filename) and arg_filename or (system.absolute_path(".") .. PATHSEP .. common.normalize_path(arg_filename))
          if file_abs then
            table.insert(files, file_abs)
            project_dir = file_abs:match("^(.+)[/\\].+$")
          end
        end
      end
    end
  end

  core.frame_start = 0
  core.clip_rect_stack = {{ 0,0,0,0 }}
  core.docs = {}
  core.projects = {}
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
  -- We prevent set_project below to effectively add and scan the directory because the
  -- project module and its ignore files is not yet loaded.
  if project_dir_abs and pcall(core.set_project, project_dir_abs) then
    got_project_error = not core.load_project_module()
    if project_dir_explicit then
      update_recents_project("add", project_dir_abs)
    end
  else
    if not project_dir_explicit then
      update_recents_project("remove", project_dir)
    end
    project_dir_abs = system.absolute_path(".")
    core.set_project(project_dir_abs)
    got_project_error = not core.load_project_module()
  end

  -- Load core and user plugins giving preference to user ones with same name.
  local plugins_success, plugins_refuse_list = core.load_plugins()

  do
    local pdir, pname = project_dir_abs:match("(.*)[/\\\\](.*)")
    core.log("Opening project %q from directory %s", pname, pdir)
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


function core.exit(quit_fn, force)
  if force then
    core.delete_temp_files()
    while #core.projects > 0 do core.remove_project(core.projects[#core.projects], true) end
    save_session()
    quit_fn()
  else
    core.confirm_close_docs(core.docs, core.exit, quit_fn, true)
  end
end


function core.quit(force)
  core.exit(function() core.quit_request = true end, force)
end


function core.restart()
  core.exit(function()
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
  local filename = core.root_project():absolute_path(".lite_project.lua")
  
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
    system.text_input(core.window, view:supports_text_input())
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

function core.root_project() return core.projects[1] end
function core.project_for_path(path)
  for i, project in ipairs(core.projects) do
    if project.path:find(path, 1, true) then return project end
  end
  return nil
end
-- Legacy interface; do not use. Use a specific project instead. When in doubt, use root_project.
function core.normalize_to_project_dir(path) core.deprecation_log("core.normalize_to_project_dir") return core.root_project():normalize_path(path) end
function core.project_absolute_path(path) core.deprecation_log("core.project_absolute_path") return core.root_project() and core.root_project():absolute_path(path) or system.absolute_path(path) end

function core.open_doc(filename)
  local new_file = true
  local abs_filename
  if filename then
    -- normalize filename and set absolute filename then
    -- try to find existing doc for filename
    filename = core.root_project():normalize_path(filename)
    abs_filename = core.root_project():absolute_path(filename)
    new_file = not system.get_file_info(abs_filename)
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
