-- mod-version:4
--
-- Agent System for LiteXL AI
-- Agent loop for multi-step AI tasks
--

local core = require "core"
local common = require "core.common"
local config = require "core.config"
local Object = require "core.object"
local ai = require "core.ai"
local tools = require "core.tools"


---@class core.agent.state
---@field idle boolean Agent is idle
---@field running boolean Agent is executing
---@field waiting_approval boolean Waiting for user approval
---@field error boolean Agent encountered an error

---@class core.agent : core.object
---@field messages table[] Conversation history
---@field state core.agent.state Current agent state
---@field pending_tool_calls table[] Tool calls awaiting approval
---@field system_prompt string System prompt for the agent
---@field on_message fun(role: string, content: string)|nil
---@field on_tool_call fun(tool_name: string, args: table)|nil
---@field on_tool_result fun(tool_name: string, result: any)|nil
---@field on_approval_needed fun(tool_calls: table[])|nil
---@field on_complete fun()|nil
---@field on_error fun(err: string)|nil
local Agent = Object:extend()


-- Default system prompt for the agent
local DEFAULT_SYSTEM_PROMPT = [[You are an AI assistant integrated into the LiteXL text editor. You help users with coding tasks, file editing, and project management.

You have access to the following tools to help accomplish tasks:
- read_file: Read file contents
- write_file: Write content to a file
- edit_file: Make specific edits to a file
- search_project: Search for text patterns in the project
- list_files: List files and directories
- run_command: Execute shell commands

When the user asks you to perform a task:
1. Analyze what needs to be done
2. Use the appropriate tools to accomplish the task
3. Explain what you did and the results

Be concise but thorough. When editing code, make sure your changes are correct and complete.]]


function Agent:new(options)
  options = options or {}
  
  self.messages = {}
  self.state = {
    idle = true,
    running = false,
    waiting_approval = false,
    error = false,
  }
  self.pending_tool_calls = {}
  self.system_prompt = options.system_prompt or DEFAULT_SYSTEM_PROMPT
  self.max_iterations = options.max_iterations or 10
  self.auto_approve = options.auto_approve or false
  
  -- Callbacks
  self.on_message = options.on_message
  self.on_tool_call = options.on_tool_call
  self.on_tool_result = options.on_tool_result
  self.on_approval_needed = options.on_approval_needed
  self.on_complete = options.on_complete
  self.on_error = options.on_error
  
  -- Add system prompt
  table.insert(self.messages, {
    role = "system",
    content = self.system_prompt,
  })
end


function Agent:__tostring()
  return "Agent"
end


---Get the current state as a string
---@return string
function Agent:get_state_string()
  if self.state.error then return "error"
  elseif self.state.waiting_approval then return "waiting_approval"
  elseif self.state.running then return "running"
  else return "idle" end
end


---Clear conversation history (keep system prompt)
function Agent:clear()
  self.messages = { self.messages[1] }
  self.pending_tool_calls = {}
  self.state = {
    idle = true,
    running = false,
    waiting_approval = false,
    error = false,
  }
end


---Add a user message
---@param content string
function Agent:add_user_message(content)
  table.insert(self.messages, {
    role = "user",
    content = content,
  })
  if self.on_message then
    self.on_message("user", content)
  end
end


---Add an assistant message
---@param content string
function Agent:add_assistant_message(content)
  table.insert(self.messages, {
    role = "assistant",
    content = content,
  })
  if self.on_message then
    self.on_message("assistant", content)
  end
end


---Execute pending tool calls
---@param tool_calls table[]
---@param callback fun()
function Agent:execute_tool_calls(tool_calls, callback)
  local results = {}
  local pending = #tool_calls
  
  for i, tc in ipairs(tool_calls) do
    local tool_name = tc["function"].name
    local args_str = tc["function"].arguments or "{}"
    local args = ai.json_decode(args_str) or {}
    
    if self.on_tool_call then
      self.on_tool_call(tool_name, args)
    end
    
    core.log("AI Agent: Executing tool '%s'", tool_name)
    
    local result, err = tools.execute(tool_name, args)
    
    local result_content
    if err then
      result_content = "Error: " .. err
    elseif result == nil then
      result_content = "Success (no output)"
    elseif type(result) == "string" then
      result_content = result
    else
      result_content = ai.json_encode(result)
    end
    
    if self.on_tool_result then
      self.on_tool_result(tool_name, result_content)
    end
    
    results[i] = {
      tool_call_id = tc.id,
      content = result_content,
    }
    
    pending = pending - 1
    if pending == 0 then
      -- Add tool results to messages
      -- First add the assistant message with tool calls
      table.insert(self.messages, {
        role = "assistant",
        content = nil,
        tool_calls = tool_calls,
      })
      
      -- Then add each tool result
      for _, r in ipairs(results) do
        table.insert(self.messages, {
          role = "tool",
          tool_call_id = r.tool_call_id,
          content = r.content,
        })
      end
      
      callback()
    end
  end
