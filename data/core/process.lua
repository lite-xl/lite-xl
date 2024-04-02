local config = require "core.config"


---An abstraction over the standard input and outputs of a process
---that allows you to read and write data easily.
---@class process.stream
---@field private fd process.streamtype
---@field private process process
---@field private buf string[]
---@field private len number
process.stream = {}
process.stream.__index = process.stream

---Creates a stream from a process.
---@param proc process The process to wrap.
---@param fd process.streamtype The standard stream of the process to wrap.
function process.stream.new(proc, fd)
  return setmetatable({ fd = fd, process = proc, buf = {}, len = 0 }, process.stream)
end

---@alias process.stream.readtype
---| `"line"` # Reads a single line
---| `"all"`  # Reads the entire stream
---| `"L"`    # Reads a single line, keeping the trailing newline character.

---Options that can be passed to stream.read().
---@class process.stream.readoption
---@field public timeout number The number of seconds to wait before the function throws an error. Reads do not time out by default.
---@field public scan number The number of seconds to yield in a coroutine. Defaults to `1/config.fps`.

---Reads data from the stream.
---
---When called inside a coroutine such as `core.add_thread()`,
---the function yields to the main thread occassionally to avoid blocking the editor. <br>
---If the function is not called inside the coroutine, the function returns immediately
---without waiting for more data.
---@param bytes process.stream.readtype|integer The format or number of bytes to read.
---@param options? process.stream.readoption Options for reading from the stream.
---@return string|nil data The string read from the stream, or nil if no data could be read.
function process.stream:read(bytes, options)
  if type(bytes) == 'string' then bytes = bytes:gsub("^%*", "") end
  options = options or {}
  local start = system.get_time()
  local target = 0
  if bytes == "line" or bytes == "l" or bytes == "L" then
    if #self.buf > 0 then
      for i,v in ipairs(self.buf) do
        local s = v:find("\n")
        if s then
          target = target + s
          break
        elseif i < #self.buf then
          target = target + #v
        else
          target = 1024*1024*1024*1024
        end
      end
    else
      target = 1024*1024*1024*1024
    end
  elseif bytes == "all" or bytes == "a" then
    target = 1024*1024*1024*1024
  elseif type(bytes) == "number" then
    target = bytes
  else
    error("'" .. bytes .. "' is an unsupported read option for this stream")
  end

  while self.len < target do
    local chunk = self.process.process:read(self.fd, math.max(target - self.len, 0))
    if not chunk then break end
    if #chunk > 0 then
      table.insert(self.buf, chunk)
      self.len = self.len + #chunk
      if bytes == "line" or bytes == "l" or bytes == "L" then
        local s = chunk:find("\n")
        if s then target = self.len - #chunk + s end
      end
    elseif coroutine.running() then
      if options.timeout and system.get_time() - start > options.timeout then
        error("timeout expired")
      end
      coroutine.yield(options.scan or (1 / config.fps))
    else
      break
    end
  end
  if #self.buf == 0 then return nil end
  local str = table.concat(self.buf)
  self.len = math.max(self.len - target, 0)
  self.buf = self.len > 0 and { str:sub(target + 1) } or {}
  return str:sub(1, target + ((bytes == "line" or bytes == "l") and str:byte(target) == 10 and -1 or 0))
end


---Options that can be passed into stream.write().
---@class process.stream.writeoption
---@field public scan number The number of seconds to yield in a coroutine. Defaults to `1/config.fps`.

---Writes data into the stream.
---
---When called inside a coroutine such as `core.add_thread()`,
---the function yields to the main thread occassionally to avoid blocking the editor. <br>
---If the function is not called inside the coroutine,
---the function writes as much data as possible before returning.
---@param bytes string The bytes to write into the stream.
---@param options? process.stream.writeoption Options for writing to the stream.
---@return integer num_bytes The number of bytes written to the stream.
function process.stream:write(bytes, options)
  options = options or {}
  local buf = bytes
  while #buf > 0 do
    local len = self.process.process:write(buf)
    if not len then break end
    if not coroutine.running() then return len end
    buf = buf:sub(len + 1)
    coroutine.yield(options.scan or (1 / config.fps))
  end
  return #bytes - #buf
end


---Closes the stream and its underlying resources.
function process.stream:close()
  return self.process.process:close_stream(self.fd)
end


---Waits for the process to exit.
---When called inside a coroutine such as `core.add_thread()`,
---the function yields to the main thread occassionally to avoid blocking the editor. <br>
---Otherwise, the function blocks the editor until the process exited or the timeout has expired.
---@param timeout? number The amount of seconds to wait. If omitted, the function will wait indefinitely.
---@param scan? number The amount of seconds to yield while scanning. If omittted, the scan rate will be the FPS.
---@return integer|nil exit_code The exit code for this process, or nil if the wait timed out.
function process:wait(timeout, scan)
  if not coroutine.running() then return self.process:wait(timeout) end
  local start = system.get_time()
  while self.process:running() and (system.get_time() - start > (timeout or math.huge)) do
    coroutine.yield(scan or (1 / config.fps))
  end
  return self.process:returncode()
end


function process:__index(k)
  if process[k] then return process[k] end
  if type(self.process[k]) == 'function' then return function(newself, ...) return self.process[k](self.process, ...) end end
  return self.process[k]
end


local old_start = process.start
function process.start(...)
  local self = setmetatable({ process = old_start(...) }, process)
  self.stdout = process.stream.new(self, process.STREAM_STDOUT)
  self.stderr = process.stream.new(self, process.STREAM_STDERR)
  self.stdin  = process.stream.new(self, process.STREAM_STDIN)
  return self
end

return process
