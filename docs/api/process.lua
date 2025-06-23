---@meta

---
---Functionality that allows you to launch subprocesses and read
---or write to them in a non-blocking fashion.
---@class process
process = {}

---@alias process.ioresult
---| "ok"    # The operation suceeded.
---| "error" # An error occured when reading / writing to the stream.
---| "wait"  # No data is available for reading / writing.
---| "eof"   # End of stream reached.

---@alias process.readstreamtype
---| "stdout" # Standard output.
---| "stderr" # Standard error.

---@alias process.redirecttype
---| "parent"  # The stream is redirected to the parent process. This is the default.
---| "pipe"    # The stream is available for reading / writing with process:read() or process:write().
---| "discard" # The stream is discarded.
---| "stdout"  # The stream is redirected into standard output (only applicable to `stderr`).

---
--- Options that can be passed to process.start().
--- 
---@class process.options
---@field cwd? string The working directory of the child process.
---@field detached? boolean If true, the child process is detached, and the standard IO and exit code will not be available to the parent process.
---@field env? { [string]: string } A table containing environment variables to add to the child process. This table will override parent process' values.
---@field stdin? process.redirecttype
---@field stdout? process.redirecttype
---@field stderr? process.redirecttype

---
---Starts a child process.
---
---On Windows, the function can accept a string instead of a table,
---and the string will be treated as the commandline to run.
---This bypasses any escaping done internally by the function
---and can result in nasty vulnerabilities like BatBadBut.
---Do not use this unless you know what you are doing.
---
---@param command_and_params string[]|string
---@param options process.options
---
---@return process
function process.start(command_and_params, options) end

---
---Get the process id.
---
---@return integer|nil
function process:pid() end

---
---Get the exit code of the process.
---
---@return number|nil exitcode
function process:returncode() end

---
---Check if the process is running.
---
---@return boolean
function process:running() end

---
---Reads from the standard output or error of the child process.
---
---@param stream process.readstreamtype The stream to read from.
---@param len? integer Amount of bytes to read, defaults to 4096.
---
---@return string content
---@return process.ioresult result
---@return string|nil errmsg
function process:read(stream, len) end

---
---Reads from the standard output of the child process.
---
---@param len? integer Amount of bytes to read, defaults to 4096.
---
---@return string content
---@return process.ioresult result
---@return string|nil errmsg
function process:read_stdout(len) end

---
---Reads from the standard output of the child process.
---
---@param len? integer Amount of bytes to read, defaults to 2048.
---
---@return string content
---@return process.ioresult result
---@return string|nil errmsg
function process:read_stderr(len) end

---
---Writes to the standard input of the child process.
---
---@param data string
---
---@return integer bytes
---@return process.ioresult result
---@return string|nil errmsg
function process:write(data) end

---
---Wait the specified amount of time for the child process to exit.
---
---@param timeout? integer Time to wait in milliseconds. Defaults to 0 (no wait).
---@return integer|nil exitcode
function process:wait(timeout) end

---
---Terminates the process gracefully.
---
---On Windows, this function tries to send WM_CLOSE to the process windows,
---and falls back to sending Ctrl+Break to the process console.
---If this fails, the function terminates the process with TerminateProcess().
---On Linux, this function sends SIGTERM to the process.
---
function process:terminate() end

---
---Terminates the process forcefully.
---
---On Windows, this function terminates the process with TerminateProcess().
---On Linux, this function sends SIGKILL to the process.
---
function process:kill() end


return process
