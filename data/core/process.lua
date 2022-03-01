---@class Process
---@field proc any
local Process = {
  c_start          = process.start,
  REDIRECT_PIPE    = process.REDIRECT_PIPE,
  REDIRECT_DISCARD = process.REDIRECT_DISCARD,
  REDIRECT_STDOUT  = process.REDIRECT_STDOUT,
  STREAM_STDERR    = process.STREAM_STDERR,
  STREAM_STDOUT    = process.STREAM_STDOUT
}
Process.__index = Process

---Starts a new process.
---@param cmd table
---@param options? table
---@return Process
function Process.start(cmd, options)
  local p = (options and Process.c_start(cmd, options)) or Process.c_start(cmd)
  return setmetatable({ proc = p }, Process)
end

---Reads from stream.
---@param stream Process.STREAM_STDERR | Process.STREAM_STDOUT
---@param size? integer
---@return string
function Process:read(stream, size)
  size = size or 2048
  local readed = 0
  local data = {}
  while readed < size and self:running() do
    local d = self.proc:read(stream, size - readed)
    if #d == 0 then break end
    table.insert(data, d)
    readed = readed + #d
  end
  return table.concat(data, "")
end

---Reads from standard output.
---@param size? integer
---@return string
function Process:read_stdout(size)
  return self:read(self.STREAM_STDOUT, size)
end

---Reads from error output.
---@param size? integer
---@return string
function Process:read_stderr(size)
  return self:read(self.STREAM_STDERR, size)
end

---Write to standard input.
---@param data string
function Process:write(data)
  self.proc:write(data)
end

---Check if the process is running.
---@return boolean
function Process:running()
  return self.proc:running()
end

---Get the process exit code waiting $time ms
---@param time integer
---@return integer|nil
function Process:wait(time)
  return (self.proc:wait(time) or nil)
end

---Sends SIGTERM (or Windows equivalent) to the process.
function Process:terminate()
  self.proc:terminate()
end

---Sends SIGKILL (or Windows equivalent) to the progress
function Process:kill()
  self.proc:kill()
end

---Returns the PID of the process.
---Warning: There are no guarantees for this PID to be correct if the process
---terminated early.
---@return integer
function Process:pid()
  return self.proc:pid()
end

---Returns the exit code of the process.
---@return integer
function Process:returncode()
  return self.proc:returncode()
end

---Closes stdin, stdout or stderr stream of the process.
function Process:close_stream()
  self.proc:close_stream()
end

return Process
