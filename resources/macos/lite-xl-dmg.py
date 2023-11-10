# configuration for dmgbuild

import os.path

app_path = "Lite XL.app"
app_name = os.path.basename(app_path)

# Image options
format = defines.get("format", "UDZO")

# Content options
files = [(app_path, app_name)]
symlinks = { "Applications": "/Applications" }
icon = "resources/icons/icon.icns"
icon_locations = {
    app_name: (144, 248),
    "Applications": (336, 248)
}

# Window options
background = "resources/macos/dmg-cover.png"
window_rect = ((360, 360), (480, 380))
default_view = "coverflow"
include_icon_view_settings = True

# Icon view options
icon_size = 80
text_size = 11.0
