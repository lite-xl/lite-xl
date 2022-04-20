#!/bin/env bash
set -e

source scripts/common.sh

wget="wget --retry-connrefused --waitretry=1 --read-timeout=20 --no-check-certificate" 

workdir=".repackage"
rm -fr "$workdir" && mkdir "$workdir" && pushd "$workdir"

ARCH="$(get_arch)"

create_appimage() {
  rm -fr LiteXL.AppDir

  echo "Creating LiteXL.AppDir..."

  mkdir -p LiteXL.AppDir/usr
  tar xf "$1" -C LiteXL.AppDir/usr --strip-components=1
  cp AppRun LiteXL.AppDir/
  pushd LiteXL.AppDir
  strip AppRun
  mv usr/share/applications/org.lite_xl.lite_xl.desktop .
  mv usr/share/icons/hicolor/scalable/apps/lite-xl.svg .
  rm -fr usr/share/{icons,applications,metainfo}
  popd

  echo "Generating AppImage..."
  local appimage_name="${1/lite-xl/LiteXL}"
  appimage_name="${appimage_name/-linux/}"
  appimage_name="${appimage_name/%.tar.gz/.AppImage}"

  ./appimagetool LiteXL.AppDir "$appimage_name"
}

repackage_from_github () {
  assets=($($wget -q -nv -O- https://api.github.com/repos/franko/lite-xl/releases/latest | grep "browser_download_url" | cut -d '"' -f 4))

  for url in "${assets[@]}"; do
    if [[ $url == *"linux-x86_64"* ]]; then
      echo "getting: $url"
      $wget -q "$url" || exit 1
      create_appimage "${url##*/}"
    fi
  done
}

setup_appimagetool() {
  if ! which appimagetool > /dev/null ; then
    if [ ! -e appimagetool ]; then
      if ! wget -O appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${ARCH}.AppImage" ; then
        echo "Could not download the appimagetool for the arch '${ARCH}'."
        exit 1
      else
        chmod 0755 appimagetool
      fi
    fi
  fi
}

download_appimage_apprun() {
  if [ ! -e AppRun ]; then
    if ! wget -O AppRun "https://github.com/AppImage/AppImageKit/releases/download/continuous/AppRun-${ARCH}" ; then
      echo "Could not download AppRun for the arch '${ARCH}'."
      exit 1
    else
      chmod 0755 AppRun
    fi
  fi
}

setup_appimagetool
download_appimage_apprun
repackage_from_github

