local config = require "core.config"

process.stream = {}
process.stream.__index = process.stream

--- @param proc process The `process` which this stream references.
--- @param fd integer The constant from `process` that represents `stdin`, `stdout` or `stderr`.
function process.stream.new(proc, fd)
  return setmetatable({ fd = fd, process = proc, buf = {}, len = 0 }, process.stream)
end

--- read is designed to be run in a coroutine; if not in one, it will perform a non-blocking read.
--- @param bytes string|number Can be "line", "l", or "L" to read a line, "all", "a" to read the whole file, or a number to read the specified amount of bytes.
--- @param options table? A table specifying `timeout`: how many seconds to wait before `error`ing, and `scan`: the amount of time to yield for while waiting.
---
--- @return string The result of reading from this process.
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


--- write is designed to be run in a coroutine, if not in one, it will perform a non-blocking write.
--- @param bytes string The bytes to write into this process's stream.
--- @param options table? A table specifying `scan`, which is the amount of time to yield for while waiting.
---
--- @return integer The amount of bytes written to this stream.
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


--- closes the underlying stream
function process.stream:close()
  return self.process.process:close_stream(self.fd)
end


--- waits until the process exits. designed to be called in a coroutine, otherwise will block the editor.
--- @param timeout number The amount of seconds to wait. If omitted, will wait indefinitely.
---
--- @return integer The system exit code for this process.
function process:wait(timeout)
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
