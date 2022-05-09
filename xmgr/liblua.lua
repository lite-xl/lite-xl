local lib_path = path.join(os.projectdir(),"3rd","lua")

target("liblua")
    set_kind("shared")
    set_group("lib3rd")
    add_filegroups("src", {rootdir = lib_path})
    add_includedirs(lib_path)
    add_includedirs(lib_path,{public = true})

    add_headerfiles(path.join(lib_path,"*.h"))
    add_files(path.join(lib_path,"*.c|lua.c|luac.c|onelua.c"))

    add_defines("LUA_COMPAT_5_2", "LUA_COMPAT_5_1")
    on_load(function(target)
        if is_plat("linux", "bsd", "cross") then
            target:add("defines","LUA_USE_LINUX")
            target:add("defines","LUA_DL_DLOPEN")
        elseif is_plat("macosx", "iphoneos") then
            target:add("defines","LUA_USE_MACOSX")
            target:add("defines","LUA_DL_DYLD")
        elseif is_plat("windows", "mingw") then
            -- Lua already detects Windows and sets according defines
            if "shared" == target:get("kind")  then
                target:add("defines","LUA_BUILD_AS_DLL", {public = true})
            end
        end
    end)


target("lua")
    -- set_enabled(enabled)
    set_default(false)
    set_kind("binary")
    set_group("lib3rd")
    add_filegroups("src", {rootdir = lib_path})
    add_files(path.join(lib_path,"lua.c"))
    add_deps("liblua")
    on_load(function(target)
        if not is_plat("windows", "mingw") then
            target:add("syslinks","dl")
        end
    end)
   
