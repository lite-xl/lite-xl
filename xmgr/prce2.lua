includes("check_cfuncs.lua")
includes("check_cincludes.lua")

add_rules("mode.debug", "mode.release")
local is_shared = false 
local cfg_dir = path.join(os.projectdir(),"build","config","prce2")
local lib_path = path.join(os.projectdir(),"3rd","pcre2")
local lib_src = path.join(lib_path,"src")
local cfg_in = path.join(lib_path,"config-cmake.h.in")
local cfg_fn = path.join(cfg_dir,"config.h.in")
local pcre_in = path.join(lib_src,"pcre2.h.in")
local pcre_fn = path.join(cfg_dir,"pcre2.h.in")
local cht_in = path.join(lib_src,"pcre2_chartables.c.dist")
local cht_fn = path.join(cfg_dir,"pcre2_chartables.c")


option("prce2_env")
    before_check(function(option)
        if os.isfile(cfg_fn) and os.isfile(pcre_fn) and os.isfile(cht_fn) then
            return
        end

        if not os.isdir(cfg_dir) then
            os.mkdir(cfg_dir)
        end

        os.cp(cht_in,cht_fn)

        import("config_c2x", {alias = "cfg"})

        cfg.c2x(cfg_in,cfg_fn)
        cfg.c2x(pcre_in,pcre_fn)
    end)
option_end()


local function add_src(fn)
    add_files(path.join(lib_src,fn))
end

