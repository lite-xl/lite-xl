local bit = {}

local LUA_NBITS = 32
local ALLONES = (~(((~0) << (LUA_NBITS - 1)) << 1))

local function trim(x)
	return (x & ALLONES)
end

local function mask(n)
	return (~((ALLONES << 1) << ((n) - 1)))
end

local function check_args(field, width)
	assert(field >= 0, "field cannot be negative")
	assert(width > 0, "width must be positive")
	assert(field + width < LUA_NBITS and field + width >= 0,
	       "trying to access non-existent bits")
end

function bit.extract(n, field, width)
	local w = width or 1
	check_args(field, w)
	local m = trim(n)
	return m >> field & mask(w)
end

function bit.replace(n, v, field, width)
	local w = width or 1
	check_args(field, w)
	local m = trim(n)
	local x = v & mask(width);
	return m & ~(mask(w) << field) | (x << field)
end

return bit
