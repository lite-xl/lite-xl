-- mod-version:4
--
-- Tool System for LiteXL AI
-- Registry and execution of tools for agents
--

local core = require "core"
local common = require "core.common"
local config = require "core.config"

---@class core.tools
local tools = {}

-- Tool registry
local registry = {}


---@class core.tools.definition
---@field name string Tool identifier
---@field description string What the tool does
---@field parameters table JSON Schema for parameters
---@field fn fun(args: table): any, string|nil Function to execute (returns result, error)
---@field requires_approval? boolean Whether user approval is needed


---Register a tool
---@param name string Tool name
---@param definition core.tools.definition
function tools.register(name, definition)
  definition.name = name
  registry[name] = definition
  core.log("AI Tools: Registered tool '%s'", name)
end


---Unregister a tool
---@param name string Tool name
function tools.unregister(name)
  registry[name] = nil
end


---Get a tool definition
---@param name string Tool name
---@return core.tools.definition|nil
function tools.get(name)
  return registry[name]
end


---Get all registered tools
---@return core.tools.definition[]
function tools.get_all()
  local list = {}
  for _, tool in pairs(registry) do
    table.insert(list, tool)
  end
  return list
end


---Get tools in OpenAI function calling format
---@return table[]
function tools.get_openai_format()
  local list = {}
  for name, tool in pairs(registry) do
    table.insert(list, {
      type = "function",
      ["function"] = {
        name = name,
        description = tool.description,
        parameters = tool.parameters or { type = "object", properties = {} },
      }
    })
  end
  return list
end


---Execute a tool
---@param name string Tool name
---@param args table Arguments for the tool
---@return any result
---@return string|nil error
function tools.execute(name, args)
  local tool = registry[name]
  if not tool then
    return nil, "Tool not found: " .. name
  end
  
  local ok, result, err = pcall(tool.fn, args)
  if not ok then
    return nil, "Tool execution error: " .. tostring(result)
  end
  
  return result, err
end


---Check if a tool requires approval
---@param name string Tool name
---@return boolean
function tools.requires_approval(name)
  local tool = registry[name]
  return tool and tool.requires_approval == true
end


-- =============================================================================
-- Built-in Tools
-- =============================================================================


---Read file content
tools.register("read_file", {
  description = "Read the contents of a file",
  parameters = {
    type = "object",
    properties = {
      path = {
        type = "string",
        description = "The path to the file to read (relative to project root or absolute)"
      }
    },
    required = { "path" }
  },
  requires_approval = false,
  fn = function(args)
    local path = args.path
    if not path then
      return nil, "path is required"
    end
    
    -- Try to resolve relative path
    if not common.is_absolute_path(path) and core.project_dir then
      path = core.project_dir .. PATHSEP .. path
    end
    
    local file = io.open(path, "r")
    if not file then
      return nil, "Could not open file: " .. path
    end
    
    local content = file:read("*a")
    file:close()
    
    return content, nil
  end
})


---Write/edit file content
tools.register("write_file", {
  description = "Write content to a file (creates or overwrites)",
  parameters = {
    type = "object",
    properties = {
      path = {
        type = "string",
        description = "The path to the file to write"
      },
      content = {
        type = "string",
        description = "The content to write to the file"
      }
    },
    required = { "path", "content" }
  },
  requires_approval = true,
  fn = function(args)
    local path = args.path
    local content = args.content
    
    if not path then return nil, "path is required" end
    if not content then return nil, "content is required" end
    
    -- Resolve relative path
    if not common.is_absolute_path(path) and core.project_dir then
      path = core.project_dir .. PATHSEP .. path
    end
    
    -- Ensure parent directory exists
    local dir = common.dirname(path)
    if dir then
      common.mkdirp(dir)
    end
    
    local file = io.open(path, "w")
    if not file then
      return nil, "Could not open file for writing: " .. path
    end
    
    file:write(content)
    file:close()
    
    -- Trigger reload if the file is open in the editor
    for _, doc in ipairs(core.docs) do
      if doc.filename == path then
        doc:reload()
        break
      end
    end
    
    return "File written successfully: " .. path, nil
  end
})


---Edit file with specific changes
tools.register("edit_file", {
  description = "Apply a specific edit to a file by replacing old content with new content",
  parameters = {
    type = "object",
    properties = {
      path = {
        type = "string",
        description = "The path to the file to edit"
      },
      old_content = {
        type = "string",
        description = "The exact content to find and replace"
      },
      new_content = {
        type = "string",
        description = "The new content to replace with"
      }
    },
    required = { "path", "old_content", "new_content" }
  },
  requires_approval = true,
  fn = function(args)
    local path = args.path
    local old_content = args.old_content
    local new_content = args.new_content
    
    if not path then return nil, "path is required" end
    if not old_content then return nil, "old_content is required" end
    if new_content == nil then return nil, "new_content is required" end
    
    -- Resolve relative path
    if not common.is_absolute_path(path) and core.project_dir then
      path = core.project_dir .. PATHSEP .. path
    end
    
    -- Read existing content
    local file = io.open(path, "r")
    if not file then
      return nil, "Could not open file: " .. path
    end
    local content = file:read("*a")
    file:close()
    
    -- Find and replace
    local start_pos, end_pos = content:find(old_content, 1, true) -- plain text search
    if not start_pos then
      return nil, "Could not find the specified content in the file"
    end
    
    local new_file_content = content:sub(1, start_pos - 1) .. new_content .. content:sub(end_pos + 1)
    
    -- Write back
    file = io.open(path, "w")
    if not file then
      return nil, "Could not open file for writing: " .. path
    end
    file:write(new_file_content)
    file:close()
    
    -- Trigger reload if the file is open
    for _, doc in ipairs(core.docs) do
      if doc.filename == path then
        doc:reload()
        break
      end
    end
    
    return "File edited successfully: " .. path, nil
  end
})


