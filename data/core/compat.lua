local has_jit_module = pcall(require, "jit")
if has_jit_module then
  -- when using luajit the function table.pack/unpack are not available
  function table.pack(...)
    return {n=select('#',...), ...}
  end

  table.unpack = unpack
end

