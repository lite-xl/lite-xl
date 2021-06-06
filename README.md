# Lite XL

[![Discord Badge Image]](https://discord.gg/RWzqC3nx7K)

![screenshot-dark]

A lightweight text editor written in Lua, adapted from [lite].

* **[Get Lite XL]** — Download for Windows, Linux and Mac OS (notarized app).
* **[Get plugins]** — Add additional functionality, adapted for Lite XL.
* **[Get color themes]** — Add additional colors themes.

Please refer to our [website] for the user and developer documentation,
including [build] instructions.

Lite XL has support for high DPI display on Windows and Linux and,
since 1.16.7 release, it supports **retina displays** on macOS.

Please note that Lite XL is compatible with lite for most plugins and all color themes.
We provide a separate lite-plugins repository for Lite XL, because in some cases
some adaptations may be needed to make them work better with Lite XL.
The repository with modified plugins is https://github.com/franko/lite-plugins.

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

## Contributing

Any additional functionality that can be added through a plugin should be done
as a plugin, after which a pull request to the [plugins repository] can be made.

If the plugin uses any Lite XL-specific functionality,
please open a pull request to the [Lite XL plugins repository].

Pull requests to improve or modify the editor itself are welcome.

## Licenses

This project is free software; you can redistribute it and/or modify it under
the terms of the MIT license. See [LICENSE] for details.

See the [licenses] file for details on licenses used by the required dependencies.


[Discord Badge Image]:        https://img.shields.io/discord/847122429742809208?label=discord&logo=discord
[screenshot-dark]:            https://user-images.githubusercontent.com/433545/111063905-66943980-84b1-11eb-9040-3876f1133b20.png
[lite]:                       https://github.com/rxi/lite
[website]:                    https://lite-xl.github.io
[build]:                      https://lite-xl.github.io/en/build
[Get Lite XL]:                https://github.com/franko/lite-xl/releases/latest
[Get plugins]:                https://github.com/franko/lite-plugins
[Get color themes]:           https://github.com/rxi/lite-colors
[changelog]:                  https://github.com/franko/lite-xl/blob/master/changelog.md
[Lite XL plugins repository]: https://github.com/franko/lite-plugins
[plugins repository]:         https://github.com/rxi/lite-plugins
[colors repository]:          https://github.com/rxi/lite-colors
[LICENSE]:                    LICENSE
[licenses]:                   licenses/licenses.md
