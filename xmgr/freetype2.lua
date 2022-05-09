includes("check_cincludes.lua")

local lib_path = path.join(os.projectdir(),"3rd","FreeType2")
local lib_inc = path.join(lib_path,"include")
local lib_src = path.join(lib_path,"src")
local cfg_dir = path.join("$(buildir)","config","libfreetype")
local cfg_in = path.join(lib_path,"ftconfig_unix.in")
local cfg_fn = path.join(cfg_dir,"ftconfig_linux.h.in")

local function chkfn(s)
    return path.join(lib_src,s) 
end

local function unpack_files(ss)
    local  result = {}
    if not ss then
        return result
    end

    local pattern = "%s*(.-)[\n*]"

    string.gsub(ss,pattern,function(s) 
        result[#result + 1] = chkfn(s) 
    end)

    return table.unpack(result) 
end

local src_files = [[
    autofit/autofit.c
    base/ftbase.c
    base/ftbbox.c
    base/ftbdf.c
    base/ftbitmap.c
    base/ftcid.c
    base/ftfstype.c
    base/ftgasp.c
    base/ftglyph.c
    base/ftgxval.c
    base/ftinit.c
    base/ftmm.c
    base/ftotval.c
    base/ftpatent.c
    base/ftpfr.c
    base/ftstroke.c
    base/ftsynth.c
    base/fttype1.c
    base/ftwinfnt.c
    bdf/bdf.c
    bzip2/ftbzip2.c
    cache/ftcache.c
    cff/cff.c
    cid/type1cid.c
    gzip/ftgzip.c
    lzw/ftlzw.c
    pcf/pcf.c
    pfr/pfr.c
    psaux/psaux.c
    pshinter/pshinter.c
    psnames/psnames.c
    raster/raster.c
    sdf/sdf.c
    sfnt/sfnt.c
    smooth/smooth.c
    svg/svg.c
    truetype/truetype.c
    type1/type1.c
    type42/type42.c
    winfonts/winfnt.c
]]

option("with_freetype_env")
    before_check(function(option)
        if os.isfile(cfg_fn) then
            return
        end

        if not os.isdir(cfg_dir) then
            os.mkdir(cfg_dir)
        end

        import("config_c2x", {alias = "cfg"})

        cfg.u2x(cfg_in,cfg_fn)
    end)
option_end()

option("with_unistd_h")
    on_check(function(op)
        import("lib.detect.check_cxsnippets")
        local ok = check_cxsnippets({'printf("%d", 0); return 0;'}, {includes = {"unistd.h"}, tryrun=true , output = true})
        op:set_value(ok)
    end)
option_end()


option("with_fcntl_h")
    on_check(function(op)
        import("lib.detect.check_cxsnippets")
        local ok = check_cxsnippets({'printf("%d", 0); return 0;'}, {includes = {"fcntl.h"}, tryrun=true , output = true})
        op:set_value(ok)
    end)
option_end()

option("with_stdint_h")
    on_check(function(op)
        import("lib.detect.check_cxsnippets")
        local ok = check_cxsnippets({'printf("%d", 0); return 0;'}, {includes = {"stdint.h"}, tryrun=true , output = true})
        op:set_value(ok)
    end)
option_end()


target("freetype2")
    set_kind("shared")
    set_group("lib3rd")
    add_options("with_freetype_env")
    add_filegroups("src", {rootdir = lib_src})
    add_includedirs(lib_path,lib_src)
    add_includedirs(lib_inc,{public = true})
    add_headerfiles(chkfn("**.h"))

    add_files(unpack_files(src_files))
    add_defines("FT2_BUILD_LIBRARY")

    if not is_plat("windows") then
        add_configfiles(cfg_fn)
        add_options("with_unistd_h","with_fcntl_h","with_stdint_h")
    else
        add_files(path.join(lib_path,"src/base/ftver.rc"))
    end

    on_load(function(target)
        if is_plat("windows","wince") then
            target:add("defines","WIN32","_WINDOWS","OS_WIN32",{public = true})
            target:add("defines","PRIVATE","_ENABLE_EXTENDED_ALIGNED_STORAGE","_CRT_SECURE_NO_WARNINGS")
            target:add("files",path.join(lib_path,"builds/windows/ftsystem.c"))
            if is_plat("wince") then
                target:add("files",path.join(lib_path,"builds/wince/ftdebug.c"))
            else
                target:add("files",path.join(lib_path,"builds/windows/ftdebug.c"))
            end

            if "shared" == target:get("kind") then
                target:add("defines","DLL_EXPORT")
            end
        else
            if is_plat("unix","bsd") then
                target:add("files",path.join(lib_path,"builds/unix/ftsystem.c"))
            else
                target:add("files",path.join(lib_path,"src/base/ftsystem.c"))
            end

            if has_config("with_unistd_h") then
                target:set("configvar","HAVE_UNISTD_H",1)
            end

            if has_config("with_fcntl_h") then
                target:set("configvar","HAVE_FCNTL_H",1)
            end

            if has_config("with_stdint_h") then
                target:set("configvar","HAVE_STDINT_H",1)
            end

        end
    end)
