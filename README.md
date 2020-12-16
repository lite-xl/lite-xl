# Lite XL

![screenshot-dark](https://user-images.githubusercontent.com/433545/85227778-b42abc80-b3df-11ea-9dd3-e788f6c71882.png)

A lightweight text editor written in Lua, adapted from [Lite](https://github.com/rxi/lite)

* **[Get Lite XL](https://github.com/franko/lite-xl/releases/latest)** — Download
  for Windows and Linux
* **[Get started](doc/usage.md)** — A quick overview on how to get started
* **[Get plugins](https://github.com/franko/lite-plugins)** — Add additional
  functionality, adapted for Lite XL
* **[Get color themes](https://github.com/rxi/lite-colors)** — Add additional colors
  themes

Please note that Lite XL is compatible with Lite for all the plugins and color themes.
Yet we provide a specific lite-plugins directory for Lite XL because in some cases some adaptations may be needed to make them work better with Lite XL.
The address for modified plugins is http://github.com/franko/lite-plugins.
Currently only the "workspace" plugin needs a minor adjustment to restore the workspace when the command `core:restart` is used.

The changes and differences between Lite XL and rxi/lite are listed in the [changelog](https://github.com/franko/lite-xl/blob/master/changelog.md).

## Overview
Lite XL is derived from Lite. It is a lightweight text editor written mostly in Lua — it aims to provide
something practical, pretty, *small* and fast easy to modify and extend, or to use without doing either.

The aim of Lite XL compared to Lite is to be more user friendly, improve the quality of the font rendering and reduce CPU usage.

## Customization
Additional functionality can be added through plugins which are available from
the [plugins repository](https://github.com/rxi/lite-plugins) or from the [plugin repository adapted to Lite XL](https://github.com/franko/lite-plugins); additional color
themes can be found in the [colors repository](https://github.com/rxi/lite-colors).
The editor can be customized by making changes to the
[user module](data/user/init.lua).

## Building

You can build the project yourself using the Meson build.

In addition the script `build-packages.sh` can be used to compile Lite XL and create a package adapted to the OS, Linux, Windows or Mac OS X.

The following libraries are required:

- freetype2
- SDL2

The libraries libagg and Lua 5.2 are optional.
If they are not found they will be automatically downloaded and compiled by the Meson build system.
Otherwise, if they are present they will be used to compile Lite XL.

On a debian based systems the required library and Meson can be installed using the commands:

```sh
# To install the required libraries:
sudo apt install libfreetype6-dev libsdl2-dev

# To install Meson:
sudo apt install meson
# or pip3 install --user meson
```

To build Lite XL with Meson use the commands:
```sh
meson setup build
meson compile -C build
meson install -C build
```

When performing the "meson setup" command you may enable the "portable" option.

If this latter is enabled Lite XL is built to use a "data" and a "user" directory
from the same directory of the executable.
If "portable" is not enabled (this is the default) Lite XL will use unix-like
directory locations.
In this case the "data" directory will be `$prefix/share/lite-xl` and the "user"
directory will be `$HOME/.config/lite-xl`.
The `$prefix` is determined as the directory such as `$prefix/bin` corresponds to
the location of the executable.
The `$HOME` is determined from the corresponding environment variable.
As a special case on Windows the variable `$USERPROFILE` will be used instead.

If you want to install Lite XL on Windows or Mac OS X we suggest to use the script `build-packages.sh`:

```sh
bash build-packages.sh <version> <arch>

# In alternative the -portable option can be used like below:
# bash build-packages.sh -portable <version> <arch>
```

It will run meson and create a Zip file that can be easily installed or uninstalled.

Please note the, while compiling Lite XL on Mac OS X should work Mac OS X
is not currently supported.

## Contributing
Any additional functionality that can be added through a plugin should be done
so as a plugin, after which a pull request to the
[plugins repository](https://github.com/rxi/lite-plugins) can be made.

Pull requests to improve or modify the editor itself are welcome.

## License
This project is free software; you can redistribute it and/or modify it under
the terms of the MIT license. See [LICENSE](LICENSE) for details.
