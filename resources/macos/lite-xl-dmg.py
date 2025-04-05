# configuration for dmgbuild

import os.path

app_path = defines.get("app_path", "Lite XL.app")
app_name = os.path.basename(app_path)

# Image options
format = defines.get("format", "UDZO")

# all sizes here are in points (pt)s
# for reference, size-in-points = size-in-pixels * 72 / dpi
# background DPI is 300, icon DPI is assumed to be 96

# Content options
files = [(app_path, app_name)]
symlinks = {"Applications": "/Applications"}
icon = "resources/macos/dmg-icon.icns"
icon_locations = {app_name: (170, 140), "Applications": (384, 140)}

# Window options
background = "resources/macos/background.tiff"
window_rect = ((100, 338), (550, 362))
default_view = "coverflow"
include_icon_view_settings = True
show_icon_preview = True

# Icon view options
icon_size = 128
text_size = 13
