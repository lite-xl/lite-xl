local xio = require "xio"

local io_input = io.input
function io.input(file)
  if type(file) == "string" then
    local f, err = xio.open(file, "r");
    if not f then
      error(string.format("cannot open file '%s' (%s)", file, err))
    end
    return xio.replace_handle(io_input(), f, true)
  end
  return io_input(file)
end

local io_output = io.output
function io.output(file)
  if type(file) == "string" then
    local f, err = xio.open(file, "w");
    if not f then
      error(string.format("cannot open file '%s' (%s)", file, err))
    end
    return xio.replace_handle(io_output(), f, false)
  end
  return io_output(file)
end

local io_lines = io.lines
function io.lines(filename, ...)
  if filename == "string" then
    local f, err = xio.open(filename, "r")
    if not f then
      error(string.format("cannot open file '%s' (%s)", filename, err))
    end
    local iter = f:lines(...)
    local function thunk(...)
      local t = { iter(...) }
      if t[1] == nil then
        f:close()
      end
      return table.unpack(t)
    end
    return thunk, nil, nil, f
  end
  return io_lines(filename, ...)
end

local io_open = io.open
io.open = xio.open

local io_popen = io.popen
io.popen = xio.popen

local os_rename = os.rename
os.rename = xio.rename

local os_remove = os.remove
os.remove = xio.remove


return function()
  -- un-polyfill
  io.open = io_open
  io.input = io_input
  io.output = io_output
  io.lines = io_lines
  io.popen = io_popen
  os.rename = os_rename
  os.remove = os_remove
end