local function check_sources()
    set_group("lib3rd")
    add_src("pcre2_auto_possess.c")
    add_src("pcre2_compile.c")
    add_src("pcre2_config.c")
    add_src("pcre2_context.c")
    add_src("pcre2_convert.c")
    add_src("pcre2_dfa_match.c")
    add_src("pcre2_error.c")
    add_src("pcre2_extuni.c")
    add_src("pcre2_find_bracket.c")
    add_src("pcre2_jit_compile.c")
    add_src("pcre2_maketables.c")
    add_src("pcre2_match.c")
    add_src("pcre2_match_data.c")
    add_src("pcre2_newline.c")
    add_src("pcre2_ord2utf.c")
    add_src("pcre2_pattern_info.c")
    add_src("pcre2_script_run.c")
    add_src("pcre2_serialize.c")
    add_src("pcre2_string_utils.c")
    add_src("pcre2_study.c")
    add_src("pcre2_substitute.c")
    add_src("pcre2_substring.c")
    add_src("pcre2_tables.c")
    add_src("pcre2_ucd.c")
    add_src("pcre2_valid_utf.c")
    add_src("pcre2_xclass.c")

    add_headerfiles("$(buildir)/config/**.h")
    set_configdir("$(buildir)/config")
    add_includedirs(lib_src,cfg_dir,{public = true})
    
    if is_plat("windows") then
        add_configfiles(path.join(lib_src,"pcre2_chartables.c.dist"),{copyonly = true,filename="pcre2_chartables.c"})
        add_defines("_CRT_SECURE_NO_DEPRECATE","_CRT_SECURE_NO_WARNINGS")
        add_defines("WIN32","_WINDOWS")
    else
        add_src("pcre2_dftables.c")
    end

    if is_shared then
        if is_mode("debug") then
            set_runtimes("MDd")
        else
            set_runtimes("MD")
        end
        add_defines("pcre2_8_shared_EXPORTS")
    else
        if is_mode("debug") then
            set_runtimes("MTd")
        else
            set_runtimes("MT")
        end
        add_defines("PCRE2_STATIC")
    end

    add_options("pcre2_env")
    set_configdir(cfg_dir)
    add_configfiles(pcre_fn)
    add_configfiles(cfg_fn)
    
    set_configvar("PCRE2_MAJOR", 10)
    set_configvar("PCRE2_MINOR", 40)
    set_configvar("PCRE2_PRERELEASE", "")
    set_configvar("PCRE2_DATE", os.date("%Y-%m-%d"))


    add_defines("HAVE_CONFIG_H")
    -- add_configfiles("$(buildir)/config/config.h.in", {pattern = "@(.-)@"})
   

    -- CHECK_INCLUDE_FILE(dirent.h     HAVE_DIRENT_H)
    configvar_check_cincludes("HAVE_DIRENT_H","dirent.h")

    -- CHECK_INCLUDE_FILE(sys/stat.h   HAVE_SYS_STAT_H)
    configvar_check_cincludes("HAVE_SYS_STAT_H","sys/stat.h")

    -- CHECK_INCLUDE_FILE(sys/types.h  HAVE_SYS_TYPES_H)
    configvar_check_cincludes("HAVE_SYS_TYPES_H","sys/types.h")

    -- CHECK_INCLUDE_FILE(unistd.h     HAVE_UNISTD_H)
    configvar_check_cincludes("HAVE_UNISTD_H","unistd.h")

    -- CHECK_INCLUDE_FILE(windows.h    HAVE_WINDOWS_H)
    configvar_check_cincludes("HAVE_WINDOWS_H","windows.h")

    -- CHECK_SYMBOL_EXISTS(bcopy         "strings.h"  HAVE_BCOPY)
    configvar_check_cfuncs("HAVE_BCOPY","bcopy",{includes = {"strings.h"}})

    -- CHECK_SYMBOL_EXISTS(memfd_create  "sys/mman.h" HAVE_MEMFD_CREATE)
    configvar_check_cfuncs("HAVE_MEMFD_CREATE","memfd_create",{includes = {"sys/mman.h"}})

    -- CHECK_SYMBOL_EXISTS(memmove       "string.h"   HAVE_MEMMOVE)
    configvar_check_cfuncs("HAVE_MEMMOVE","memmove",{includes = {"string.h"}})

    -- CHECK_SYMBOL_EXISTS(secure_getenv "stdlib.h"   HAVE_SECURE_GETENV)
    configvar_check_cfuncs("HAVE_SECURE_GETENV","secure_getenv",{includes = {"stdlib.h"}})

    -- CHECK_SYMBOL_EXISTS(strerror      "string.h"   HAVE_STRERROR)
    configvar_check_cfuncs("HAVE_STRERROR","strerror",{includes = {"string.h"}})

    set_configvar("SUPPORT_PCRE2_8",1)
    set_configvar("SUPPORT_PCRE2_16",1)
    set_configvar("SUPPORT_PCRE2_32",1)

    set_configvar("SUPPORT_JIT",1)
    set_configvar("SUPPORT_PCRE2GREP_JIT",1)
    set_configvar("SUPPORT_PCRE2GREP_CALLOUT",1)
    set_configvar("SUPPORT_PCRE2GREP_CALLOUT_FORK",1)
    set_configvar("SUPPORT_UNICODE",1)

    --Internal link size (2, 3 or 4 allowed). See LINK_SIZE in config.h.in for details.
    set_configvar("PCRE2_LINK_SIZE",2)

    --Default limit on heap memory (kibibytes). See HEAP_LIMIT in config.h.in for details.
    set_configvar("PCRE2_HEAP_LIMIT",20000000)

    --Default limit on internal looping. See MATCH_LIMIT in config.h.in for details.
    set_configvar("PCRE2_MATCH_LIMIT",10000000)

    --Default limit on internal depth of search. See MATCH_LIMIT_DEPTH in config.h.in for details.
    set_configvar("PCRE2_MATCH_LIMIT_DEPTH","MATCH_LIMIT")

    set_configvar("NEWLINE_DEFAULT",2)

    --Default nested parentheses limit. See PARENS_NEST_LIMIT in config.h.in for details.
    set_configvar("PCRE2_PARENS_NEST_LIMIT",250)

    --Buffer starting size parameter for pcre2grep. See PCRE2GREP_BUFSIZE in config.h.in for details.
    set_configvar("PCRE2GREP_BUFSIZE",20480)

    --Buffer maximum size parameter for pcre2grep. See PCRE2GREP_MAX_BUFSIZE in config.h.in for details.
    set_configvar("PCRE2GREP_MAX_BUFSIZE",1048576)
    on_load(function(target)
        if is_plat("windows") then
            target:add("files",cht_fn)
        end
    end)
end

target("pcre2-8")
    set_kind("shared")
    is_shared = true
    check_sources()
    add_defines("PCRE2_CODE_UNIT_WIDTH=8")
target_end()

target("pcre2-8s")
    set_kind("static")
    check_sources()
    set_default(false)
    add_defines("PCRE2_CODE_UNIT_WIDTH=8")
target_end()

target("pcre2-16")
    set_kind("shared")
    is_shared = true
    check_sources()
    set_default(false)
    add_defines("PCRE2_CODE_UNIT_WIDTH=16")
target_end()

target("pcre2-16s")
    set_kind("static")
    check_sources()
    set_default(false)
    add_defines("PCRE2_CODE_UNIT_WIDTH=16")
target_end()

target("pcre2-32")
    set_kind("shared")
    is_shared = true
    check_sources()
    set_default(false)
    add_defines("PCRE2_CODE_UNIT_WIDTH=32")
target_end()

target("pcre2-32s")
    set_kind("static")
    check_sources()
    set_default(false)
    add_defines("PCRE2_CODE_UNIT_WIDTH=32")
target_end()

