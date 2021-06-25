---@meta

---
---Functionality that allows you to launch subprocesses and read
---or write to them in a non-blocking fashion.
---@class process
process = {}

---Error triggered when the stdout, stderr or stdin fails while reading
---or writing, its value is platform dependent, so the value declared on this
---interface does not represents the real one.
---@type integer
process.ERROR_PIPE = -1

---Error triggered when a read or write action is blocking,
---its value is platform dependent, so the value declared on this
---interface does not represents the real one.
---@type integer
process.ERROR_WOULDBLOCK = -2

---Error triggered when a process takes more time than that specified
---by the deadline parameter given on process:start(),
---its value is platform dependent, so the value declared on this
---interface does not represents the real one.
---@type integer
process.ERROR_TIMEDOUT = -3

---Error triggered when trying to terminate or kill a non running process,
---its value is platform dependent, so the value declared on this
---interface does not represents the real one.
---@type integer
process.ERROR_INVALID = -4

---Used for the process:close_stream() method to close stdin.
---@type integer
process.STREAM_STDIN = 0

---Used for the process:close_stream() method to close stdout.
---@type integer
process.STREAM_STDOUT = 1

---Used for the process:close_stream() method to close stderr.
---@type integer
process.STREAM_STDERR = 2

---Instruct process:wait() to wait until the process ends.
---@type integer
process.WAIT_INFINITE = -1

---Instruct process:wait() to wait until the deadline given on process:start()
---@type integer
process.WAIT_DEADLINE = -2

---
---Create a new process object
---
---@return process
function process.new() end

---
---Translates an error code into a useful text message
---
---@param code integer
---
---@return string
function process.strerror(code) end

---
---Start a process
---
---@param command_and_params table First index is the command to execute
---and subsequente elements are parameters for the command.
---@param working_directory? string Path where the command will be launched.
---@param deadline? integer Maximum time in milliseconds the
---process is allowed to run on a process:wait(process.WAIT_DEADLINE) call.
---
---@return integer|boolean status Negative integer error code if could
---not start or true on success
function process:start(command_and_params, working_directory, deadline) end

---
---Get the process id.
---
---@return integer id Process id or 0 if not running.
function process:pid() end

---
---Read from stdout, if the process fails with a ERROR_PIPE it is
---automatically destroyed, so checking process status with the
---process:running() method would be advised.
---
---@param len? integer Amount of bytes to read.
---@param tries? integer Retry reading the given amount of times
---if nothing was read.
---
---@return integer|nil bytes Amount of bytes read or nil if nothing was read.
function process:read(len, tries) end

---
---Read from stderr, if the process fails with a ERROR_PIPE it is
---automatically destroyed, so checking process status with the
---process:running() method would be advised.
---
---@param len? integer Amount of bytes to read.
---@param tries? integer Retry reading the given amount of times
---if nothing was read.
---
---@return integer|nil bytes Amount of bytes read or nil if nothing was read.
function process:read_errors(len, tries) end

---
---Write to the stdin, if the process fails with a ERROR_PIPE it is
---automatically destroyed, so checking process status with the
---process:running() method would be advised.
---
---@param data string
---
---@return integer bytes The amount of bytes written or negative integer
---error code: process.ERROR_PIPE, process.ERROR_WOULDBLOCK
function process:write(data) end

---
---Allows you to close a stream pipe that you will not be using.
---
---@param stream integer Could be one of the following:
---process.STREAM_STDIN, process.STREAM_STDOUT, process.STREAM_STDERR
---
---@return integer status Negative error code process.ERROR_INVALID if
---process is not running or stream is already closed.
function process:close_stream(stream) end

---
---Wait the specified amount of time for the process to exit.
---
---@param timeout integer Time to wait in milliseconds, if 0, the function
---will only check if process is running without waiting, also the timeout
---can be set to:
--- * process.WAIT_INFINITE - will wait until the process ends
--- * process.WAIT_DEADLINE - will wait until the deadline declared on start()
---
---@return integer exit_status The process exit status or negative integer
---error code like process.ERROR_TIMEDOUT
function process:wait(timeout) end

---
---Sends SIGTERM to the process
---
---@return boolean|integer status Returns true on success or a
---negative integer error code like process.ERROR_INVALID
function process:terminate() end

---
---Sends SIGKILL to the process
---
---@return boolean|integer status Returns true on success or a
---negative integer error code like process.ERROR_INVALID
function process:kill() end

---
---Check if the process is running
---
---@return boolean
function process:running() end
