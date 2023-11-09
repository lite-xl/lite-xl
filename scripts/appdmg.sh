#!/bin/bash
set -ex

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."
  exit 1
fi

cat > lite-xl-dmg.py << EOF
import os.path

app_path = "$(pwd)/Lite XL.app"
app_name = os.path.basename(app_path)

format = defines.get("format", "UDBZ")

files = [ (app_path, app_name) ]
symlinks = { "Applications": "/Applications" }
icon_locations = { app_name: (144, 248), "Applications": (336, 248) }

icon = "$(pwd)/resources/icons/icon.icns"
background = "$(pwd)/resources/macos/appdmg.png"
window_rect = ((360, 360), (480, 360))
default_view = "icon_view"
EOF

dmgbuild -s lite-xl-dmg.py "Lite XL" "$(pwd)/$1.dmg"