end


---Check if any tool calls require approval
---@param tool_calls table[]
---@return boolean
function Agent:needs_approval(tool_calls)
  if self.auto_approve then
    return false
  end
  
  for _, tc in ipairs(tool_calls) do
    local tool_name = tc["function"].name
    if tools.requires_approval(tool_name) then
      return true
    end
  end
  return false
end


---Run the agent loop
---@param request string User request
function Agent:run(request)
  if self.state.running then
    core.log("AI Agent: Already running")
    return
  end
  
  self.state = {
    idle = false,
    running = true,
    waiting_approval = false,
    error = false,
  }
  
  -- Add user request
  self:add_user_message(request)
  
  -- Start the loop
  self:_loop(0)
end


---Internal agent loop
---@param iteration number
function Agent:_loop(iteration)
  if iteration >= self.max_iterations then
    self.state.running = false
    self.state.idle = true
    if self.on_error then
      self.on_error("Maximum iterations reached")
    end
    return
  end
  
  core.log("AI Agent: Iteration %d", iteration + 1)
  
  -- Call AI with tools
  ai.chat(self.messages, {
    tools = tools.get_openai_format(),
  }, function(err, response)
    if err then
      self.state.running = false
      self.state.error = true
      core.log_quiet("AI Agent error: %s", err)
      if self.on_error then
        self.on_error(err)
      end
      return
    end
    
    -- Handle response
    if response.content and #response.content > 0 then
      self:add_assistant_message(response.content)
    end
    
    -- Check for tool calls
    if response.tool_calls and #response.tool_calls > 0 then
      -- Check if approval is needed
      if self:needs_approval(response.tool_calls) then
        self.state.waiting_approval = true
        self.pending_tool_calls = response.tool_calls
        
        if self.on_approval_needed then
          self.on_approval_needed(response.tool_calls)
        end
        -- Loop will continue when approve() is called
      else
        -- Execute tools and continue
        self:execute_tool_calls(response.tool_calls, function()
          self:_loop(iteration + 1)
        end)
      end
    else
      -- No tool calls, agent is done
      self.state.running = false
      self.state.idle = true
      
      if self.on_complete then
        self.on_complete()
      end
    end
  end)
end


---Approve pending tool calls and continue
function Agent:approve()
  if not self.state.waiting_approval then
    return
  end
  
  self.state.waiting_approval = false
  local tool_calls = self.pending_tool_calls
  self.pending_tool_calls = {}
  
  -- Find current iteration (count tool messages pairs)
  local iteration = 0
  for _, msg in ipairs(self.messages) do
    if msg.role == "tool" then
      iteration = iteration + 1
    end
  end
  
  self:execute_tool_calls(tool_calls, function()
    self:_loop(iteration)
  end)
end


---Reject pending tool calls
function Agent:reject()
  if not self.state.waiting_approval then
    return
  end
  
  self.state.waiting_approval = false
  self.state.running = false
  self.state.idle = true
  self.pending_tool_calls = {}
  
  self:add_assistant_message("Tool execution was rejected by the user.")
  
  if self.on_complete then
    self.on_complete()
  end
end


---Abort the agent
function Agent:abort()
  self.state = {
    idle = true,
    running = false,
    waiting_approval = false,
    error = false,
  }
  self.pending_tool_calls = {}
  core.log("AI Agent: Aborted")
end


-- =============================================================================
-- Module exports
-- =============================================================================

local agent = {
  Agent = Agent,
}


---Create a new agent
---@param options? table
---@return core.agent
function agent.new(options)
  return Agent(options)
end


return agent
