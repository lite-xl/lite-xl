# lite

![screenshot](https://user-images.githubusercontent.com/3920290/81471642-6c165880-91ea-11ea-8cd1-fae7ae8f0bc4.png)

## Overview
Lite is a lightweight text editor written mostly in Lua — it aims to provide
something practical, pretty, *small* and fast, implemented as simply as
possible; easy to modify and extend, or to use without doing either.

Lite XL is based on the Lite editor itself and provide some enhancements
while remaining perfectly compatible with Lite.


## Getting Started
Lite works using a *project directory* — this is the directory where your
project's code and other data resides.

To open lite with a specific project directory the directory name can be passed
as a command-line argument *(`.` can be passed to use the current directory)* or
the directory can be dragged onto either the lite executable or a running
instance of lite.

Once started the project directory can be changed using the command
`core:change-project-folder`. The command will close all the documents
currently opened and switch to the new project directory.

If you want to open a project directory in a new window the command
`core:open-project-folder` will open a new editor window with the selected
project directory.

The main way of opening files in lite is through the `core:find-file` command
— this provides a fuzzy finder over all of the project's files and can be
opened using the **`ctrl+p`** shortcut by default.

Commands can be run using keyboard shortcuts, or by using the `core:find-command`
command bound to **`ctrl+shift+p`** by default. For example, pressing
`ctrl+shift+p` and typing `newdoc` then pressing `return` would open a new
document. The current keyboard shortcut for a command can be seen to the right
of the command name on the command finder, thus to find the shortcut for a command
`ctrl+shift+p` can be pressed and the command name typed.


## User Module
lite can be configured through use of the user module. The user module can be
used for changing options in the config module, adding additional key bindings,
loading custom color themes, modifying the style or changing any other part of
lite to your personal preference.

The user module is loaded by lite when the application starts, after the plugins
have been loaded.

The user module can be modified by running the `core:open-user-module` command
or otherwise directly opening the `$HOME/.config/lite-xl/init.lua` file.

On Windows, the variable `$USERPROFILE` will be used instead of
`$HOME`.

Please note that Lite XL differs from the standard Lite editor for the location
of the user's module.

## Project Module
The project module is an optional module which is loaded from the current
project's directory when lite is started. Project modules can be useful for
things like adding custom commands for project-specific build systems, or
loading project-specific plugins.

The project module is loaded by lite when the application starts, after both the
plugins and user module have been loaded.

The project module can be edited by running the `core:open-project-module`
command — if the module does not exist for the current project when the
command is run it will be created.


## Commands
Commands in lite are used both through the command finder (`ctrl+shift+p`) and
by lite's keyboard shortcut system. Commands consist of 3 components:
* **Name** — The command name in the form of `namespace:action-name`, for
  example: `doc:select-all`
* **Predicate** — A function that returns true if the command can be ran, for
  example, for any document commands the predicate checks whether the active
  view is a document
* **Function** — The function which performs the command itself

Commands can be added using the `command.add` function provided by the
`core.command` module:
```lua
local core = require "core"
local command = require "core.command"

command.add("core.docview", {
  ["doc:save"] = function()
    core.active_view.doc:save()
    core.log("Saved '%s', core.active_view.doc.filename)
  end
})
```

Commands can be performed programatically (eg. from another command or by your
user module) by calling the `command.perform` function after requiring the
`command` module:
```lua
local command = require "core.command"
command.perform "core:quit"
```


## Keymap
All keyboard shortcuts in lite are handled by the `core.keymap` module. A key
binding in lite maps a "stroke" (eg. `ctrl+q`) to one or more commands (eg.
`core:quit`). When the shortcut is pressed lite will iterate each command
assigned to that key and run the *predicate function* for that command — if the
predicate passes it stops iterating and runs the command.

An example of where this used is the default binding of the `tab` key:
``` lua
  ["tab"] = { "command:complete", "doc:indent" },
```
When tab is pressed the `command:complete` command is attempted which will only
succeed if the command-input at the bottom of the window is active. Otherwise
the `doc:indent` command is attempted which will only succeed if we have a
document as our active view.

A new mapping can be added by your user module as follows:
```lua
local keymap = require "core.keymap"
keymap.add { ["ctrl+q"] = "core:quit" }
```


## Plugins
Plugins in lite are normal lua modules and are treated as such — no
complicated plugin manager is provided, and, once a plugin is loaded, it is never
expected be to have to unload itself.

To install a plugin simply drop it in the `plugins` directory in the user
module directory.
When Lite XL starts it will first load the plugins included in the data directory
and will then loads the plugins located in the user module directory.

To uninstall a plugin the
plugin file can be deleted — any plugin (including those included with lite's
default installation) can be deleted to remove its functionality.

If you want to load a plugin only under a certain circumstance (for example,
only on a given project) the plugin can be placed somewhere other than the
`plugins` directory so that it is not automatically loaded. The plugin can
then be loaded manually as needed by using the `require` function.

Plugins can be downloaded from the [plugins repository](https://github.com/rxi/lite-plugins).


## Restarting the editor

If you modifies the user configuration file or some of the Lua implementation files you may
restart the editor using the command `core:restart`.
All the application will be restarting by keeping the window that is already in use.


## Color Themes
Colors themes in lite are lua modules which overwrite the color fields of lite's
`core.style` module.
Pre-defined color methods are located in the `colors` folder in the data directory.
Additional color themes can be installed in the user's directory in a folder named
`colors`.

A color theme can be set by requiring it in your user module:
```lua
core.reload_module "colors.winter"
```

In the Lite editor the function `require` is used instead of `core.reload_module`.
In Lite XL `core.reload_module` should be used to ensure that the color module
is actually reloaded when saving the user's configuration file.

Color themes can be downloaded from the [color themes repository](https://github.com/rxi/lite-colors).
They are included with Lite XL release packages.

