

local function check_cmakestr_ex(s)
    if "#cmakedefine" == string.sub(s,1,12) then
        local mt = {}
        for w  in s:gmatch("([^%s]+)") do
            table.insert(mt,w)
        end
        
        local ss = nil
        return table.concat({"${define ",mt[2],"}\n"}) 
    else
        local ms,mn = string.gsub(s,"@(.-)@","${%1}")
        if 0 < mn then
            return ms .. "\n"
        end
    end
    return s .. "\n"
end

local function check_cmakestr(s)
    local mt = {}
    local is_cmake = false
    for w  in s:gmatch("([^%s]+)") do
        table.insert(mt,w)
    end
    if "#cmakedefine" == mt[1] then
        local ss = nil
        return table.concat({"${define ",mt[2],"}\n"}) 
    else
        local ms,mn = string.gsub(s,"@(.-)@","${%1}")
        if 0 < mn then
            return ms .. "\n"
        end
    end
    return s .. "\n"
end

local function check_undef(s)
    return string.gsub(s,"^[%s]*#undef (.-)[%s]*[.]*$","${%1}") .. "\n"
end

local function check_undef_ex(s)
    return string.gsub(s,"^[%s]*#undef (.-)[%s]*[.]*$","${define %1}") .. "\n"
end

function src2dst(src,dst,to)
    f = io.open (dst,"w+")
    for s in io.lines(src) do
        local ss =to(s)
        f:write(ss)
    end
    f:close()
end

function ce2x(src,dst)
    src2dst(src,dst,check_cmakestr_ex)
end

function c2x(src,dst)
    src2dst(src,dst,check_cmakestr)
end

function u2x(src,dst)
    src2dst(src,dst,check_undef)
end

function ue2x(src,dst)
    src2dst(src,dst,check_undef_ex)
end

function main(src,dst)
    c2x(src,dst)
end