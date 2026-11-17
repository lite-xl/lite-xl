# Lite XL

[![CI]](https://github.com/lite-xl/lite-xl/actions/workflows/build.yml)
[![Discord Badge Image]](https://discord.gg/UQKnzBhY5H)

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

Lite XL is derived from [lite].
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

To compile Lite XL yourself, you must have the following dependencies installed
via your desired package manager, or manually.

### Prerequisites

- Meson (>=0.63)
- Ninja
- SDL2
- PCRE2
- FreeType2
- Lua 5.4
- A working C compiler (GCC / Clang / MSVC)

SDL2, PCRE2, FreeType2 and Lua will be downloaded by Meson
if `--wrap-mode=forcefallback` or `--wrap-mode=default` is specified.

> [!NOTE]
> MSVC is used in the CI, but MSVC-compiled binaries are not distributed officially
> or tested extensively for bugs.

On Linux, you may install the following dependencies for the SDL2 X11 and/or Wayland backend to work properly:

- `libX11-devel`
- `libXi-devel`
- `libXcursor-devel`
- `libxkbcommon-devel`
- `libXrandr-devel`
- `wayland-devel`
- `wayland-protocols-devel`
- `dbus-devel`
- `ibus-devel`

The following command can be used to install the dependencies in Ubuntu:

```sh
apt-get install python3.8 python3-pip build-essential git cmake wayland-protocols libsdl2-dev
pip3 install meson ninja
```

Please refer to [lite-xl-build-box] for a working Linux build environment used to package official Lite XL releases.

On macOS, you must install bash via Brew, as the default bash version on macOS is antiquated
and may not run the build script correctly.

### Building

You can use `scripts/build.sh` to set up Lite XL and build it.

```sh
$ bash build.sh --help
# Usage: scripts/build.sh <OPTIONS>
# 
# Available options:
# 
# -b --builddir DIRNAME         Sets the name of the build directory (not path).
#                               Default: 'build-x86_64-linux'.
#    --debug                    Debug this script.
# -f --forcefallback            Force to build dependencies statically.
# -h --help                     Show this help and exit.
# -d --debug-build              Builds a debug build.
# -p --prefix PREFIX            Install directory prefix. Default: '/'.
# -B --bundle                   Create an App bundle (macOS only)
# -A --addons                   Add in addons
# -P --portable                 Create a portable binary package.
# -r --reconfigure              Tries to reuse the meson build directory, if possible.
#                               Default: Deletes the build directory and recreates it.
# -O --pgo                      Use profile guided optimizations (pgo).
#                               macOS: disabled when used with --bundle,
#                               Windows: Implicit being the only option.
#    --cross-platform PLATFORM  Cross compile for this platform.
#                               The script will find the appropriate
#                               cross file in 'resources/cross'.
#    --cross-arch ARCH          Cross compile for this architecture.
