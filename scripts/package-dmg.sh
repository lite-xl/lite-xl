#!/usr/bin/env bash
set -ex

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."
  exit 1
fi

mkdir -p "Lite XL.app/Contents/MacOS" "Lite XL.app/Contents/Resources"
cp -r $1/lite-xl/lite-xl "Lite XL.app/Contents/MacOS"
cp -r $1/lite-xl/data/* "Lite XL.app/Contents/Resources"
cp resources/icons/icon.icns "Lite XL.app/Contents/Resources"
cp -r $1/Info.plist "Lite XL.app/Contents/Resources"

dmgbuild -s resources/macos/lite-xl-dmg.py "Lite XL" "$2.dmg"

rm -rf "Lite XL.app"

