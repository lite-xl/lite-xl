# Resources

This folder contains resources that is used for building or packaging the project.

### Build

- `cross/*.txt`: Meson [cross files][1] for cross-compiling lite-xl on other platforms.

### Packaging

- `icons/icon.{icns,ico,inl,rc,svg}`: lite-xl icon in various formats.
- `linux/com.lite_xl.LiteXL.appdata.xml`: AppStream metadata.
- `linux/com.lite_xl.LiteXL.desktop`: Desktop file for Linux desktops.
- `macos/dmg-cover.png`: Background image for packaging macOS DMGs.
- `macos/Info.plist.in`: Template for generating `info.plist` on macOS. See `macos/macos-retina-display.md` for details.
- `macos/lite-xl-dmg.py`: Configuration options for dmgbuild for packaging macOS DMGs.
- `windows/001-lua-unicode.diff`: Patch for allowing Lua to load files with UTF-8 filenames on Windows.

### Development

- `include/lite_xl_plugin_api.h`: Native plugin API header. See the contents of `lite_xl_plugin_api.h` for more details.


[1]: https://mesonbuild.com/Cross-compilation.html
