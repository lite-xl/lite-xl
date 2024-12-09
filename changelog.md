# Changes Log

## [2.1.7] - 2024-12-05

This release fixes a bug related to scaling on macOS,
the comment line / block functionality and an issue with overscrolling
when the editor is too small.
The TreeView now allows creating directories when a trailing slash is added,
and the open file prompt now allows using both '/' and '\' as path separators.

### Features

* Allow `/` for path suggestions in Windows
  ([#1875](https://github.com/lite-xl/lite-xl/pull/1875),
   [#1976](https://github.com/lite-xl/lite-xl/pull/1976))

* Check item type before creating input text in treeview
  ([#1904](https://github.com/lite-xl/lite-xl/pull/1904))

### Fixes

* Return state when tokenizing plaintext syntaxes

* Scale font pixel size in `RENDERER` mode
  ([#1969](https://github.com/lite-xl/lite-xl/pull/1969))

* Prevent overscroll when DocView size is less than lh * 2
  ([#1971](https://github.com/lite-xl/lite-xl/pull/1971))

* Fix process:read_stdout() and process:read_stderr() not checking for process completion
  ([#1973](https://github.com/lite-xl/lite-xl/pull/1973))

* Call poll_process when calling process:returncode()
  ([#1981](https://github.com/lite-xl/lite-xl/pull/1981))

### Other Changes

* Add winget releaser workflow

## [2.1.6] - 2024-11-29

This release introduces a new icon for macOS, improves the performance of the renderer,
adds syntax highlighting support for CUDA as well as QOL fixes and improvements.

### Features

* Add CUDA syntax highlighting support
  ([#1848](https://github.com/lite-xl/lite-xl/pull/1848))

* Add macOS-specific application icon
  ([#1844](https://github.com/lite-xl/lite-xl/pull/1844))

* Add keyboard shortcut to tooltips in ToolbarView
  ([#1880](https://github.com/lite-xl/lite-xl/pull/1880))

* Improve projectsearch (status on the top, horizontal scrolling, elipsis)
  ([#1876](https://github.com/lite-xl/lite-xl/pull/1876))

### Fixes

* Correctly free SDL_Texture and SDL_Renderer
  ([#1849](https://github.com/lite-xl/lite-xl/pull/1850))

* Fixed minor typo from merge of #1854 for Windows builds

* Fix multi-type usage in delimited patterns
  ([#1740](https://github.com/lite-xl/lite-xl/pull/1740))

* Fix appimage cd error and use static appimage runtime
  ([#1924](https://github.com/lite-xl/lite-xl/pull/1924))

### Other Changes

* Rewrite glyph cache
  ([#1845](https://github.com/lite-xl/lite-xl/pull/1845))

* Use lite-xl-build-box-manylinux
  ([#1877](https://github.com/lite-xl/lite-xl/pull/1877))

* Remove unused calls to system.absolute_path()
  ([#1895](https://github.com/lite-xl/lite-xl/pull/1895))

* Remove lhelper script, build configuration and dependency support
  ([#1906](https://github.com/lite-xl/lite-xl/pull/1906))

* Refactor how arguments are handled in process.start()
  ([#1854](https://github.com/lite-xl/lite-xl/pull/1854))

* Add a proper name to EmptyView
  ([#1569](https://github.com/lite-xl/lite-xl/pull/1569))

* Format renderer font scale code to be actually readable
  ([#1921](https://github.com/lite-xl/lite-xl/pull/1921))

* Update PCRE2 wrap
  ([#1927](https://github.com/lite-xl/lite-xl/pull/1927))

* Use meson datadir as lite_datadir base
  ([#1939](https://github.com/lite-xl/lite-xl/pull/1939))

* Convert unix style paths literals into meson path segments
  ([#1938](https://github.com/lite-xl/lite-xl/pull/1938))

## [2.1.5] - 2024-06-29

This release addresses several bugs from upstream dependencies and
improves the stability and usability of the program.

### Features

* New macOS installer background
  ([#1816](https://github.com/lite-xl/lite-xl/pull/1816))

* Improve number highlighting for `language_c`
  ([#1752](https://github.com/lite-xl/lite-xl/pull/1752))

* Backport number highlighting improvements to `language_cpp`
  ([#1818](https://github.com/lite-xl/lite-xl/pull/1818))

* Support binary integer literals for `language_cpp`
  ([#1819](https://github.com/lite-xl/lite-xl/pull/1819))

* Improve syntax highlighting for `language_python`
  ([#1723](https://github.com/lite-xl/lite-xl/pull/1723))

* Support for drag-and-drop into Dock and "Open with" menu in macOS
  ([#1822](https://github.com/lite-xl/lite-xl/pull/1822))

* Support `static constexpr` syntax in `language_cpp`
  ([#1806](https://github.com/lite-xl/lite-xl/pull/1806))

### Fixes

* Fix removing threads when iterating over `core.threads`
  ([#1794](https://github.com/lite-xl/lite-xl/pull/1794))

* Fix dirmonitor backend selection
  ([#1790](https://github.com/lite-xl/lite-xl/pull/1790))

* Fix clipboard removing newlines on Windows
  ([#1788](https://github.com/lite-xl/lite-xl/pull/1788))

* Change co_wait to co_await in `language_cpp`
  ([#1800](https://github.com/lite-xl/lite-xl/pull/1800))

* Fix font scale on monitor change when `RENDERER` backend is used
  ([#1650](https://github.com/lite-xl/lite-xl/pull/1650))

* Avoid calling the change callback multiple times in the same notification
  ([#1824](https://github.com/lite-xl/lite-xl/pull/1824))

* Fix autoreload reloading file too soon and misses some updates
  ([#1823](https://github.com/lite-xl/lite-xl/pull/1823))

* Fix drag-and-drop multiple folders into Dock icon in macOS
  ([#1828](https://github.com/lite-xl/lite-xl/pull/1828))

* Fix `Doc:merge_cursors()` accepting selection table index instead of selection index
  ([#1833](https://github.com/lite-xl/lite-xl/pull/1833))

* Fix `Doc:merge_cursors()` table index calculation
  ([#1834](https://github.com/lite-xl/lite-xl/pull/1834))

### Other Changes

* Add functionality to generate release notes
  ([#1774](https://github.com/lite-xl/lite-xl/pull/1774))

* Fix typo in release note template
  ([#1801](https://github.com/lite-xl/lite-xl/pull/1801))

* Update action dependencies
  ([#1724](https://github.com/lite-xl/lite-xl/pull/1724))

* Update labeler action config
  ([#1805](https://github.com/lite-xl/lite-xl/pull/1805))

* Update macOS runner images
  ([#1804](https://github.com/lite-xl/lite-xl/pull/1804))

* Update macOS copyright notice
  ([#1815](https://github.com/lite-xl/lite-xl/pull/1815))

* Update SDL2 and PCRE2
  ([#1812](https://github.com/lite-xl/lite-xl/pull/1812))

## [2.1.4] - 2024-04-16

This release addresses severe bugs not found in previous releases,
and improves the usability of the program.

### Features

* Add `.pyi` extension to `language_python`.
  ([#1728](https://github.com/lite-xl/lite-xl/pull/1728))

* Improve autocomplete suggestions box behavior with long text
  ([#1734](https://github.com/lite-xl/lite-xl/pull/1734))

* Improve `CommandView` and autocomplete scroll behavior
  ([#1732](https://github.com/lite-xl/lite-xl/pull/1732))

* Add `from` symbol to support ESM
  ([#1754](https://github.com/lite-xl/lite-xl/pull/1754))

* Add Arduino syntax highlighting support in `language_cpp`
  ([#1767](https://github.com/lite-xl/lite-xl/pull/1767))

* Skip patterns matching nothing in tokenizer
  ([#1743](https://github.com/lite-xl/lite-xl/pull/1743))

### Fixes

* Fix uninitialized variables in `src/api/process.c`
  ([#1719](https://github.com/lite-xl/lite-xl/pull/1719))

* Fix `language_js` regex/comment distinction
  ([#1731](https://github.com/lite-xl/lite-xl/pull/1731))

* Fix compilation on non-MINGW64 platforms
  ([#1739](https://github.com/lite-xl/lite-xl/pull/1739))

* Limit `language_js` regex avoidance to numbers, and fix starting `/*` comments
  ([#1744](https://github.com/lite-xl/lite-xl/pull/1744))

* Fix `buffer_size` in `g_read` for Windows
  ([#1722](https://github.com/lite-xl/lite-xl/pull/1722))

* Fix missing permission for creating releases
  ([#1770](https://github.com/lite-xl/lite-xl/pull/1770))

### Other Changes

* Rectify LICENSE dates and owners
  ([#1748](https://github.com/lite-xl/lite-xl/pull/1748))

* Fix some typos in `core.init`
  ([#1755](https://github.com/lite-xl/lite-xl/pull/1755))

## [2.1.3] - 2024-01-29

This release addresses severe bugs not found in previous releases.

### Fixes

* Fix `doc:create-cursor-{previous,next}-line` with tabs
  ([#1697](https://github.com/lite-xl/lite-xl/pull/1697))

* Fix heap buffer overflow and memory leaks in process and renderer API
  ([#1705](https://github.com/lite-xl/lite-xl/pull/1705))

* Improve Python number syntax highlighting
  ([#1704](https://github.com/lite-xl/lite-xl/pull/1704))

* Fix inconsistent NagView options on `doc:save`
  ([#1696](https://github.com/lite-xl/lite-xl/pull/1696))

* Fix crashes with autoreload when files are deleted externally and replaced with a directory.
  ([#1698](https://github.com/lite-xl/lite-xl/pull/1698))

* Improve JavaScript number syntax highlighting
  ([#1710](https://github.com/lite-xl/lite-xl/pull/1710))

### Other Changes

* Process API style changes
  ([#1709](https://github.com/lite-xl/lite-xl/pull/1709))

## [2.1.2] - 2023-12-29

This release addresses some issues present in the previous release,
and improves the performance and stability of Lite XL.

### New Features

* The context menu in TreeView is now navigable with a keyboard.
  ([#1338](https://github.com/lite-xl/lite-xl/pull/1338))

* A universal build of Lite XL is now available for macOS.
  This build runs natively on both Intel and Apple Silicon macs.
  ([#1458](https://github.com/lite-xl/lite-xl/pull/1458))

* Most Unicode characters should be displayed properly
  if your fonts support them.
  ([#1524](https://github.com/lite-xl/lite-xl/pull/1524))

* LogView will no longer scroll automatically if the user had scrolled.
  The LogView will only scroll automatically when the user scrolls up
  to the last entry.
  ([#1546](https://github.com/lite-xl/lite-xl/pull/1546))

* When using different fonts (especially fonts that render different scripts),
  the letters will be aligned vertically.
  ([#1560](https://github.com/lite-xl/lite-xl/pull/1560))

* Unsaved named files are now saved in the workspace.
  ([#1597](https://github.com/lite-xl/lite-xl/pull/1597))

* macOS builds are now signed with a developer certificate.
  This allows the user to right click the application in Finder and execute
  it directly.
  ([#1656](https://github.com/lite-xl/lite-xl/pull/1656))

### Performance Improvements

* Allow command buffer to be expanded.
  ([#1297](https://github.com/lite-xl/lite-xl/pull/1297))

* Use table.move to implement `common.splice`.
  ([#1324](https://github.com/lite-xl/lite-xl/pull/1324))

* Create renderer only when it doesn't exist.
  ([#1315](https://github.com/lite-xl/lite-xl/pull/1315))

* Avoid drawing hidden text in `DocView:draw_line_text`.
  ([#1298](https://github.com/lite-xl/lite-xl/pull/1298))

* Don't calculate widths per-uft8-char when not needed.
  ([#1409](https://github.com/lite-xl/lite-xl/pull/1409))

* Allow tokenizer to pause and resume in the middle of a line.
  ([#1444](https://github.com/lite-xl/lite-xl/pull/1444))

* Optimize CI build times on MSYS2.
  ([#1435](https://github.com/lite-xl/lite-xl/pull/1435))

* Significant memory usage improvements when using huge fonts on Windows.
  ([#1555](https://github.com/lite-xl/lite-xl/pull/1555))

* Optimize background tasks response time.
  ([#1601](https://github.com/lite-xl/lite-xl/pull/1601))

### Backward Incompatible Changes

* The native plugin API is now usable on multiple source files,
  without causing any duplicated symbol errors during compilation.
  Plugins using the new plugin API header must define `LITE_XL_PLUGIN_ENTRYPOINT`
  before importing the header, in one of their source files.
  ([#1335](https://github.com/lite-xl/lite-xl/pull/1335))

* The native plugin API header now follows the Lua 5.4 API.
  Previously, the plugin API header followed the Lua 5.2 API.
  ([#1436](https://github.com/lite-xl/lite-xl/pull/1436))

* On Linux, `process.start()` will now throw an error if `execv()` fails.
  ([#1363](https://github.com/lite-xl/lite-xl/pull/1363))

* Lite XL will use the default `SCALE` of 1 due to unreliable display
  scale detection. This may be fixed in a later version of Lite XL.
  Set the `LITE_SCALE` environment variable to override this value.

### Fixes

* Fix minor typos in user module
  ([#1289](https://github.com/lite-xl/lite-xl/pull/1289))

* Do not allow users to create an empty font group
  ([#1303](https://github.com/lite-xl/lite-xl/pull/1303))

* Fix a memory leak
  ([#1305](https://github.com/lite-xl/lite-xl/pull/1305))

* Make dirwatch sorting compatible with what file_bisect expects
  ([#1300](https://github.com/lite-xl/lite-xl/pull/1300))

* Handle readlink errors
  ([#1292](https://github.com/lite-xl/lite-xl/pull/1292))

* Disable horizontal scrolling when linewrapping is enabled
  ([#1309](https://github.com/lite-xl/lite-xl/pull/1309))

* Update widgets install location

* Add missing luaL_typeerror symbol to plugin API
  ([#1313](https://github.com/lite-xl/lite-xl/pull/1313))

* Defer lua error until after cleanup
  ([#1310](https://github.com/lite-xl/lite-xl/pull/1310))

* Make empty groups in regex.gmatch return their offset
  ([#1325](https://github.com/lite-xl/lite-xl/pull/1325))

* Add missing header declaration

* Fix msys build now requiring ca-certificates
  ([#1348](https://github.com/lite-xl/lite-xl/pull/1348))

* Fix path to macOS arm64 cross file in GitHub workflows

* Fix Doc contextmenu not registering commands if scale plugin is not found
  ([#1338](https://github.com/lite-xl/lite-xl/pull/1338))

* Fix TreeView contextmenu commands not working if the mouse hovers DocView
  ([#1338](https://github.com/lite-xl/lite-xl/pull/1338))

* Fix incorrect contextmenu predicate
  ([#1338](https://github.com/lite-xl/lite-xl/pull/1338))

* Properly rescale NagView on scale change
  ([#1379](https://github.com/lite-xl/lite-xl/pull/1379))

* Scale plugin also rescales `style.expanded_scrollbar_size`
  ([#1380](https://github.com/lite-xl/lite-xl/pull/1380))

* Improve DocView:get_visible_line_range precision
  ([#1382](https://github.com/lite-xl/lite-xl/pull/1382))

* Fix up some post 5.1/JIT Symbols
  ([#1385](https://github.com/lite-xl/lite-xl/pull/1385))

* Fix incorrect x_offset if opened docs have different tab sizes
  ([#1383](https://github.com/lite-xl/lite-xl/pull/1383))

* Use correct view for scrolling to find-replace:repeat-find results
  ([#1400](https://github.com/lite-xl/lite-xl/pull/1400))

* Improve text width calculation precision
  ([#1408](https://github.com/lite-xl/lite-xl/pull/1408))

* Add asynchronous process reaping
  ([#1412](https://github.com/lite-xl/lite-xl/pull/1412))

* Fix cursors positions when deleting multiple selections
  ([#1393](https://github.com/lite-xl/lite-xl/pull/1393),
   [#1463](https://github.com/lite-xl/lite-xl/pull/1463))

* Fix invalid EXEFILE and EXEDIR on Windows
  ([#1396](https://github.com/lite-xl/lite-xl/pull/1396))

* Fix `os.getenv()` not supporting UTF-8 output
  ([#1397](https://github.com/lite-xl/lite-xl/pull/1397))

* Fix differing stacktrace on stdout and file
  ([#1404](https://github.com/lite-xl/lite-xl/pull/1404))

* Update api_require to expose more symbols
  ([#1437](https://github.com/lite-xl/lite-xl/pull/1437))

* Make system.path_compare more case-aware
  ([#1457](https://github.com/lite-xl/lite-xl/pull/1457))

* Fix for api_require wrong macro && conditions
  ([#1465](https://github.com/lite-xl/lite-xl/pull/1465))

* Merge carets after doc:move-to-{previous,next}-char
  ([#1462](https://github.com/lite-xl/lite-xl/pull/1462))

* Process API improvements (again)
  ([#1370](https://github.com/lite-xl/lite-xl/pull/1370))

* Make system.path_compare more digit-aware
  ([#1474](https://github.com/lite-xl/lite-xl/pull/1474))

* Check for HANDLE_INVALID in Process API
  ([#1475](https://github.com/lite-xl/lite-xl/pull/1475))

* Fix linewrapping bug to do with wordwrapping

* Fix compiler warning for printing size_t in rencache.c

* Return error string from C searcher

* Restore horizontal scroll position after scale change
  ([#494](https://github.com/lite-xl/lite-xl/pull/494))

* Fix memory leak in renderer.c when freeing glyphsets

* Move lineguide below blinking cursor
  ([#1511](https://github.com/lite-xl/lite-xl/pull/1511))

* Close lua state when exiting on a runtime error
  ([#1487](https://github.com/lite-xl/lite-xl/pull/1487))

* Mark linewrapping open_files table as weak

* Don't use core.status_view if not yet initialized when logging

* Revert "core syntax: strip the path from filename on syntax.get ([#1168](https://github.com/lite-xl/lite-xl/pull/1168))"
  ([#1322](https://github.com/lite-xl/lite-xl/pull/1322))

* Make Doc:sanitize_position return a more appropriate col
  ([#1469](https://github.com/lite-xl/lite-xl/pull/1469))

* Skip checking files if no filename was provided to syntax.get

* Normalize stroke before adding keybind
  ([#1334](https://github.com/lite-xl/lite-xl/pull/1334))

* Make DocView aware of scrollbars sizes
  ([#1177](https://github.com/lite-xl/lite-xl/pull/1177))

* Normalize strokes in fixed order
  ([#1572](https://github.com/lite-xl/lite-xl/pull/1572))

* Defer core:open-log until everything is loaded
  ([#1585](https://github.com/lite-xl/lite-xl/pull/1585))

* Fix returned percent when clicking the Scrollbar track

* Fix C++14 digit separators
  ([#1593](https://github.com/lite-xl/lite-xl/pull/1593))

* Make linewrapping consider the expanded Scrollbar size

* Fix dimmed text when antialiasing is turned off
  ([#1641](https://github.com/lite-xl/lite-xl/pull/1641))

* Mark unsaved named files as dirty
  ([#1598](https://github.com/lite-xl/lite-xl/pull/1598))

* Make `common.serialize()` locale-independent and nan/inf compatible
  ([#1640](https://github.com/lite-xl/lite-xl/pull/1640))

* Ignore keypresses during IME composition
  ([#1573](https://github.com/lite-xl/lite-xl/pull/1573))

* Fix deadlock if error handler jumps somewhere else
  ([#1647](https://github.com/lite-xl/lite-xl/pull/1647))

* Avoid considering single spaces in detectindent
  ([#1595](https://github.com/lite-xl/lite-xl/pull/1595))

* Fix deleting indentation with multiple cursors
  ([#1670](https://github.com/lite-xl/lite-xl/pull/1670))

* Fix `set_target_size` passing the wrong value to plugins
  ([#1657](https://github.com/lite-xl/lite-xl/pull/1657))

* Limit `system.{sleep,wait_event}` to `timeouts >= 0`
  ([#1666](https://github.com/lite-xl/lite-xl/pull/1666))

* Fix running core.step when receiving an event while not waiting
  ([#1667](https://github.com/lite-xl/lite-xl/pull/1667))

* Fix dirmonitor sorting issues
  ([#1599](https://github.com/lite-xl/lite-xl/pull/1599))

* Scale mouse coordinates by window scale
  ([#1630](https://github.com/lite-xl/lite-xl/pull/1630))

* Made coroutines make more sense, and fixed a bug
  ([#1381](https://github.com/lite-xl/lite-xl/pull/1381))

* Fix selecting newlines with `find-replace:select-add-{next,all}`
  ([#1608](https://github.com/lite-xl/lite-xl/pull/1608))

* Fix editing after undo not clearing the change id
  ([#1574](https://github.com/lite-xl/lite-xl/pull/1574))

* Fix language_js regex constant detection
  ([#1581](https://github.com/lite-xl/lite-xl/pull/1581))
  
* Fix patterns starting with `^` in tokenizer
  ([#1645](https://github.com/lite-xl/lite-xl/pull/1645))

* Use x offset to define render command rect in rencache_draw_text
  ([#1618](https://github.com/lite-xl/lite-xl/pull/1618))

* Improve font/color change detection in `language_md`
  ([#1614](https://github.com/lite-xl/lite-xl/pull/1614))

* Allow long commands and envs on process_start
  ([#1477](https://github.com/lite-xl/lite-xl/pull/1477)) 

* Fix typo in `drawwhitespace.lua`

* Fix NagBar save failed message
  ([#1678](https://github.com/lite-xl/lite-xl/pull/1678))

* Fix typo in `drawwhitespace.lua`

* Add autocompletion to multicursor
  ([#1394](https://github.com/lite-xl/lite-xl/pull/1394))

### Other Changes

* Make api_require's nodes const
  ([#1296](https://github.com/lite-xl/lite-xl/pull/1296))

* Don't set a value twice
  ([#1306](https://github.com/lite-xl/lite-xl/pull/1306))

* Center title and version in emptyview
  ([#1311](https://github.com/lite-xl/lite-xl/pull/1311))

* Use master branch for packaging plugins for addons release

* Reorganize resources folder and add wasm target
  ([#1244](https://github.com/lite-xl/lite-xl/pull/1244))

* Replace uses of SDL_Window with RenWindow
  ([#1319](https://github.com/lite-xl/lite-xl/pull/1319))

* Update dummy dirmonitor method signature to match prototypes

* Remove static libgcc from meson
  ([#1290](https://github.com/lite-xl/lite-xl/pull/1290))

* Pass RenWindow by argument
  ([#1321](https://github.com/lite-xl/lite-xl/pull/1321))

* Get rid of annoying forward slash on windows
  ([#1345](https://github.com/lite-xl/lite-xl/pull/1345))

* Improve plugins config table handling
  ([#1356](https://github.com/lite-xl/lite-xl/pull/1356))

* Add manifest on Windows
  ([#1405](https://github.com/lite-xl/lite-xl/pull/1405))

* Split Command struct into different structs for each command type
  ([#1407](https://github.com/lite-xl/lite-xl/pull/1407))

* Move SetProcessDPIAware to manifests
  ([#1413](https://github.com/lite-xl/lite-xl/pull/1413))

* Use clipping functions provided by SDL
  ([#1426](https://github.com/lite-xl/lite-xl/pull/1426))

* Aggregate SDL_Surfaces and their scale in RenSurface
  ([#1429](https://github.com/lite-xl/lite-xl/pull/1429))

* Disable trimwhitespace and drawwhitespace via their configs
  ([#1446](https://github.com/lite-xl/lite-xl/pull/1446))

* Bump dependency versions
  ([#1434](https://github.com/lite-xl/lite-xl/pull/1434))

* Improvements to cross-compilation
  ([#1458](https://github.com/lite-xl/lite-xl/pull/1458))

* Move native plugin API header into include/
  ([#1440](https://github.com/lite-xl/lite-xl/pull/1440))

* Build releases with Ubuntu 18.04 container
  ([#1460](https://github.com/lite-xl/lite-xl/pull/1460))

* Update GitHub Actions dependencies

* Make all parameters for set_window_hit_test optional in documentation

* Attach command buffer to Renderer Window
  ([#1472](https://github.com/lite-xl/lite-xl/pull/1472))

* Fix comment typo in object.lua
  ([#1541](https://github.com/lite-xl/lite-xl/pull/1541))

* Allow setting custom glyphset size
  ([#1542](https://github.com/lite-xl/lite-xl/pull/1542))

* Use FreeType header names in renderer.c
  ([#1554](https://github.com/lite-xl/lite-xl/pull/1554))

* Add documentation for core.common
  ([#1510](https://github.com/lite-xl/lite-xl/pull/1510))

* Document missing parameter for system.path_compare
  ([#1566](https://github.com/lite-xl/lite-xl/pull/1566))

* Add documentation for core.command
  ([#1564](https://github.com/lite-xl/lite-xl/pull/1564))

* Update the *Installing prebuild* section in README.md
  ([#1548](https://github.com/lite-xl/lite-xl/pull/1548))

* Update README.md to remove previously installed files
  prior to installing a new version

* Use lite-xl Build Box to build releases
  ([#1571](https://github.com/lite-xl/lite-xl/pull/1571))

* Use Lua wrap by default
  ([#1481](https://github.com/lite-xl/lite-xl/pull/1481))

* Add documentation for contextmenu
  ([#1567](https://github.com/lite-xl/lite-xl/pull/1567))

* Use dmgbuild to create DMGs
  ([#1664](https://github.com/lite-xl/lite-xl/pull/1664))

* Un-hardcode lua subproject detection and update dependencies
  ([#1676](https://github.com/lite-xl/lite-xl/pull/1676))

* Make license time-independent
  ([#1655](https://github.com/lite-xl/lite-xl/pull/1655))

## [2.1.1] - 2022-12-29

### New Features

* Add config.keep_newline_whitespace option
  ([#1184](https://github.com/lite-xl/lite-xl/pull/1184))

* Add regex.find_offsets, regex.find, improve regex.match
  ([#1232](https://github.com/lite-xl/lite-xl/pull/1232))

* Added regex.gmatch ([#1233](https://github.com/lite-xl/lite-xl/pull/1233))

* add touch events ([#1245](https://github.com/lite-xl/lite-xl/pull/1245))

### Performance Improvements

* highlighter: autostop co-routine when not needed
  ([#881](https://github.com/lite-xl/lite-xl/pull/881))

* core: ported regex.gsub to faster native version
  ([#1233](https://github.com/lite-xl/lite-xl/pull/1233))

### Backward Incompatible Changes

* For correctness, the behaviour of `regex.match` was changed to more closely
  behave like `string.match`.

* `regex.find_offsets` now provides the previous functionality of `regex.match`
  with a more appropriate function name.

* `regex.gsub` doesn't provides the indexes of matches and replacements anymore,
  now it behaves more similar to `string.gsub` (the only known affected plugin
  was `regexreplacepreview` which has already been adapted)

### UI Enhancements

* statusview: respect right padding of item tooltip
  ([0373d29f](https://github.com/lite-xl/lite-xl/commit/0373d29f99f286b2fbdda5a6837ef3797c988b88))

* feat: encode home in statusview file path
  ([#1224](https://github.com/lite-xl/lite-xl/pull/1224))

* autocomplete: wrap the autocomplete results around
  ([#1223](https://github.com/lite-xl/lite-xl/pull/1223))

* feat: alert user via nagview if file cannot be saved
  ([#1230](https://github.com/lite-xl/lite-xl/pull/1230))

* contextmenu: make divider less aggressive
  ([#1228](https://github.com/lite-xl/lite-xl/pull/1228))

* Improve IME location updates
  ([#1170](https://github.com/lite-xl/lite-xl/pull/1170))

* fix: move tab scroll buttons to remove spacing before 1st tab
  ([#1231](https://github.com/lite-xl/lite-xl/pull/1231))

* Allow TreeView file operation commands when focused
  ([#1256](https://github.com/lite-xl/lite-xl/pull/1256))

* contextmenu: adjust y positioning if less than zero
  ([#1268](https://github.com/lite-xl/lite-xl/pull/1268))

### Fixes

* Don't sort in Doc:get_selection_idx with an invalid index
  ([b029f599](https://github.com/lite-xl/lite-xl/commit/b029f5993edb7dee5ccd2ba55faac1ec22e24609))

* tokenizer: remove the limit of 3 subsyntaxes depth
  ([#1186](https://github.com/lite-xl/lite-xl/pull/1186))

* dirmonitor: give kevent a timeout so it doesn't lock forever
  ([#1180](https://github.com/lite-xl/lite-xl/pull/1180))

* dirmonitor: fix win32 implementation name length to prevent ub
  ([5ab8dc0](https://github.com/lite-xl/lite-xl/commit/5ab8dc027502146dd947b3d2c7544ba096a3881b))

* Make linewrapping plugin recompute breaks before scrolling
  ([#1190](https://github.com/lite-xl/lite-xl/pull/1190))

* Add missing get_exe_filename() implementation for FreeBSD
  ([#1198](https://github.com/lite-xl/lite-xl/pull/1198))

* (Windows) Load fonts with UTF-8 filenames
  ([#1201](https://github.com/lite-xl/lite-xl/pull/1201))

* Use subsyntax info to toggle comments
  ([#1202](https://github.com/lite-xl/lite-xl/pull/1202))

* Pass the currently selected item to CommandView validation
  ([#1203](https://github.com/lite-xl/lite-xl/pull/1203))

* Windows font loading hotfix
  ([#1205](https://github.com/lite-xl/lite-xl/pull/1205))

* better error messages for checkcolor
  ([#1211](https://github.com/lite-xl/lite-xl/pull/1211))

* Fix native plugins not reloading upon core:restart
  ([#1219](https://github.com/lite-xl/lite-xl/pull/1219))

* Converted from bytes to characters, as this is what windows is expecting
  ([5ab8dc02](https://github.com/lite-xl/lite-xl/commit/5ab8dc027502146dd947b3d2c7544ba096a3881b))

* Fix some syntax errors ([#1243](https://github.com/lite-xl/lite-xl/pull/1243))

* toolbarview: Remove tooltip when hidden
  ([#1251](https://github.com/lite-xl/lite-xl/pull/1251))

* detectindent: Limit subsyntax depth
  ([#1253](https://github.com/lite-xl/lite-xl/pull/1253))

* Use Lua string length instead of relying on strlen (#1262)
  ([#1262](https://github.com/lite-xl/lite-xl/pull/1262))

* dirmonitor: fix high cpu usage
  ([#1271](https://github.com/lite-xl/lite-xl/pull/1271)),
  ([#1274](https://github.com/lite-xl/lite-xl/pull/1274))

* Fix popping subsyntaxes that end consecutively
  ([#1246](https://github.com/lite-xl/lite-xl/pull/1246))

* Fix userdata APIs for Lua 5.4 in native plugin interface
  ([#1188](https://github.com/lite-xl/lite-xl/pull/1188))

* Fix horizontal scroll with touchpad on MacOS
  ([74349f8e](https://github.com/lite-xl/lite-xl/commit/74349f8e566ec31acd9a831a060b677d706ae4e8))

### Other Changes

* (Windows) MSVC Support ([#1199](https://github.com/lite-xl/lite-xl/pull/1199))

* meson: updated all subproject wraps
  ([#1214](https://github.com/lite-xl/lite-xl/pull/1214))

* set arch tuple in meson ([#1254](https://github.com/lite-xl/lite-xl/pull/1254))

* update documentation for system
  ([#1210](https://github.com/lite-xl/lite-xl/pull/1210))

* docs api: added dirmonitor
  ([7bb86e16](https://github.com/lite-xl/lite-xl/commit/7bb86e16f291256a99d2e87beb77de890cfaf0fe))

* trimwhitespace: expose functionality and extra features
  ([#1238](https://github.com/lite-xl/lite-xl/pull/1238))

* plugins projectsearch: expose its functionality
  ([#1235](https://github.com/lite-xl/lite-xl/pull/1235))

* Simplify SDL message boxes
  ([#1249](https://github.com/lite-xl/lite-xl/pull/1249))

* Add example settings to _overwrite_ an existing key binding
  ([#1270](https://github.com/lite-xl/lite-xl/pull/1270))

* Fix two typos in data/init.lua
  ([#1272](https://github.com/lite-xl/lite-xl/pull/1272))

* Updated meson wraps to latest (SDL v2.26, PCRE2 v10.42)

## [2.1.0] - 2022-11-01

### New Features
* Make distinction between
  [line and block comments](https://github.com/lite-xl/lite-xl/pull/771),
  and added all appropriate functionality to the commenting/uncommenting lines.

* [Added in line paste mode](https://github.com/lite-xl/lite-xl/pull/713),
  if you copy without a selection.

* Many [improvements to treeview](https://github.com/lite-xl/lite-xl/pull/732),
  including keyboard navigation of treeview, and ability to specify single vs.
  double-click behavior.

* Added in [soft line wrapping](https://github.com/lite-xl/lite-xl/pull/636)
  as core plugin, under `linewrapping.lua`, use `F10` to activate.

* Revamped [StatusView](https://github.com/lite-xl/lite-xl/pull/852) API with
  new features that include:

  * Support for predicates, click actions, tooltips on item hover
    and custom drawing of added items.
  * Hide items that are too huge by rendering with clip_rect.
  * Ability to drag or scroll the left or right if too many items to display.
  * New status bar commands accessible from the command palette that
    include: toggling status bar visibility, toggling specific item visibility,
    enable/disable status messages, etc...

* Added `renderer.font.group` interface to set up
  [font fallback groups](https://github.com/lite-xl/lite-xl/pull/616) in
  the font renderer, if a token doesn't have a corresponding glyph.

  **Example:**
  ```lua
  local emoji_font = renderer.font.load(USERDIR .. "/fonts/NotoEmoji-Regular.ttf", 15 * SCALE)
  local nonicons = renderer.font.load(USERDIR .. "/fonts/nonicons.ttf", 15 * SCALE)
  style.code_font = renderer.font.group({style.code_font, nonicons, emoji_font})
  ```

* Added in the ability to specify
  [mouse clicks](https://github.com/lite-xl/lite-xl/pull/589) in the
  keymap, allowing for easy binds of `ctrl+lclick`, and the like.

  **Example:**
  ```lua
  keymap.add { ["ctrl+shift+3lclick"] = "core:open-log" }
  ```

* Improved ability for plugins to be loaded at a given time, by making the
  convention of defining a config for the plugin using `common.merge` to merge
  existing hashes together, rather than overwriting.

* Releases will now include all language plugins and the
  [settings gui](https://github.com/lite-xl/lite-xl-plugins/pull/65) plugin.

* New [core.warn](https://github.com/lite-xl/lite-xl/pull/1005) was introduced.

* Added [suggestions warping](https://github.com/lite-xl/lite-xl/pull/1003)
  for `CommandView`.

* Allow regexes in tokenizer to
  [split tokens with group](https://github.com/lite-xl/lite-xl/pull/999).

* Added [settings gui support](https://github.com/lite-xl/lite-xl/pull/995)
  to core plugins.

* Support for [stricter predicates](https://github.com/lite-xl/lite-xl/pull/990)
  by appending a `!`, eg: `"core.docview!"`.

* [UTF8 support in tokenizer](https://github.com/lite-xl/lite-xl/pull/945)
  and new utf8 counter parts of string functions,
  eg: `string.ulen`, `string.ulower`, etc...

* Added [utf8 support](https://github.com/lite-xl/lite-xl/pull/986) on doc
  lower and upper commands.

* Allow syntax patterns to match with the
  [beginning of the line](https://github.com/lite-xl/lite-xl/pull/860).

  **Example:**
  ```lua
  { pattern = "^my_pattern_starting_at_beginning", type="symbol" }
  ```

* [Add View:on_file_dropped](https://github.com/lite-xl/lite-xl/pull/845).

* Implemented new function to retrieve current process id of lite-xl
  [system.get_process_id()](https://github.com/lite-xl/lite-xl/pull/833).

* [Allow functions in keymap](https://github.com/lite-xl/lite-xl/pull/948).

* [Add type ahead to CommandView](https://github.com/lite-xl/lite-xl/pull/963).

* Add syntax symbols to
  [auto-complete](https://github.com/lite-xl/lite-xl/pull/913).

* Add [animation categories](https://github.com/lite-xl/lite-xl/pull/941)
  to enable finer transitions control.

* Added in a [native plugin](https://github.com/lite-xl/lite-xl/pull/527)
  interface that allows for C-level interfacing with a statically-linked
  lite-xl. The implementation of this may change in future.

* Config: added new development option to prevent plugin version checking at
  startup named [skip_plugins_version](https://github.com/lite-xl/lite-xl/pull/879)

* Added a smoothing and strikethrough option to font loading
  ([#1087](https://github.com/lite-xl/lite-xl/pull/1087))

* Allow command predicates to manage parameters, allow overwriting commands
  ([#1098](https://github.com/lite-xl/lite-xl/pull/1098))

* Added in simple directory search to treeview.
  ([#1110](https://github.com/lite-xl/lite-xl/pull/1110))

* Added in native modules suffixes.
  ([#1111](https://github.com/lite-xl/lite-xl/pull/1111))

* plugin scale: added option to set default scale
  ([#1115](https://github.com/lite-xl/lite-xl/pull/1115))

* Added in ability to have init.so as a require for cpath.
  ([#1126](https://github.com/lite-xl/lite-xl/pull/1126))

* Added system.raise_window() ([#1131](https://github.com/lite-xl/lite-xl/pull/1131))

* Initial horizontal scrollbar support ([#1124](https://github.com/lite-xl/lite-xl/pull/1124))

* IME support ([#991](https://github.com/lite-xl/lite-xl/pull/991))

### Performance Improvements

* [Load space metrics only when creating font](https://github.com/lite-xl/lite-xl/pull/1032)

* [Performance improvement](https://github.com/lite-xl/lite-xl/pull/883)
  of detect indent plugin.

* Improve performance of
  [ren_draw_rect](https://github.com/lite-xl/lite-xl/pull/935).

* Improved [tokenizer performance](https://github.com/lite-xl/lite-xl/pull/896).

* drawwhitespace: [Cache whitespace location](https://github.com/lite-xl/lite-xl/pull/1030)

* CommandView: improve performance by
  [only drawing visible](https://github.com/lite-xl/lite-xl/pull/1047)

### Backward Incompatible Changes
* [Upgraded Lua to 5.4](https://github.com/lite-xl/lite-xl/pull/781), which
  should improve performance, and provide useful extra functionality. It should
  also be more available out of the box with most modern
  linux/unix-based package managers.

* Bumped plugin mod-version number as various interfaces like: `DocView`,
  `StatusView` and `CommandView` have changed which should require a revision
  from plugin developers to make sure their plugins work with this new release.

* Changed interface for key handling; now, all components should return true if
  they've handled the event.

* For plugin developers, declaring config options by directly assigning
  to the plugin table (eg: `config.plugins.plugin_name.myvalue = 10`) was
  deprecated in favor of using `common.merge`.

  **Example:**
  ```lua
  config.plugins.autowrap = common.merge({
    enabled = false,
    files = { "%.md$", "%.txt$" }
  }, config.plugins.autowrap)
  ```

* `DocView:draw_text_line` and related functions been used by plugin developers
  require a revision, since some of this interfaces were updated to support
  line wrapping.

* Removed `cp_replace`, and replaced this with a core plugin,
  [drawwhitespace.lua](https://github.com/lite-xl/lite-xl/pull/908).

### Deprecated Features
* For plugins the usage of the `--lite-xl` version tag was dropped
  in favor of `--mod-version`.

* Overriding `StatusView:get_items()` has been deprecated in favor of
  the new dedicated interface to insert status bar items:

  **New Interface:**
  ```lua
  ------@return StatusView.Item
  function StatusView:add_item(
    { predicate, name, alignment, get_item, command, position, tooltip, separator }
  ) end
  ```

  **Example:**
  ```lua
  core.status_view:add_item({
    predicate = nil,
    name = "status:memory-usage",
    alignment = StatusView.Item.RIGHT,
    get_item = function()
      return {
        style.text,
        string.format(
          "%.2f MB",
          (math.floor(collectgarbage("count") / 10.24) / 100)
        )
      }
    end,
    command = nil,
    position = 1,
    tooltip = "lua memory usage",
    separator = core.status_view.separator2
  })
  ```

* [CommandView:enter](https://github.com/lite-xl/lite-xl/pull/1004) now accepts
  a single options table as a parameter, meaning that the old way of calling
  this function will now show a deprecation message. Also `CommandView:set_text`
  and `CommandView:set_hidden_suggestions` has been
  [deprecated](https://github.com/lite-xl/lite-xl/pull/1014).

  **Example:**
  ```lua
  core.command_view:enter("Title", {
    submit = function() end,
    suggest = function() return end,
    cancel = function() end,
    validate = function() return true end,
    text = "",
    select_text = false,
    show_suggestions = true,
    typeahead = true,
    wrap = true
  })
  ```

### Other Changes
* Removed `dmon`, and implemented independent backends for dirmonitoring. Also
  more cleanly split out dirmonitoring into its own class in lua, from core.init.
  We should now support FreeBSD; and any other system that uses `kqueue` as
  their dir monitoring library. We also have a dummy-backend, which reverts
  transparently to scanning if there is some issue with applying OS-level
  watches (such as system limits).

* Removed `libagg` and the font renderer; compacted all font rendering into a
  single renderer.c file which uses `libfreetype` directly. Now allows for ad-hoc
  bolding, italics, and underlining of fonts.

* Removed `reproc` and replaced this with a simple POSIX/Windows implementation
  in `process.c`. This allows for greater tweakability (i.e. we can now `break`
  for debugging purposes), performance (startup time of subprocesses is
  noticeably shorter), and simplicity (we no longer have to link reproc, or
  winsock, on windows).

* [Split out `Node` and `EmptyView`](https://github.com/lite-xl/lite-xl/pull/715)
  into their own lua files, for plugin extensibility reasons.

* Improved fuzzy_matching to probably give you something closer to what you're
  looking for.

* Improved handling of alternate keyboard layouts.

* Added in a default keymap for `core:restart`, `ctrl+shift+r`.

* Improvements to the [C and C++](https://github.com/lite-xl/lite-xl/pull/875)
  syntax files.

* Improvements to [markdown](https://github.com/lite-xl/lite-xl/pull/862)
  syntax file.

* [Improvements to borderless](https://github.com/lite-xl/lite-xl/pull/994)
  mode on Windows.

* Fixed a bunch of problems relating to
  [multi-cursor](https://github.com/lite-xl/lite-xl/pull/886).

* NagView: [support vscroll](https://github.com/lite-xl/lite-xl/pull/876) when
  message is too long.

* Meson improvements which include:
  * Added in meson wraps for freetype, pcre2, and SDL2 which target public,
    rather than lite-xl maintained repos.
  * [Seperate dirmonitor logic](https://github.com/lite-xl/lite-xl/pull/866),
    add build time detection of features.
  * Add [fallbacks](https://github.com/lite-xl/lite-xl/pull/798) to all
    common dependencies.
  * [Update SDL to 2.0.20](https://github.com/lite-xl/lite-xl/pull/884).
  * install [docs/api](https://github.com/lite-xl/lite-xl/pull/979) to datadir
    for lsp support.

* Always check if the beginning of the
  [text needs to be clipped](https://github.com/lite-xl/lite-xl/pull/871).

* Added [git commit](https://github.com/lite-xl/lite-xl/pull/859)
  on development builds.

* Update [autocomplete](https://github.com/lite-xl/lite-xl/pull/832)
  with changes needed for latest LSP plugin.

* Use SDL to manage color format mapping in
  [ren_draw_rect](https://github.com/lite-xl/lite-xl/pull/829).

* Various code [clean ups](https://github.com/lite-xl/lite-xl/pull/826).

* [Autoreload Nagview](https://github.com/lite-xl/lite-xl/pull/942).

* [Enhancements to scrollbar](https://github.com/lite-xl/lite-xl/pull/916).

* Set the correct working directory for the
  [AppImage version](https://github.com/lite-xl/lite-xl/pull/937).

* Core: fixes and changes to
  [temp file](https://github.com/lite-xl/lite-xl/pull/906) functions.

* [Added plugin load-time log](https://github.com/lite-xl/lite-xl/pull/966).

* TreeView improvements for
  [multi-project](https://github.com/lite-xl/lite-xl/pull/1010).

* Open LogView on user/project
  [module reload error](https://github.com/lite-xl/lite-xl/pull/1022).

* Check if ["open" pattern is escaped](https://github.com/lite-xl/lite-xl/pull/1034)

* Support [UTF-8 on Windows](https://github.com/lite-xl/lite-xl/pull/1041) (Lua)

* Make system.* functions support
  [UTF8 filenames on windows](https://github.com/lite-xl/lite-xl/pull/1042)

* [Fix memory leak](https://github.com/lite-xl/lite-xl/pull/1039) and wrong
  check in font_retrieve

* CommandView: do not change caret size with config.line_height
  ([#1080](https://github.com/lite-xl/lite-xl/pull/1080))

* Fixed process layer argument quoting; allows for strings with spaces
  ([#1132](https://github.com/lite-xl/lite-xl/pull/1132))

* Draw lite-xl icon in TitleView ([#1143](https://github.com/lite-xl/lite-xl/pull/1143))

* Add parameter validation to checkcolor and f_font_group
  ([#1145](https://github.com/lite-xl/lite-xl/pull/1145))

* Many, many, many more changes that are too numerous to list.

## [2.0.5] - 2022-01-29

Revamp the project's user module so that modifications are immediately applied.

Add a mechanism to ignore files or directory based on their project's path.
The new mechanism is backward compatible.*

Essentially there are two mechanisms:

- if a '/' or a '/$' appear at the end of the pattern it will match only
  directories
- if a '/' appears anywhere in the pattern except at the end the pattern will
  be applied to the path

In the first case, when the pattern corresponds to a directory, a '/' will be
appended to the name of each directory before checking the pattern.

In the second case, when the pattern corresponds to a path, the complete path of
the file or directory will be used with an initial '/' added to the path.

Fix several problems with the directory monitoring library.
Now the application should no longer assert when some related system call fails
and we fallback to rescan when an error happens.
On linux no longer use the recursive monitoring which was a source of problem.

Directory monitoring is now aware of symlinks and treat them appropriately.

Fix problem when encountering special files type on linux.

Improve directory monitoring so that the related thread actually waits without
using any CPU time when there are no events.

Improve the suggestion when changing project folder or opening a new one.
Now the previously used directory are suggested but if the path is changed the
actual existing directories that match the pattern are suggested.
In addition always use the text entered in the command view even if a suggested
entry is highlighted.

The NagView warning window now no longer moves the document content.

## [2.0.4] - 2021-12-20

Fix some bugs related to newly introduced directory monitoring using the
dmon library.

Fix a problem with plain text search using Lua patterns by error.

Fix a problem with visualization of UTF-8 characters that caused garbage
characters visualization.

Other fixes and improvements contributed by @Guldoman.

## [2.0.3] - 2021-10-23

Replace periodic rescan of project folder with a notification based system
using the [dmon library](https://github.com/septag/dmon). Improves performance
especially for large project folders since the application no longer needs to
rescan. The application also reports immediately any change in the project
directory even when the application is unfocused.

Improved find-replace reverse and forward search.

Fixed a bug in incremental syntax highlighting affecting documents with
multiple-lines comments or strings.

The application now always shows the tabs in the documents' view even when
a single document is opened. Can be changed with the option
`config.always_show_tabs`.

Fix problem with numeric keypad function keys not properly working.

Fix problem with pixel not correctly drawn at the window's right edge.

Treat correctly and open network paths on Windows.

Add some improvements for very slow network file systems.

Fix problem with python syntax highlighting, contributed by @dflock.

## [2.0.2] - 2021-09-10

Fix problem project directory when starting the application from Launcher on
macOS.

Improved LogView. Entries can now be expanded and there is a context menu to
copy the item's content.

Change the behavior of `ctrl+d` to add a multi-cursor selection to the next
occurrence. The old behavior to move the selection to the next occurrence is
now done using the shortcut `ctrl+f3`.

Added a command to create a multi-cursor with all the occurrences of the
current selection. Activated with the shortcut `ctrl+shift+l`.

Fix problem when trying to close an unsaved new document.

No longer shows an error for the `-psn` argument passed to the application on
macOS.

Fix `treeview:open-in-system` command on Windows.

Fix rename command to update name of document if opened.

Improve the find and replace dialog so that previously used expressions can be
recalled using "up" and "down" keys.

Build package script rewrite with many improvements.

Use bigger fonts by default.

Other minor improvements and fixes.

With many thanks to the contributors: @adamharrison, @takase1121, @Guldoman,
@redtide, @Timofffee, @boppyt, @Jan200101.

## [2.0.1] - 2021-08-28

Fix a few bugs and we mandate the mod-version 2 for plugins.
This means that users should ensure they have up-to-date plugins for Lite XL 2.0.

Here some details about the bug fixes:

- fix a bug that created a fatal error when using the command to change project
  folder or when closing all the active documents
- add a limit to avoid scaling fonts too much and fix a related invalid memory
  access for very small fonts
- fix focus problem with NagView when switching project directory
- fix error that prevented the verification of plugins versions
- fix error on X11 that caused a bug window event on exit

## [2.0] - 2021-08-16

The 2.0 version of lite contains *breaking changes* to lite, in terms of how
plugin settings are structured; any custom plugins may need to be adjusted
accordingly (see note below about plugin namespacing).

Contains the following new features:

Full PCRE (regex) support for find and replace, as well as in language syntax
definitions. Can be accessed programatically via the lua `regex` module.

A full, finalized subprocess API, using libreproc. Subprocess can be started
and interacted with using `Process.new`.

Support for multi-cursor editing. Cursors can be created by either ctrl+clicking
on the screen, or by using the keyboard shortcuts ctrl+shift+up/down to create
an additional cursor on the previous/next line.

All build systems other than meson removed.

A more organized directory structure has been implemented; in particular a docs
folder which contains C api documentation, and a resource folder which houses
all build resources.

Plugin config namespacing has been implemented. This means that instead of
using `config.myplugin.a`, to read settings, and `config.myplugin = false` to
disable plugins, this has been changed to `config.plugins.myplugin.a`, and
`config.plugins.myplugin = false` respectively. This may require changes to
your user plugin, or to any custom plugins you have.

A context menu on right click has been added.

Changes to how we deal with indentation have been implemented; in particular,
hitting home no longer brings you to the start of a line, it'll bring you to
the start of indentation, which is more in line with other editors.

Lineguide, and scale plugins moved into the core, and removed from
`lite-plugins`. This may also require you to adjust your personal plugin
folder to remove these if they're present.

In addition, there have been many other small fixes and improvements, too
numerous to list here.

## [1.16.11] - 2021-05-28

When opening directories with too many files lite-xl now keep displaying files
and directories in the treeview. The application remains functional and the
directories can be explored without using too much memory. In this operating
mode the files of the project are not indexed so the command "Core: Find File"
will act as the "Core: Open File" command.The "Project Search: Find" will work
by searching all the files present in the project directory even if they are
not indexed.

Implemented changing fonts per syntax group by @liquidev.

Example user module snippet that makes all comments italic:

```lua
local style = require "core.style"

-- italic.ttf must be provided by the user
local italic = renderer.font.load("italic.ttf", 14)
style.syntax_fonts["comment"] = italic
```

Improved indentation behavior by @adamharrison.

Fix bug with close button not working in borderless window mode.

Fix problem with normalization of filename for opened documents.

## [1.16.10] - 2021-05-22

Improved syntax highlight system thanks to @liquidev and @adamharrison.
Thanks to the new system we provide more a accurate syntax highlighting for
Lua, C and C++. Other syntax improvements contributed by @vincens2005.

Move to JetBrains Mono and Fira Sans fonts for code and UI respectively.
They are provided under the SIL Open Font License, Version 1.1.
See `doc/licenses.md` for license details.

Fixed bug with fonts and rencache module. Under very specific situations the
application was crashing due to invalid memory access.

Add documentation for keymap binding, thanks to @Janis-Leuenberger.

Added a contributors page in `doc/contributors.md`.

## [1.16.9] - 2021-05-06

Fix a bug related to nested panes resizing.

Fix problem preventing creating a new file.

## [1.16.8] - 2021-05-06

Fix application crash when using the command `core:restart`.

Improve application startup to reduce "flashing".

Move to new plugins versioning using tag `mod-version:1`.
The mod-version is a single digit version that tracks the
plugins compatibility version independently from the lite-xl
version.

For backward compatibility the tag `-- lite-xl 1.16` is considered equivalent to
`mod-version:1` so users don't need to update their plugins.

Both kind of tags can appear in new plugins in the form:

```lua
-- mod-version:1 -- lite-xl 1.16
```

where the old tag needs to appear at the end for compatibility.

## [1.16.7] - 2021-05-01

Add support for retina displays on Mac OS X.

Fix a few problems related to file paths.

## [1.16.6] - 2021-04-21

Implement a system to check the compatibility of plugins by checking a release
tag. Plugins that don't have the release tag will not be loaded.

Improve and extend the NagView with keyboard commands.
Special thanks to @takase1121 for the implementation and @liquidev for proposing
and discussing the enhancements.

Add support to build on Mac OS X and create an application bundle.
Special thanks to @mathewmariani for his lite-macos fork, the Mac OS specific
resources and his support.

Add hook function `DocView.on_text_change` so that plugin can accurately react
on document changes. Thanks to @vincens2005 for the suggestion and testing the
implementation.

Enable borderless window mode using the `config.borderless` variable.
If enable the system window's bar will be replaced by a title bar provided
by lite-xl itself.

Fix a drawing engine bug that caused increased CPU usage for drawing operations.

Add `system.set_window_opacity` function.

Add codepoint replacement API to support natively the "draw whitespaces" option.
It supersedes the `drawwhitespace` plugin. If can be configured using the
`config.draw_whitespace` boolean variable and enabled and disables using the
commands `draw-whitespace:toggle`, `draw-whitespace:enable`,
`draw-whitespace:disable`.

Improve the NagView to accept keyboard commands and introduce dialog commands.

Add hook function `Doc:on_text_change` called on document changes, to be
used by plugins.

## [1.16.5] - 2021-03-20

Hotfix for Github's issue https://github.com/franko/lite-xl/issues/122

## [1.16.4] - 2021-03-20

Add tooltips to show full file names from the tree-view.

Introduce NagView to show warning dialog about unsaved files.

Detect High-DPI displays on Linux using Xft.dpi entry from xrdb's output.

Made animations independent of framerate, and added a config setting
`config.animation_rate` for customizing the speed of animations.

Made borders between tabs look cleaner.

Fix problem with files using hard tabs.

## [1.16.2] - 2021-03-05

Implement close button for tabs.

Make the command view list of suggestion scrollable to see all the items.

Improve update/resize behavior of treeview and toolbar.

## [1.16.1] - 2021-02-25

Improve behavior of commands to move, delete and duplicate multiple lines:
no longer include the last line if it does not contain any selection.

Fix graphical artifacts when rendering some fonts like FiraSans.

Introduce the `config.transitions` boolean variable.
When false the transitions will be disabled and changes will be done immediately.
Very useful for remote sessions where visual transitions doesn't work well.

Fix many small problems related to the new toolbar and the tooptips.
Fix problem with spacing in treeview when using monospace fonts.

## [1.16] - 2021-02-19

Implement a toolbar shown in the bottom part of the tree-view.
The toolbar is especially meant for new users to give an easy, visual, access
to the more important commands.

Make the treeview actually resizable and shows the resize cursor only when panes
are actually resizable.

Add config mechanism to disable a plugin by setting
`config.<plugin-name> = false`.

Improve the "detect indent" plugin to take into account the syntax and exclude
comments for much accurate results.

Add command `root:close-all` to close all the documents currently opened.

Show the full path filename of the active document in the window's title.

Fix problem with user's module reload not always enabled.

## [1.15] - 2021-01-04

**Project directories**

Extend your project by adding more directories using the command
`core:add-directory`. To remove them use the corresponding command
`core:remove-directory`.

**Workspaces**

The workspace plugin from rxi/lite-plugins is now part of Lite XL.
In addition to the functionalities of the original plugin the extended version
will also remember the window size and position and the additional project
directories.

To not interfere with the project's files the workspace file is saved in the
personal Lite's configuration folder. On unix-like systems it will be in:
`$HOME/.config/lite-xl/ws`.

**Scrolling the Tree View**

It is now possible to scroll the tree view when there are too many visible items.

**Recognize `~` for the home directory**

As in the unix shell `~` is now used to identify the home directory.

**Files and Directories**

Add command to create a new empty directory within the project using the
command `files:create-directory`.

In addition a control-click on a project directory will prompt the user to
create a new directory inside the directory pointed.

**New welcome screen**

Show 'Lite XL' instead of 'lite' and the version number.

**Various fixes and improvements**

A few quirks previously with some of the new features have been fixed for a
better user experience.

## [1.14] - 2020-12-13

**Project Management**

Add a new command, Core: Change Project Folder, to change project directory by
staying on the same window. All the current opened documents will be closed.
The new command is associated with the keyboard combination ctrl+shit+c.

A similar command is also added, Core: Open Project Folder, with key binding
ctrl+shift+o. It will open the chosen folder in a new window.

In addition Lite XL will now remember the recently used projects across
different sessions. When invoked without arguments it will now open the project
more recently used. If a directory is specified it will behave like before and
open the directory indicated as an argument.

**Restart command**

A Core: Restart command is added to restart the editor without leaving the
current window. Very convenient when modifying the Lua code for the editor
itself.

**User's setting auto-reload**

When saving the user configuration, the user's module, the changes will be
automatically applied to the current instance.

**Bundle community provided colors schemes**

Included now in the release files the colors schemes from
github.com/rxi/lite-colors.

**Usability improvements**

Improve left and right scrolling of text to behave like other editors and
improves text selection with mouse.

**Fixes**

Correct font's rendering for full hinting mode when using subpixel antialiasing.

## [1.13] - 2020-12-06

**Rendering options for fonts**

When loading fonts with the function renderer.font.load some rendering options
can be optionally specified:

- antialiasing: grayscale or subpixel
- hinting: none, slight or full

See data/core/style.lua for the details about its utilisation.

The default remains antialiasing subpixel and hinting slight to reproduce the
behavior of previous versions.
The option grayscale with full hinting is specially interesting for crisp font
rendering without color artifacts.

**Unix-like install directories**

Use unix-like install directories for the executable and for the data directory.
The executable will be placed under $prefix/bin and the data folder will be
$prefix/share/lite-xl.

The folder $prefix is not hard-coded in the binary but is determined at runtime
as the directory such as the executable is inside $prefix/bin.

If no such $prefix exist it will fall back to the old behavior and use the
"data" folder from the executable directory.

In addtion to the `EXEDIR` global variable an additional variable is exposed,
`DATADIR`, to point to the data directory.

The old behavior using the "data" directory can be still selected at compile
time using the "portable" option. The released Windows package will use the
"data" directory as before.

**Configuration stored into the user's home directory**

Now the Lite XL user's configuration will be stored in the user's home directory
under .config/lite-xl".

The home directory is determined using the "HOME" environment variable except
on Windows wher "USERPROFILE" is used instead.

A new global variable `USERDIR` is exposed to point to the user's directory.

## [1.11] - 2020-07-05

- include changes from rxi's Lite 1.11
- fix behavior of tab to indent multiple lines
- disable auto-complete on very big files to limit memory usage
- limit project scan to a maximum number of files to limit memory usage
- list recently visited files when using "Find File" command

## [1.08] - 2020-06-14

- Subpixel font rendering, removed gamma correction
- Avoid using CPU when the editor is idle

## [1.06] - 2020-05-31

- subpixel font rendering with gamma correction

[2.1.7]: https://github.com/lite-xl/lite-xl/releases/tag/v2.1.7
[2.1.6]: https://github.com/lite-xl/lite-xl/releases/tag/v2.1.6
[2.1.5]: https://github.com/lite-xl/lite-xl/releases/tag/v2.1.5
[2.1.4]: https://github.com/lite-xl/lite-xl/releases/tag/v2.1.4
[2.1.3]: https://github.com/lite-xl/lite-xl/releases/tag/v2.1.3
[2.1.2]: https://github.com/lite-xl/lite-xl/releases/tag/v2.1.2
[2.1.1]: https://github.com/lite-xl/lite-xl/releases/tag/v2.1.1
[2.1.0]: https://github.com/lite-xl/lite-xl/releases/tag/v2.1.0
[2.0.5]: https://github.com/lite-xl/lite-xl/releases/tag/v2.0.5
[2.0.4]: https://github.com/lite-xl/lite-xl/releases/tag/v2.0.4
[2.0.3]: https://github.com/lite-xl/lite-xl/releases/tag/v2.0.3
[2.0.2]: https://github.com/lite-xl/lite-xl/releases/tag/v2.0.2
[2.0.1]: https://github.com/lite-xl/lite-xl/releases/tag/v2.0.1
[2.0]: https://github.com/lite-xl/lite-xl/releases/tag/v2.0.0
[1.16.11]: https://github.com/lite-xl/lite-xl/releases/tag/v1.16.11
[1.16.10]: https://github.com/lite-xl/lite-xl/releases/tag/v1.16.10
[1.16.9]: https://github.com/lite-xl/lite-xl/releases/tag/v1.16.9
[1.16.8]: https://github.com/lite-xl/lite-xl/releases/tag/v1.16.8
[1.16.7]: https://github.com/lite-xl/lite-xl/releases/tag/v1.16.7
[1.16.6]: https://github.com/lite-xl/lite-xl/releases/tag/v1.16.6
[1.16.5]: https://github.com/lite-xl/lite-xl/releases/tag/v1.16.5
[1.16.4]: https://github.com/lite-xl/lite-xl/releases/tag/v1.16.4
[1.16.2]: https://github.com/lite-xl/lite-xl/releases/tag/v1.16.2-lite-xl
[1.16.1]: https://github.com/lite-xl/lite-xl/releases/tag/v1.16.1-lite-xl
[1.16]: https://github.com/lite-xl/lite-xl/releases/tag/v1.16.0-lite-xl
[1.15]: https://github.com/lite-xl/lite-xl/releases/tag/v1.15-lite-xl
[1.14]: https://github.com/lite-xl/lite-xl/releases/tag/v1.14-lite-xl
[1.13]: https://github.com/lite-xl/lite-xl/releases/tag/v1.13-lite-xl
[1.11]: https://github.com/lite-xl/lite-xl/releases/tag/v1.11-lite-xl
[1.08]: https://github.com/lite-xl/lite-xl/releases/tag/v1.08-subpixel
[1.06]: https://github.com/lite-xl/lite-xl/releases/tag/1.06-subpixel-rc1
