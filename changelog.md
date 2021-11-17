This files document the changes done in Lite XL for each release.

### 2.0.2

Fix problem project directory when starting the application from Launcher on macOS.

Improved LogView. Entries can now be expanded and there is a context menu to copy the item's content.

Change the behavior of `ctrl+d` to add a multi-cursor selection to the next occurrence.
The old behavior to move the selection to the next occurrence is now done using the shortcut `ctrl+f3`.

Added a command to create a multi-cursor with all the occurrences of the current selection.
Activated with the shortcut `ctrl+shift+l`.

Fix problem when trying to close an unsaved new document.

No longer shows an error for the `-psn` argument passed to the application on macOS.

Fix `treeview:open-in-system` command on Windows.

Fix rename command to update name of document if opened.

Improve the find and replace dialog so that previously used expressions can be recalled
using "up" and "down" keys.

Build package script rewrite with many improvements.

Use bigger fonts by default.

Other minor improvements and fixes.

With many thanks to the contributors: @adamharrison, @takase1121, @Guldoman, @redtide, @Timofffee, @boppyt, @Jan200101.

### 2.0.1

Fix a few bugs and we mandate the mod-version 2 for plugins.
This means that users should ensure they have up-to-date plugins for Lite XL 2.0.

Here some details about the bug fixes:

- fix a bug that created a fatal error when using the command to change project folder or when closing all the active documents
- add a limit to avoid scaling fonts too much and fix a related invalid memory access for very small fonts
- fix focus problem with NagView when switching project directory
- fix error that prevented the verification of plugins versions
- fix error on X11 that caused a bug window event on exit

### 2.0

The 2.0 version of lite contains *breaking changes* to lite, in terms of how plugin settings are structured;
any custom plugins may need to be adjusted accordingly (see note below about plugin namespacing).

Contains the following new features:

Full PCRE (regex) support for find and replace, as well as in language syntax definitions. Can be accessed 
programatically via the lua `regex` module.

A full, finalized subprocess API, using libreproc. Subprocess can be started and interacted with using
`Process.new`.

Support for multi-cursor editing. Cursors can be created by either ctrl+clicking on the screen, or by using
the keyboard shortcuts ctrl+shift+up/down to create an additional cursor on the previous/next line.

All build systems other than meson removed.

A more organized directory structure has been implemented; in particular a docs folder which contains C api
documentation, and a resource folder which houses all build resources.

Plugin config namespacing has been implemented. This means that instead of using `config.myplugin.a`, 
to read settings, and `config.myplugin = false` to disable plugins, this has been changed to 
`config.plugins.myplugin.a`, and `config.plugins.myplugin = false` repsectively. This may require changes to
your user plugin, or to any custom plugins you have.

A context menu on right click has been added.

Changes to how we deal with indentation have been implemented; in particular, hitting home no longer brings you
to the start of a line, it'll bring you to the start of indentation, which is more in line with other editors.

Lineguide, and scale plugins moved into the core, and removed from `lite-plugins`. This may also require you to 
adjust your personal plugin folder to remove these if they're present.

In addition, there have been many other small fixes and improvements, too numerous to list here.

### 1.16.11

When opening directories with too many files lite-xl now keep diplaying files and directories in the treeview.
The application remains functional and the directories can be explored without using too much memory.
In this operating mode the files of the project are not indexed so the command "Core: Find File" will act as the "Core: Open File" command.
The "Project Search: Find" will work by searching all the files present in the project directory even if they are not indexed.

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

### 1.16.10

Improved syntax highlight system thanks to @liquidev and @adamharrison.
Thanks to the new system we provide more a accurate syntax highlighting for Lua, C and C++.
Other syntax improvements contributed by @vincens2005.

Move to JetBrains Mono and Fira Sans fonts for code and UI respectively.
Thet are provided under the SIL Open Font License, Version 1.1.
See `doc/licenses.md` for license details.

Fixed bug with fonts and rencache module.
Under very specific situations the application was crashing due to invalid memory access.

Add documentation for keymap binding, thanks to @Janis-Leuenberger.

Added a contributors page in `doc/contributors.md`.

### 1.16.9

Fix a bug related to nested panes resizing.

Fix problem preventing creating a new file.

### 1.16.8

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

### 1.16.7

Add support for retina displays on Mac OS X.

Fix a few problems related to file paths.

### 1.16.6

Implement a system to check the compatibility of plugins by checking a release tag.
Plugins that don't have the release tag will not be loaded.

Improve and extend the NagView with keyboard commands.
Special thanks to @takase1121 for the implementation and @liquidev for proposing and
discussing the enhancements.

Add support to build on Mac OS X and create an application bundle.
Special thanks to @mathewmariani for his lite-macos fork, the Mac OS specific
resources and his support.

Add hook function `DocView.on_text_change` so that plugin can accurately react on document changes.
Thanks to @vincens2005 for the suggestion and testing the implementation.

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

Add hook function `Doc:on_text_change` called on document changes, to be used by plugins.

### 1.16.5

Hotfix for Github's issue https://github.com/franko/lite-xl/issues/122

### 1.16.4

Add tooltips to show full file names from the tree-view.

Introduce NagView to show warning dialog about unsaved files.

Detect High-DPI displays on Linux using Xft.dpi entry from xrdb's output.