---Search in project files
tools.register("search_project", {
  description = "Search for text pattern in project files",
  parameters = {
    type = "object",
    properties = {
      pattern = {
        type = "string",
        description = "The text pattern to search for"
      },
      path = {
        type = "string",
        description = "Optional: subdirectory to search in"
      }
    },
    required = { "pattern" }
  },
  requires_approval = false,
  fn = function(args)
    local pattern = args.pattern
    local search_path = args.path
    
    if not pattern then return nil, "pattern is required" end
    
    local project_dir = core.project_dir
    if not project_dir then
      return nil, "No project directory"
    end
    
    if search_path then
      if not common.is_absolute_path(search_path) then
        search_path = project_dir .. PATHSEP .. search_path
      end
    else
      search_path = project_dir
    end
    
    local results = {}
    local max_results = 50
    
    local function search_dir(dir)
      if #results >= max_results then return end
      
      local files = system.list_dir(dir)
      if not files then return end
      
      for _, file in ipairs(files) do
        if #results >= max_results then return end
        
        local path = dir .. PATHSEP .. file
        local info = system.get_file_info(path)
        
        if info then
          if info.type == "dir" then
            -- Skip ignored directories
            local ignored = false
            for _, ignore_pattern in ipairs(config.ignore_files) do
              if file:match(ignore_pattern) then
                ignored = true
                break
              end
            end
            if not ignored then
              search_dir(path)
            end
          elseif info.type == "file" then
            -- Search in file
            local f = io.open(path, "r")
            if f then
              local line_num = 0
              for line in f:lines() do
                line_num = line_num + 1
                if line:find(pattern, 1, true) then
                  local relative_path = path:sub(#project_dir + 2)
                  table.insert(results, {
                    file = relative_path,
                    line = line_num,
                    text = line:sub(1, 200) -- truncate long lines
                  })
                  if #results >= max_results then
                    f:close()
                    return
                  end
                end
              end
              f:close()
            end
          end
        end
      end
    end
    
    search_dir(search_path)
    
    if #results == 0 then
      return "No results found for: " .. pattern, nil
    end
    
    -- Format results
    local output = {}
    for _, r in ipairs(results) do
      table.insert(output, string.format("%s:%d: %s", r.file, r.line, r.text))
    end
    
    return table.concat(output, "\n"), nil
  end
})


---List files in directory
tools.register("list_files", {
  description = "List files and directories in a path",
  parameters = {
    type = "object",
    properties = {
      path = {
        type = "string",
        description = "The directory path to list (relative to project or absolute). Defaults to project root."
      }
    },
    required = {}
  },
  requires_approval = false,
  fn = function(args)
    local path = args.path or ""
    
    if path == "" then
      path = core.project_dir
    elseif not common.is_absolute_path(path) and core.project_dir then
      path = core.project_dir .. PATHSEP .. path
    end
    
    if not path then
      return nil, "No path specified and no project directory"
    end
    
    local files = system.list_dir(path)
    if not files then
      return nil, "Could not list directory: " .. path
    end
    
    local results = {}
    for _, file in ipairs(files) do
      local full_path = path .. PATHSEP .. file
      local info = system.get_file_info(full_path)
      if info then
        local suffix = info.type == "dir" and "/" or ""
        table.insert(results, file .. suffix)
      end
    end
    
    table.sort(results)
    return table.concat(results, "\n"), nil
  end
})


---Run shell command
tools.register("run_command", {
  description = "Execute a shell command and return its output. Use with caution!",
  parameters = {
    type = "object",
    properties = {
      command = {
        type = "string",
        description = "The command to execute"
      },
      cwd = {
        type = "string",
        description = "Optional: working directory for the command"
      }
    },
    required = { "command" }
  },
  requires_approval = true,
  fn = function(args)
    local command = args.command
    local cwd = args.cwd
    
    if not command then return nil, "command is required" end
    
    -- Resolve cwd
    if cwd and not common.is_absolute_path(cwd) and core.project_dir then
      cwd = core.project_dir .. PATHSEP .. cwd
    elseif not cwd then
      cwd = core.project_dir
    end
    
    -- Build command for shell
    local shell_cmd
    if PLATFORM == "Windows" then
      shell_cmd = { "cmd", "/c", command }
    else
      shell_cmd = { "sh", "-c", command }
    end
    
    local proc = process.start(shell_cmd, {
      cwd = cwd,
      stdin = process.REDIRECT_DISCARD,
      stdout = process.REDIRECT_PIPE,
      stderr = process.REDIRECT_PIPE,
    })
    
    if not proc then
      return nil, "Failed to start command"
    end
    
    local stdout = proc.stdout:read("all") or ""
    local stderr = proc.stderr:read("all") or ""
    local exit_code = proc:wait(30) -- 30 second timeout
    
    local output = stdout
    if stderr and #stderr > 0 then
      output = output .. "\n[stderr]\n" .. stderr
    end
    output = output .. "\n[exit code: " .. tostring(exit_code or "timeout") .. "]"
    
    return output, nil
  end
})


return tools
