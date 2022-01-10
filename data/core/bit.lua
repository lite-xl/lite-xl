local bit = {}

local LUA_NBITS = 32
local ALLONES = (~(((~0) << (LUA_NBITS - 1)) << 1))

local function trim(x)
	return (x & ALLONES)
end

local function mask(n)
	return (~((ALLONES << 1) << ((n) - 1)))
end

function bit.extract(n, field, width)
	local r = trim(field)
	local f = width
	r = (r >> f) & mask(width)
	return r
end

function bit.replace(n, v, field, width)
	local r = trim(v);
	local v = trim(field);
	local f = width
	local m = mask(width);
	r = (r & ~(m << f)) | ((v & m) << f);
	return r
end

return bit