Made animations independent of framerate, and added a config setting
`config.animation_rate` for customizing the speed of animations.

Made borders between tabs look cleaner.

Fix problem with files using hard tabs.

### 1.16.2

Implement close button for tabs.

Make the command view list of suggestion scrollable to see all the items.

Improve update/resize behavior of treeview and toolbar.

### 1.16.1

Improve behavior of commands to move, delete and duplicate multiple lines:
no longer include the last line if it does not contain any selection.

Fix graphical artefacts when rendering some fonts like FiraSans.

Introduce the `config.transitions` boolean variable.
When false the transitions will be disabled and changes will be done immediately.
Very useful for remote sessions where visual transitions doesn't work well.

Fix many small problems related to the new toolbar and the tooptips.
Fix problem with spacing in treeview when using monospace fonts.

### 1.16

Implement a toolbar shown in the bottom part of the tree-view.
The toolbar is especially meant for new users to give an easy, visual, access
to the more important commands.

Make the treeview actually resizable and shows the resize cursor only when panes
are actually resizable.

Add config mechanism to disable a plugin by setting
`config.<plugin-name> = false`.

Improve the "detect indent" plugin to take into account the syntax and exclude comments
for much accurate results.

Add command `root:close-all` to close all the documents currently opened.

Show the full path filename of the active document in the window's title.

Fix problem with user's module reload not always enabled.

### 1.15

**Project directories**

Extend your project by adding more directories using the command `core:add-directory`.
To remove them use the corresponding command `core:remove-directory`.

**Workspaces**

The workspace plugin from rxi/lite-plugins is now part of Lite XL.
In addition to the functionalities of the original plugin the extended version will
also remember the window size and position and the additonal project directories.
To not interfere with the project's files the workspace file is saved in the personal
Lite's configuration folder.
On unix-like systems it will be in: `$HOME/.config/lite-xl/ws`.

**Scrolling the Tree View**

It is now possible to scroll the tree view when there are too many visible items.

**Recognize `~` for the home directory**

As in the unix shell `~` is now used to identify the home directory.

**Files and Directories**

Add command to create a new empty directory within the project using the command
`files:create-directory`.
In addition a control-click on a project directory will prompt the user to create
a new directory inside the directory pointed.

**New welcome screen**

Show 'Lite XL' instead of 'lite' and the version number.

**Various fixes and improvements**

A few quirks previously with some of the new features have been fixed for a better user experience.

### 1.14

**Project Management**

Add a new command, Core: Change Project Folder, to change project directory by staying on the same window.
All the current opened documents will be closed.
The new command is associated with the keyboard combination ctrl+shit+c.

A similar command is also added, Core: Open Project Folder, with key binding ctrl+shift+o.
It will open the chosen folder in a new window.

In addition Lite XL will now remember the recently used projects across different sessions.
When invoked without arguments it will now open the project more recently used.
If a directory is specified it will behave like before and open the directory indicated as an argument.

**Restart command**

A Core: Restart command is added to restart the editor without leaving the current window.
Very convenient when modifying the Lua code for the editor itself.

**User's setting auto-reload**

When saving the user configuration, the user's module, the changes will be automatically applied to the
current instance.

**Bundle community provided colors schemes**

Included now in the release files the colors schemes from github.com/rxi/lite-colors.

**Usability improvements**

Improve left and right scrolling of text to behave like other editors and improves text selection with mouse.

**Fixes**

Correct font's rendering for full hinting mode when using subpixel antialiasing.

### 1.13

**Rendering options for fonts**

When loading fonts with the function renderer.font.load some rendering options can
be optionally specified:

- antialiasing: grayscale or subpixel
- hinting: none, slight or full

See data/core/style.lua for the details about its utilisation.

The default remains antialiasing subpixel and hinting slight to reproduce the
behavior of previous versions.
The option grayscale with full hinting is specially interesting for crisp font rendering
without color artifacts.

**Unix-like install directories**

Use unix-like install directories for the executable and for the data directory.
The executable will be placed under $prefix/bin and the data folder will be
$prefix/share/lite-xl.
The folder $prefix is not hard-coded in the binary but is determined at runtime
as the directory such as the executable is inside $prefix/bin.
If no such $prefix exist it will fall back to the old behavior and use the "data"
folder from the executable directory.

In addtion to the `EXEDIR` global variable an additional variable is exposed, `DATADIR`,
to point to the data directory.

The old behavior using the "data" directory can be still selected at compile time
using the "portable" option. The released Windows package will use the "data"
directory as before.

**Configuration stored into the user's home directory**

Now the Lite XL user's configuration will be stored in the user's home directory under
".config/lite-xl".
The home directory is determined using the "HOME" environment variable except on Windows
wher "USERPROFILE" is used instead.

A new global variable `USERDIR` is exposed to point to the user's directory.

### 1.11

- include changes from rxi's Lite 1.11
- fix behavior of tab to indent multiple lines
- disable auto-complete on very big files to limit memory usage
- limit project scan to a maximum number of files to limit memory usage
- list recently visited files when using "Find File" command

### 1.08

- Subpixel font rendering, removed gamma correction
- Avoid using CPU when the editor is idle

### 1.06

- subpixel font rendering with gamma correction
