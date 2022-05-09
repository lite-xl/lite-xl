
-- local lib_path = path.join(os.projectdir(),"3rd","sdl2")
-- local lib_inc = path.join(lib_path,"include")
-- local lib_src = path.join(lib_path,"src")
-- local sdl_inc = path.join(lib_inc,"SDL2")

package("sdl2")
    add_deps("cmake")
    set_sourcedir(path.join(os.projectdir(),"3rd","sdl2"))
    add_includedirs("include","include/SDL2")
    on_install(function (package)
        local configs = {}
        table.insert(configs, "-DCMAKE_BUILD_TYPE=" .. (package:debug() and "Debug" or "Release"))
        table.insert(configs, "-DBUILD_SHARED_LIBS=" .. (package:config("shared") and "ON" or "OFF"))
        import("package.tools.cmake").install(package, configs)
    end)

package_end()

add_requires("sdl2", {debug = true})