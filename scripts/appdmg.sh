#!/bin/bash
set -ex

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."
  exit 1
fi

cat > lite-xl-dmg.json << EOF
{
  "title": "Lite XL",
  "icon": "$(pwd)/resources/icons/icon.icns",
  "background": "$(pwd)/resources/macos/appdmg.png",
  "window": {
    "position": {
      "x": 360,
      "y": 360
    },
    "size": {
      "width": 480,
      "height": 360
    }
  },
  "contents": [
    { "x": 144, "y": 248, "type": "file", "path": "$(pwd)/Lite XL.app" },
    { "x": 336, "y": 248, "type": "link", "path": "/Applications" }
  ]
}
EOF
~/node_modules/appdmg/bin/appdmg.js lite-xl-dmg.json "$(pwd)/$1.dmg"
