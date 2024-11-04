#!/usr/bin/env lua

local aio = io.open("src/all-in-one.c", "wb")
aio:write("const char* packaged_files[] = {\n") 
for i, file in ipairs({ ... }) do 
  if i > 1 then aio:write(",\n") end 
  local contents = io.open(file, "rb"):read("*all") 
  aio:write("\"/", file:gsub("data/",""), "\",\"", contents:gsub(".",function(c) return string.format("\\x%02X",string.byte(c)) end), "\", (const char*)", #contents, "LL") 
end 
aio:write("\n, 0, 0, 0\n};");
