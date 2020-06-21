# Lite XL

![screenshot-dark](https://user-images.githubusercontent.com/433545/85227778-b42abc80-b3df-11ea-9dd3-e788f6c71882.png)

A lightweight text editor written in Lua, adapted from [Lite](https://github.com/rxi/lite)

* **[Get lite](https://github.com/franko/lite-xl/releases/latest)** — Download
  for Windows and Linux
* **[Get plugins](https://github.com/rxi/lite-plugins)** — Add additional
  functionality
* **[Get color themes](https://github.com/rxi/lite-colors)** — Add additional colors
  themes

## Overview
Lite XL is a lightweight text editor written mostly in Lua — it aims to provide
something practical, pretty, *small* and fast easy to modify and extend, or to use without doing either.

The aim of Lite XL compared to Lite is to be more user friendly, improve the quality of the font rendering and reduce CPU usage.

## Customization
Additional functionality can be added through plugins which are available from
the [plugins repository](https://github.com/rxi/lite-plugins); additional color
themes can be found in the [colors repository](https://github.com/rxi/lite-colors).
The editor can be customized by making changes to the
[user module](data/user/init.lua).

## Building
You can build the project yourself on Linux using the provided `build.sh`
script or using the Meson build.

The following libraries are required:

- freetype2
- libagg
- SDL2
- Lua 5.2

On a debian based system the required library and Meson can be installed using the commands:

```sh
# To install the required libraries:
sudo apt install libfreetype6-dev libagg-dev libsdl2-dev liblua5.2-dev

# To install Meson:
sudo apt install meson
# or pip3 install --user meson
```
To build Lite XL with Meson use the commands:
```sh
# configure
meson setup build

# build
ninja -C build

# install
ninja -C build install
```
## Contributing
Any additional functionality that can be added through a plugin should be done
so as a plugin, after which a pull request to the
[plugins repository](https://github.com/rxi/lite-plugins) can be made.

Pull requests to improve or modify the editor itself are welcome.

## License
This project is free software; you can redistribute it and/or modify it under
the terms of the MIT license. See [LICENSE](LICENSE) for details.
