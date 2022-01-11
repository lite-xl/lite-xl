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
	local w = width or 1
	assert(w > 0, "width must be positive")
	assert(field + w < LUA_NBITS and field + w >= 0, "trying to access non-existent bits")
	local m = trim(n)
	return m >> field & mask(w)
end

function bit.replace(n, v, field, width)
	local w = width or 1
	assert(w > 0, "width must be positive")
	assert(field + w < LUA_NBITS and field + w >= 0, "trying to access non-existent bits")
	local m = trim(n)
	local x = v & mask(width);
	return m & ~(mask(w) << field) | (x << field)
end

return bit
