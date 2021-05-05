# Lite XL

![screenshot-dark](https://user-images.githubusercontent.com/433545/111063905-66943980-84b1-11eb-9040-3876f1133b20.png)

A lightweight text editor written in Lua, adapted from [lite](https://github.com/rxi/lite)

* **[Get Lite XL](https://github.com/franko/lite-xl/releases/latest)** — Download
  for Windows, Linux and Mac OS (notarized app).
* **[Get started](doc/usage.md)** — A quick overview on how to get started
* **[Get plugins](https://github.com/franko/lite-plugins)** — Add additional
  functionality, adapted for Lite XL
* **[Get color themes](https://github.com/rxi/lite-colors)** — Add additional colors
  themes

Lite XL has support for high DPI display on Windows and Linux and, since 1.16.7 release, it supports **retina displays** on Mac OS.

Please note that Lite XL is compatible with lite for most plugins and all color themes.
We provide a separate lite-plugins repository for Lite XL, because in some cases some adaptations may be needed to make them work better with Lite XL.
The repository with modified plugins is http://github.com/franko/lite-plugins.

The changes and differences between Lite XL and rxi/lite are listed in the [changelog](https://github.com/franko/lite-xl/blob/master/changelog.md).

## Overview

Lite XL is derived from lite. It is a lightweight text editor written mostly in Lua — it aims to provide
something practical, pretty, *small* and fast easy to modify and extend, or to use without doing either.

The aim of Lite XL compared to lite is to be more user friendly, improve the quality of font rendering, and reduce CPU usage.

## Customization
Additional functionality can be added through plugins which are available in
the [plugins repository](https://github.com/rxi/lite-plugins) or in the [Lite XL-specific plugins repository](https://github.com/franko/lite-plugins).

Additional color themes can be found in the [colors repository](https://github.com/rxi/lite-colors).
These color themes are bundled with all releases of Lite XL by default.

The editor can be customized by making changes to the [user module](data/user/init.lua).

## Building

You can build Lite XL yourself using Meson.

In addition, the `build-packages.sh` script can be used to compile Lite XL and create an OS-specific package for Linux, Windows or Mac OS.

The following libraries are required:

- freetype2
- SDL2

The following libraries are **optional**:

- libagg
- Lua 5.2

If they are not found, they will be downloaded and compiled by Meson.
Otherwise, if they are present, they will be used to compile Lite XL.

On Debian-based systems the required libraries and Meson can be installed using the following commands:

```sh
# To install the required libraries:
sudo apt install libfreetype6-dev libsdl2-dev

# To install Meson:
sudo apt install meson
# or pip3 install --user meson
```

To build Lite XL with Meson the commands below can be used:
```sh
meson setup --buildtype=release build
meson compile -C build
meson install -C build
```

If you are using a version of Meson below 0.54 you need to use diffent commands to compile and install:

```sh
meson setup --buildtype=release build
ninja -C build
ninja -C build install
```

When performing the `meson setup` command you may enable the `-Dportable=true` option to specify whether files should be installed as in a portable application.

If `portable` is enabled, Lite XL is built to use a `data` directory placed next to the executable.
Otherwise, Lite XL will use unix-like directory locations.
In this case, the `data` directory will be `$prefix/share/lite-xl` and the executable will be located in `$prefix/bin`.
`$prefix` is determined when the application starts as a directory such that `$prefix/bin` corresponds to the location of the executable.

The `user` directory does not depend on the `portable` option and will always be `$HOME/.config/lite-xl`.
`$HOME` is determined from the corresponding environment variable.
As a special case on Windows the variable `$USERPROFILE` will be used instead.

If you compile Lite XL yourself, it is recommended to use the script `build-packages.sh`:

```sh
bash build-packages.sh <arch>
```

The script will run Meson and create a zip file with the application or, for linux, a tar compressed archive.
Lite XL can be easily installed by unpacking the archive in any directory of your choice.

On Windows two packages will be created, one called "portable" using the "data" folder next to the executable and
the other one using a unix-like file layout. Both packages works correctly. The one with unix-like file layout
is meant for people using a unix-like shell and the command line.

Please note that there aren't any hard-coded directories in the executable, so that the
package can be extracted and used in any directory.

Mac OS X is fully supported and a notarized app disk image is provided in the release page.
In addition the application can be compiled using the generic instructions given above.

## Contributing
Any additional functionality that can be added through a plugin should be done
as a plugin, after which a pull request to the
[plugins repository](https://github.com/rxi/lite-plugins) can be made.

If the plugin uses any Lite XL-specific functionality, please open a pull request to the
[Lite XL plugins repository](https://github.com/franko/lite-plugins).

Pull requests to improve or modify the editor itself are welcome.

## License
This project is free software; you can redistribute it and/or modify it under
the terms of the MIT license. See [LICENSE](LICENSE) for details.
