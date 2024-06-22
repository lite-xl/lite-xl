#!/usr/bin/env bash
set -ex

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."
  exit 1
fi

WORKDIR="work"
DMGDIR="$1"

if [[ -z "$DMGDIR" ]]; then
	echo "Please provide a path containing the dmg files."
	exit 1
fi

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

for dmg_path in "$DMGDIR"/*.dmg; do
	dmg="${dmg_path##*/}"
	dmg="${dmg%.dmg}"
	hdiutil attach -mountpoint "/Volumes/$dmg" "$dmg_path"
	if [[ ! -d "$WORKDIR/dmg" ]]; then
		ditto "/Volumes/$dmg/Lite XL.app" "Lite XL.app"
	fi
	cp "/Volumes/$dmg/Lite XL.app/Contents/MacOS/lite-xl" "$WORKDIR/$dmg-lite-xl"
	hdiutil detach "/Volumes/$dmg"
done

lipo -create -output "Lite XL.app/Contents/MacOS/lite-xl" "$WORKDIR/"*-lite-xl

# https://eclecticlight.co/2019/01/17/code-signing-for-the-concerned-3-signing-an-app/
# https://wiki.lazarus.freepascal.org/Code_Signing_for_macOS#Big_Sur_and_later_on_Apple_M1_ARM64_processors
# codesign all the files again, hopefully this would fix signature validation
codesign --force --deep --digest-algorithm=sha1,sha256 -s - "Lite XL.app"

source scripts/appdmg.sh "$2"