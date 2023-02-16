function loadfile(filename, mode, ...)
  -- this is intentionally a vararg because it is impossible to distinguish
  -- between nil or no value in pure lua. Only varargs can do that.
  local chunk, chunk_name, env
  local env_available = select("#", ...) > 0
  if env_available then
    env = select(1, ...)
  end

  if filename then
    local f, err = io.open(filename, "rb")
    if not f then error(string.format("cannot open %s: %s", filename, err)) end

    chunk_name = "@" .. filename
    chunk = f:read("*a")
    f:close()
  else
    chunk_name = "=stdin"
    chunk = io.read("*a")
  end

  -- you cannot pass nil to load. It will literally set _ENV to nil.
  if env_available then
    return load(chunk, chunk_name, mode, env)
  else
    return load(chunk, chunk_name, mode)
  end
end

function dofile(filename)
  local fn, err = loadfile(filename, "bt")
  if not fn then error(err) end

  -- this is not lua_dofile, it does not run in protected mode!
  return fn()
end
