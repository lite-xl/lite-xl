add_rules("mode.debug", "mode.release", "asm")

local function chk_3rd_inc(...)
    local mt = table.pack(...)
    local t = {}
    for _,fn in ipairs(mt) do
        table.insert(t,path.join("xmgr",fn))
    end
    includes(table.unpack(t))
end

chk_3rd_inc("prce2.lua","liblua.lua","sdl2.lua","freetype2.lua")
chk_3rd_inc("lite-xl.lua")

