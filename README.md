# Lite XL

[![CI]](https://github.com/lite-xl/lite-xl/actions/workflows/build.yml)
[![Discord Badge Image]](https://discord.gg/RWzqC3nx7K)

![screenshot-dark]

A lightweight text editor written in Lua, adapted from [lite].

* **[Get Lite XL]** — Download for Windows, Linux and Mac OS.
* **[Get plugins]** — Add additional functionality, adapted for Lite XL.
* **[Get color themes]** — Add additional colors themes.

Please refer to our [website] for the user and developer documentation,
including [build] instructions details. A quick build guide is described below.

Lite XL has support for high DPI display on Windows and Linux and,
since 1.16.7 release, it supports **retina displays** on macOS.

Please note that Lite XL is compatible with lite for most plugins and all color themes.
We provide a separate lite-xl-plugins repository for Lite XL, because in some cases
some adaptations may be needed to make them work better with Lite XL.
The repository with modified plugins is https://github.com/lite-xl/lite-xl-plugins.

The changes and differences between Lite XL and rxi/lite are listed in the
[changelog].

## Overview

Lite XL is derived from lite.
It is a lightweight text editor written mostly in Lua — it aims to provide
something practical, pretty, *small* and fast easy to modify and extend,
or to use without doing either.

The aim of Lite XL compared to lite is to be more user friendly,
improve the quality of font rendering, and reduce CPU usage.

## Customization

Additional functionality can be added through plugins which are available in
the [plugins repository] or in the [Lite XL plugins repository].

Additional color themes can be found in the [colors repository].
These color themes are bundled with all releases of Lite XL by default.

## Quick Build Guide

If you compile Lite XL yourself, it is recommended to use the script
`build-packages.sh`:

```sh
bash build-packages.sh -h
```

The script will run Meson and create a tar compressed archive with the application or,
for Windows, a zip file. Lite XL can be easily installed
by unpacking the archive in any directory of your choice.

Otherwise the following is an example of basic commands if you want to customize
the build:

```sh
meson setup --buildtype=release --prefix <prefix> build
meson compile -C build
DESTDIR="$(pwd)/lite-xl" meson install --skip-subprojects -C build
```

where `<prefix>` might be one of `/`, `/usr` or `/opt`, the default is `/`.
To build a bundle application on macOS:

```sh
meson setup --buildtype=release --Dbundle=true --prefix / build
meson compile -C build
DESTDIR="$(pwd)/Lite XL.app" meson install --skip-subprojects -C build
```

Please note that the package is relocatable to any prefix and the option prefix
affects only the place where the application is actually installed.

## Installing Prebuilt

Head over to [releases](https://github.com/lite-xl/lite-xl/releases) and download the version for your operating system.

### Linux

Unzip the file and `cd` into the `lite-xl` directory:

```sh
tar -xzf <file>
cd lite-xl
```

To run lite-xl without installing:
```sh
cd bin
./lite-xl
```

To install lite-xl copy files over into appropriate directories:

```sh
mkdir -p $HOME/.local/bin && cp bin/lite-xl $HOME/.local/bin
cp -r share $HOME/.local
```

If `$HOME/.local/bin` is not in PATH:

```sh
echo -e 'export PATH=$PATH:$HOME/.local/bin' >> $HOME/.bashrc
```

To get the icon to show up in app launcher:

```sh
xdg-desktop-menu forceupdate
```

You may need to logout and login again to see icon in app launcher.

To uninstall just run:

```sh
rm -f $HOME/.local/bin/lite-xl
rm -rf $HOME/.local/share/icons/hicolor/scalable/apps/lite-xl.svg \
          $HOME/.local/share/applications/org.lite_xl.lite_xl.desktop \
          $HOME/.local/share/metainfo/org.lite_xl.lite_xl.appdata.xml \
          $HOME/.local/share/lite-xl
```


## Contributing

Any additional functionality that can be added through a plugin should be done
as a plugin, after which a pull request to the [Lite XL plugins repository] can be made.

Pull requests to improve or modify the editor itself are welcome.

## Licenses

This project is free software; you can redistribute it and/or modify it under
the terms of the MIT license. See [LICENSE] for details.

See the [licenses] file for details on licenses used by the required dependencies.


[CI]:                         https://github.com/lite-xl/lite-xl/actions/workflows/build.yml/badge.svg
[Discord Badge Image]:        https://img.shields.io/discord/847122429742809208?label=discord&logo=discord
[screenshot-dark]:            https://user-images.githubusercontent.com/433545/111063905-66943980-84b1-11eb-9040-3876f1133b20.png
[lite]:                       https://github.com/rxi/lite
[website]:                    https://lite-xl.com
[build]:                      https://lite-xl.com/en/documentation/build/
[Get Lite XL]:                https://github.com/lite-xl/lite-xl/releases/latest
[Get plugins]:                https://github.com/lite-xl/lite-xl-plugins
[Get color themes]:           https://github.com/lite-xl/lite-xl-colors
[changelog]:                  https://github.com/lite-xl/lite-xl/blob/master/changelog.md
[Lite XL plugins repository]: https://github.com/lite-xl/lite-xl-plugins
[plugins repository]:         https://github.com/rxi/lite-plugins
[colors repository]:          https://github.com/lite-xl/lite-xl-colors
[LICENSE]:                    LICENSE
[licenses]:                   licenses/licenses.md
