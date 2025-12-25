-- mod-version:4
--
-- AI Communication Module for LiteXL
-- Provides HTTP client for LLM API calls (OpenAI-compatible)
--

local core = require "core"
local config = require "core.config"
local common = require "core.common"
local Object = require "core.object"

---@class core.ai
local ai = {}

-- Default configuration
config.plugins.ai = common.merge({
  -- API configuration
  api_key = os.getenv("OPENAI_API_KEY") or "",
  api_base = "https://api.openai.com/v1",
  
  -- Model settings
  model = "gpt-4",
  max_tokens = 4096,
  temperature = 0.7,
  
  -- Request settings
  timeout = 60, -- seconds
  
  -- Config specification for UI
  config_spec = {
    name = "AI",
    {
      label = "API Key",
      description = "API key for the LLM provider. Can also be set via OPENAI_API_KEY environment variable.",
      path = "api_key",
      type = "string",
      default = "",
    },
    {
      label = "API Base URL",
      description = "Base URL for the API (OpenAI-compatible).",
      path = "api_base",
      type = "string",
      default = "https://api.openai.com/v1",
    },
    {
      label = "Model",
      description = "Model to use for completions.",
      path = "model",
      type = "string",
      default = "gpt-4",
    },
    {
      label = "Max Tokens",
      description = "Maximum tokens in the response.",
      path = "max_tokens",
      type = "number",
      default = 4096,
      min = 1,
      max = 128000,
    },
    {
      label = "Temperature",
      description = "Sampling temperature (0-2).",
      path = "temperature",
      type = "number",
      default = 0.7,
      min = 0,
      max = 2,
      step = 0.1,
    },
  }
}, config.plugins.ai)


---Escape a string for JSON
---@param s string
---@return string
local function json_escape(s)
  s = s:gsub('\\', '\\\\')
  s = s:gsub('"', '\\"')
  s = s:gsub('\n', '\\n')
  s = s:gsub('\r', '\\r')
  s = s:gsub('\t', '\\t')
  return s
end


---Simple JSON encoder for our use case
---@param obj any
---@return string
local function json_encode(obj)
  local t = type(obj)
  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return obj and "true" or "false"
  elseif t == "number" then
    return tostring(obj)
  elseif t == "string" then
    return '"' .. json_escape(obj) .. '"'
  elseif t == "table" then
    -- Check if array or object
    local is_array = #obj > 0 or next(obj) == nil
    if is_array then
      local parts = {}
      for _, v in ipairs(obj) do
        table.insert(parts, json_encode(v))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local parts = {}
      for k, v in pairs(obj) do
        table.insert(parts, '"' .. json_escape(tostring(k)) .. '":' .. json_encode(v))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return "null"
end


---Simple JSON decoder
---@param str string
---@return any
local function json_decode(str)
  -- Use Lua pattern matching for simple JSON parsing
  -- This is a basic implementation that handles our use cases
  
  local pos = 1
  local function skip_whitespace()
    local _, e = str:find("^%s*", pos)
    if e then pos = e + 1 end
  end
  
  local function parse_value()
    skip_whitespace()
    local c = str:sub(pos, pos)
    
    if c == '"' then
      -- String
      pos = pos + 1
      local start = pos
      local result = ""
      while pos <= #str do
        local char = str:sub(pos, pos)
        if char == '"' then
          pos = pos + 1
          return result
        elseif char == '\\' then
          pos = pos + 1
          local escape = str:sub(pos, pos)
          if escape == 'n' then result = result .. '\n'
          elseif escape == 'r' then result = result .. '\r'
          elseif escape == 't' then result = result .. '\t'
          elseif escape == '"' then result = result .. '"'
          elseif escape == '\\' then result = result .. '\\'
          else result = result .. escape end
          pos = pos + 1
        else
          result = result .. char
          pos = pos + 1
        end
      end
      return result
      
    elseif c == '{' then
      -- Object
      pos = pos + 1
      local obj = {}
      skip_whitespace()
      if str:sub(pos, pos) == '}' then
        pos = pos + 1
        return obj
      end
      while true do
        skip_whitespace()
        local key = parse_value()
        skip_whitespace()
        pos = pos + 1 -- skip ':'
        local value = parse_value()
        obj[key] = value
        skip_whitespace()
        local sep = str:sub(pos, pos)
        pos = pos + 1
        if sep == '}' then break end
      end
      return obj
      
    elseif c == '[' then
      -- Array
      pos = pos + 1
      local arr = {}
      skip_whitespace()
      if str:sub(pos, pos) == ']' then
        pos = pos + 1
        return arr
      end
      while true do
        table.insert(arr, parse_value())
        skip_whitespace()
        local sep = str:sub(pos, pos)
        pos = pos + 1
        if sep == ']' then break end
      end
      return arr
      
    elseif str:sub(pos, pos + 3) == "true" then
      pos = pos + 4
      return true
      
    elseif str:sub(pos, pos + 4) == "false" then
      pos = pos + 5
      return false
      
    elseif str:sub(pos, pos + 3) == "null" then
      pos = pos + 4
      return nil
      
    else
      -- Number
      local _, e, num = str:find("^(-?%d+%.?%d*[eE]?[+-]?%d*)", pos)
      if num then
        pos = e + 1
        return tonumber(num)
      end
    end
    
    return nil
  end
  
  return parse_value()
