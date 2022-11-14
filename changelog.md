# Changes Log

## [2.1.0] - 202X-XX-XX

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

### Performance Improvements

* [Load space metrics only when creating font](https://github.com/lite-xl/lite-xl/pull/1032)

* [Performance improvement](https://github.com/lite-xl/lite-xl/pull/883)
  of detect indent plugin.

* Improve performance of
  [ren_draw_rect](https://github.com/lite-xl/lite-xl/pull/935).

* Improved [tokenizer performance](https://github.com/lite-xl/lite-xl/pull/896).

* drawwhitespace: [Cache whitespace location](https://github.com/lite-xl/lite-xl/pull/1030)

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

* The `font.set_size` function was dropped in favor of `font.copy`.

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
    predicate, name, alignment, getitem, command, pos, tooltip
  ) end
  ```

  **Example:**
  ```lua
  core.status_view:add_item(
    nil,
    "status:memory-usage",
    StatusView.Item.RIGHT,
    function()
      return {
        style.text,
        string.format(
          "%.2f MB",
          (math.floor(collectgarbage("count") / 10.24) / 100)
        )
      }
    end,
    nil,
    1,
    "lua memory usage"
  ).separator = core.status_view.separator2
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
