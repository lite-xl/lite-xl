# Scripts

Various scripts and configurations used to configure and package Lite XL.

### Package

- **appdmg.sh**:    Create a macOS DMG image using [dmgbuild][1].
- **appimage.sh**:  [AppImage][2] builder.
- **innosetup.sh**: Creates a 32/64 bit [InnoSetup][3] installer package.
- **package.sh**:   Creates all binary / DMG image / installer / source packages.

### Utility

- **common.sh**:                 Common functions used by other scripts.
- **fontello-config.json**:      Used by the icons generator.
- **generate_header.sh**:        Generates a header file for native plugin API
- **keymap-generator**:          Generates a JSON file containing the keymap
- **generate-release-notes.sh**: Generates a release note for Lite XL releases.

[1]: https://github.com/dmgbuild/dmgbuild
[2]: https://docs.appimage.org/
[3]: https://jrsoftware.org/isinfo.php
