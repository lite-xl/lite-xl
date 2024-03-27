local config = require "core.config"

process.stream = {}
process.stream.__index = proc.stream

function process.stream.new(proc, fd)
  return setmetatable({ fd = fd, process = proc, buf = {}, len = 0 }, proc.stream)
end

-- read function can take either "*all", "*line", or a byte count.
function process.stream:read(bytes, options)
  options = options or {}
  local start = system.get_time()
  local target = bytes
  if bytes == "*line" then
    target = 0
    for i,v in ipairs(self.buf) do
      local s = v:find("\n")
      if s then
        target = target + s
        break
      elseif i < #self.buf then
        target = target + #v
      else
        target = math.huge
      end
    end
  elseif bytes == "*all" then
    target = math.huge
  end

  while self.len < target then
    local chunk = self.process:read(self.fd, math.max(target - self.len, 0))
    if not chunk then break end
    if #chunk > 0 then
      table.insert(self.buf, chunk)
      self.len = self.len + #chunk
      if bytes == "*line" then
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
  until
  if #self.buf == 0 then return nil end
  local str = table.concat(self.buf)
  self.len = math.max(self.len - target, 0)
  self.buf = self.len > 0 and { str:sub(target + 1) } or {}
  return str:sub(1, target + (bytes == "*line" and str:byte(target) == "\n" and -1 or 0))
end


function process.stream:write(bytes, options)
  options = options or {}
  local buf = bytes
  while #buf > 0 do
    local len = self.process:write(buf)
    if not len then break end
    buf = buf:sub(len + 1)
    if not coroutine.running() then return len end
    coroutine.yield(options.scan or (1 / config.fps))
  end
  return #buf
end


function process.stream:close()
  return self.process:close_stream(self.fd)
end


local old_start = process.start
function process.start(...)
  local self = old_start(...)
  self.stdout = proc.stream.new(self, process.STREAM_STDOUT),
  self.stderr = proc.stream.new(self, process.STREAM_STDERR),
  self.stdin = proc.stream.new(self, process.STREAM_STDIN)
  return self
end

return process
