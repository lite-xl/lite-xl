# Resources

This folder contains resources that is used for building or packaging the project.

### Build

- `cross/*.txt`: Meson [cross files][1] for cross-compiling lite-xl on other platforms.

### Packaging

- `icons/icon.{icns,ico,inl,rc,svg}`: lite-xl icon in various formats.
- `linux/org.lite_xl.lite_xl.appdata.xml`: AppStream metadata.
- `linux/org.lite_xl.lite_xl.desktop`: Desktop file for Linux desktops.
- `macos/appdmg.png`: Background image for packaging MacOS DMGs.
- `macos/Info.plist.in`: Template for generating `info.plist` on MacOS. See `macos/macos-retina-display.md` for details.
- `windows/001-lua-unicode.diff`: Patch for allowing Lua to load files with UTF-8 filenames on Windows.

### Development

- `include/lite_xl_plugin_api.h`: Native plugin API header. See the contents of `lite_xl_plugin_api.h` for more details.


[1]: https://mesonbuild.com/Cross-compilation.html
