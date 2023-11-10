#!/bin/bash
set -ex

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."
  exit 1
fi

dmgbuild -s resources/macos/lite-xl-dmg.py "Lite XL" "$1.dmg"
