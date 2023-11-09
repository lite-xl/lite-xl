# Scripts

Various scripts and configurations used to configure, build, and package Lite XL.

### Build

- **build.sh**
- **build-packages.sh**: In root directory, as all in one script; relies to the
  ones in this directory.

### Package

- **appdmg.sh**:    Create a macOS DMG image using [dmgbuild][1].
- **appimage.sh**:  [AppImage][2] builder.
- **innosetup.sh**: Creates a 32/64 bit [InnoSetup][3] installer package.
- **package.sh**:   Creates all binary / DMG image / installer / source packages.

### Utility

- **common.sh**:               Common functions used by other scripts.
- **install-dependencies.sh**: Installs required applications to build, package
  and run Lite XL, mainly useful for CI and documentation purpose.
  Preferably not to be used in user systems.
- **fontello-config.json**:    Used by the icons generator.
- **generate_header.sh**: Generates a header file for native plugin API
- **keymap-generator**: Generates a JSON file containing the keymap

[1]: https://github.com/dmgbuild/dmgbuild
[2]: https://docs.appimage.org/
[3]: https://jrsoftware.org/isinfo.php
