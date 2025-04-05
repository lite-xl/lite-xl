local Object = require "core.object"

local Project = Object:extend()

local core = require "core"
local common = require "core.common"
local config = require "core.config"

-- inspect config.ignore_files patterns and prepare ready to use entries.
local function compile_ignore_files()
  local ipatterns = config.ignore_files
  local compiled = {}
  -- config.ignore_files could be a simple string...
  if type(ipatterns) ~= "table" then ipatterns = {ipatterns} end
  for i, pattern in ipairs(ipatterns) do
    -- we ignore malformed pattern that raise an error
    if pcall(string.match, "a", pattern) then
      table.insert(compiled, {
        use_path = pattern:match("/[^/$]"), -- contains a slash but not at the end
        -- An '/' or '/$' at the end means we want to match a directory.
        match_dir = pattern:match(".+/%$?$"), -- to be used as a boolen value
        pattern = pattern -- get the actual pattern
      })
    end
  end
  return compiled
end


function Project:new(path)
  self.path = path
  self.name = common.basename(path)
  self.compiled = compile_ignore_files()
  return self
end


-- The function below works like system.absolute_path except it
-- doesn't fail if the file does not exist. We consider that the
-- current dir is core.project_dir so relative filename are considered
-- to be in core.project_dir.
-- Please note that .. or . in the filename are not taken into account.
-- This function should get only filenames normalized using
-- common.normalize_path function.
function Project:absolute_path(filename)
  if common.is_absolute_path(filename) then
    return common.normalize_path(filename)
  elseif not self or not self.path then
    local cwd = system.absolute_path(".")
    return cwd .. PATHSEP .. common.normalize_path(filename)
  else
    return self.path .. PATHSEP .. filename
  end
end


function Project:normalize_path(filename)
  filename = common.normalize_path(filename)
  if common.path_belongs_to(filename, self.path) then
    filename = common.relative_path(self.path, filename)
  end
  return filename
end



local function fileinfo_pass_filter(info, ignore_compiled)
  if info.size >= config.file_size_limit * 1e6 then return false end
  local basename = common.basename(info.filename)
  -- replace '\' with '/' for Windows where PATHSEP = '\'
  local fullname = "/" .. info.filename:gsub("\\", "/")
  for _, compiled in ipairs(ignore_compiled) do
    local test = compiled.use_path and fullname or basename
    if compiled.match_dir then
      if info.type == "dir" and string.match(test .. "/", compiled.pattern) then
        return false
      end
    else
      if string.match(test, compiled.pattern) then
        return false
      end
    end
  end
  return true
end



function Project:is_ignored(info, path)
  -- info can be not nil but info.type may be nil if is neither a file neither
  -- a directory, for example for /dev/* entries on linux.
  if info and info.type then
    if path then info.filename = path end
    return not fileinfo_pass_filter(info, self.compiled)
  end
  return false
end

-- compute a file's info entry completed with "filename" to be used
-- in project scan or falsy if it shouldn't appear in the list.
function Project:get_file_info(path)
  local info = system.get_file_info(path)
  if self:is_ignored(info, path) then return nil end
  return info
end

local function get_dir_content(project, path, entries)
  local all = system.list_dir(path) or {}
  for _, file in ipairs(all) do
    local file = path .. PATHSEP .. file
    local info = project:get_file_info(file)
    if info then
      info.filename = file
      table.insert(entries, info)
    end
  end
end

local function find_files_rec(project, path)
  local entries = {}
  get_dir_content(project, path, entries)

  for _, info in ipairs(entries) do
    if info.type == "file" then
      coroutine.yield(project, info)
    elseif not common.match_pattern(common.basename(info.filename), config.ignore_files) and info.type then
      get_dir_content(project, info.filename, entries)
    end
  end
end


function Project:files()
  return coroutine.wrap(function()
    find_files_rec(self, self.path)
  end)
end



return Project
