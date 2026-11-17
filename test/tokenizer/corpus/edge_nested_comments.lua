-- plain line comment
--[[ a long comment
     with ]] on its own -- and a fake --[[ open inside
]]
local s = [==[
  a long string containing ]] and ]=] but not the closer
]==]
local t = [[nested [[ is not really nested in Lua ]]
print("after the long string")
--[==[ unbalanced long comment opened near EOF
local never_seen = 1
