Lite XL is following closely [rxi/lite](https://github.com/rxi/lite) but with some enhancements.

This files document the differences between Lite XL and rxi/lite for each version.

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