end

ai.json_encode = json_encode
ai.json_decode = json_decode


---@class ai.message
---@field role string "system" | "user" | "assistant"
---@field content string

---@class ai.chat_options
---@field model? string Model to use
---@field max_tokens? number Maximum tokens
---@field temperature? number Sampling temperature
---@field tools? table[] Tool definitions for function calling
---@field stream? boolean Enable streaming (default false)

---@class ai.response
---@field content string The response text
---@field finish_reason string Why the response ended
---@field tool_calls? table[] Tool calls if any
---@field usage? table Token usage stats


---Make an HTTP request using curl
---@param url string
---@param method string
---@param headers table<string,string>
---@param body string|nil
---@param callback fun(err: string|nil, response: string|nil, status: number|nil)
local function http_request(url, method, headers, body, callback)
  local args = {
    "curl", "-s", "-S",
    "-X", method,
    "-w", "\n%{http_code}",  -- Append HTTP status code
  }
  
  -- Add headers
  for k, v in pairs(headers) do
    table.insert(args, "-H")
    table.insert(args, k .. ": " .. v)
  end
  
  -- Add body
  if body then
    table.insert(args, "-d")
    table.insert(args, body)
  end
  
  table.insert(args, url)
  
  -- Run curl in background thread
  core.add_thread(function()
    local proc = process.start(args, { 
      stdin = process.REDIRECT_DISCARD,
      stdout = process.REDIRECT_PIPE,
      stderr = process.REDIRECT_PIPE,
    })
    
    if not proc then
      callback("Failed to start curl process", nil, nil)
      return
    end
    
    -- Read response
    local output = proc.stdout:read("all") or ""
    local stderr = proc.stderr:read("all") or ""
    local exit_code = proc:wait(config.plugins.ai.timeout)
    
    if exit_code ~= 0 then
      callback("curl failed: " .. stderr, nil, nil)
      return
    end
    
    -- Parse response - last line is status code
    local lines = {}
    for line in output:gmatch("[^\n]+") do
      table.insert(lines, line)
    end
    
    local status = tonumber(lines[#lines]) or 0
    table.remove(lines)
    local response_body = table.concat(lines, "\n")
    
    callback(nil, response_body, status)
  end)
end


---Make an HTTP request with streaming using curl
---@param url string
---@param method string
---@param headers table<string,string>
---@param body string|nil
---@param on_chunk fun(chunk: string)
---@param on_done fun(err: string|nil)
local function http_request_stream(url, method, headers, body, on_chunk, on_done)
  local args = {
    "curl", "-s", "-S", "-N",
    "-X", method,
  }
  
  for k, v in pairs(headers) do
    table.insert(args, "-H")
    table.insert(args, k .. ": " .. v)
  end
  
  if body then
    table.insert(args, "-d")
    table.insert(args, body)
  end
  
  table.insert(args, url)
  
  core.add_thread(function()
    local proc = process.start(args, {
      stdin = process.REDIRECT_DISCARD,
      stdout = process.REDIRECT_PIPE,
      stderr = process.REDIRECT_PIPE,
    })
    
    if not proc then
      on_done("Failed to start curl process")
      return
    end
    
    -- Read chunks as they come
    while proc:running() do
      local chunk = proc.stdout:read(1024)
      if chunk and #chunk > 0 then
        on_chunk(chunk)
      end
      coroutine.yield(0.01)
    end
    
    -- Read any remaining data
    local remaining = proc.stdout:read("all")
    if remaining and #remaining > 0 then
      on_chunk(remaining)
    end
    
    local exit_code = proc:returncode()
    if exit_code ~= 0 then
      local stderr = proc.stderr:read("all") or ""
      on_done("curl failed: " .. stderr)
    else
      on_done(nil)
    end
  end)
end


---Send a chat completion request
---@param messages ai.message[] Array of messages
---@param options? ai.chat_options Options for the request  
---@param callback fun(err: string|nil, response: ai.response|nil)
function ai.chat(messages, options, callback)
  options = options or {}
  
  local cfg = config.plugins.ai
  local api_key = cfg.api_key
  
  if not api_key or api_key == "" then
    callback("API key not configured. Set config.plugins.ai.api_key or OPENAI_API_KEY environment variable.", nil)
    return
  end
  
  local url = cfg.api_base .. "/chat/completions"
  
  local request_body = {
    model = options.model or cfg.model,
    messages = messages,
    max_tokens = options.max_tokens or cfg.max_tokens,
    temperature = options.temperature or cfg.temperature,
  }
  
  if options.tools then
    request_body.tools = options.tools
  end
  
  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. api_key,
  }
  
  http_request(url, "POST", headers, json_encode(request_body), function(err, body, status)
    if err then
      callback(err, nil)
      return
    end
    
    if status >= 400 then
      callback("API error (HTTP " .. status .. "): " .. (body or ""), nil)
      return
    end
    
    local response = json_decode(body)
    if not response then
      callback("Failed to parse API response", nil)
      return
    end
    
    if response.error then
      callback("API error: " .. (response.error.message or json_encode(response.error)), nil)
      return
    end
    
    local choice = response.choices and response.choices[1]
    if not choice then
      callback("No response from API", nil)
      return
    end
    
    local result = {
      content = choice.message and choice.message.content or "",
      finish_reason = choice.finish_reason or "unknown",
      tool_calls = choice.message and choice.message.tool_calls,
      usage = response.usage,
    }
    
    callback(nil, result)
  end)
end


---Send a chat completion request with streaming
---@param messages ai.message[] Array of messages
---@param options? ai.chat_options Options for the request
---@param on_chunk fun(content: string) Called for each content chunk
---@param on_done fun(err: string|nil, response: ai.response|nil) Called when complete
function ai.stream(messages, options, on_chunk, on_done)
  options = options or {}
  
  local cfg = config.plugins.ai
  local api_key = cfg.api_key
  
  if not api_key or api_key == "" then
    on_done("API key not configured.", nil)
    return
  end
  
  local url = cfg.api_base .. "/chat/completions"
  
  local request_body = {
    model = options.model or cfg.model,
    messages = messages,
    max_tokens = options.max_tokens or cfg.max_tokens,
    temperature = options.temperature or cfg.temperature,
    stream = true,
  }
  
  if options.tools then
    request_body.tools = options.tools
  end
  
  local headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. api_key,
  }
  
  local full_content = ""
  local finish_reason = nil
  local tool_calls = nil
  local buffer = ""
  
  http_request_stream(url, "POST", headers, json_encode(request_body),
    function(chunk)
      buffer = buffer .. chunk
      
      -- Process SSE events
      while true do
        local line_end = buffer:find("\n")
        if not line_end then break end
        
        local line = buffer:sub(1, line_end - 1):gsub("\r$", "")
        buffer = buffer:sub(line_end + 1)
        
        if line:sub(1, 6) == "data: " then
          local data = line:sub(7)
          if data == "[DONE]" then
            -- Stream complete
          else
            local event = json_decode(data)
            if event and event.choices and event.choices[1] then
              local delta = event.choices[1].delta
              if delta and delta.content then
                full_content = full_content .. delta.content
                on_chunk(delta.content)
              end
              if delta and delta.tool_calls then
                tool_calls = tool_calls or {}
                for _, tc in ipairs(delta.tool_calls) do
                  local idx = (tc.index or 0) + 1
                  tool_calls[idx] = tool_calls[idx] or { id = "", type = "function", ["function"] = { name = "", arguments = "" } }
                  if tc.id then tool_calls[idx].id = tc.id end
                  if tc["function"] then
                    if tc["function"].name then
                      tool_calls[idx]["function"].name = tool_calls[idx]["function"].name .. tc["function"].name
                    end
                    if tc["function"].arguments then
                      tool_calls[idx]["function"].arguments = tool_calls[idx]["function"].arguments .. tc["function"].arguments
                    end
                  end
                end
              end
              if event.choices[1].finish_reason then
                finish_reason = event.choices[1].finish_reason
              end
            end
          end
        end
      end
    end,
    function(err)
      if err then
        on_done(err, nil)
      else
        on_done(nil, {
          content = full_content,
          finish_reason = finish_reason or "stop",
          tool_calls = tool_calls,
        })
      end
    end
  )
end


---Send a simple completion request (wrapper around chat)
---@param prompt string The prompt
---@param options? ai.chat_options Options
---@param callback fun(err: string|nil, text: string|nil)
function ai.completion(prompt, options, callback)
  local messages = {
    { role = "user", content = prompt }
  }
  ai.chat(messages, options, function(err, response)
    if err then
      callback(err, nil)
    else
      callback(nil, response.content)
    end
  end)
end


return ai
