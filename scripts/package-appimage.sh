#!/usr/bin/env bash
set -e

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."
  exit 1
fi

source scripts/common.sh

ARCH="$(uname -m)"
BUILD_DIR="$(get_default_build_dir)"
ADDONS=false

show_help(){
  echo
  echo "Usage: $0 <OPTIONS>"
  echo
  echo "Available options:"
  echo
  echo "-h --help                 Show this help and exits."
  echo "-b --builddir DIRNAME     Sets the name of the build dir (no path)."
  echo "                          Default: '${BUILD_DIR}'."
  echo "   --debug                Debug this script."
  echo "-n --nobuild              Skips the build step, use existing files."
  echo "-v --version VERSION      Specify a version, non whitespace separated string."
  echo
}

for i in "$@"; do
  case $i in
    -h|--help)
      show_help
      exit 0
      ;;
    -b|--builddir)
      BUILD_DIR="$2"
      shift
      shift
      ;;
    --debug)
      set -x
      shift
      ;;
    -v|--version)
      VERSION="$2"
      shift
      shift
      ;;
    *)
      # unknown option
      ;;
  esac
done

setup_appimagetool() {
  if [ ! -e appimagetool ]; then
    if ! wget -O appimagetool "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${ARCH}.AppImage" ; then
      echo "Could not download the appimagetool for the arch '${ARCH}'."
      exit 1
    else
      chmod 0755 appimagetool
    fi
  fi
}

generate_appimage() {
  [[ ! -e $BUILD_DIR ]] && scripts/build.sh $@

  if [ -e LiteXL.AppDir ]; then
    rm -rf LiteXL.AppDir
  fi

  echo "Creating LiteXL.AppDir..."

  DESTDIR="$(realpath LiteXL.AppDir)" meson install -C ${BUILD_DIR}

  cp resources/icons/lite-xl.svg LiteXL.AppDir/
  cp resources/linux/com.lite_xl.LiteXL.desktop LiteXL.AppDir/

  # https://github.com/lite-xl/lite-xl/issues/1912
  mkdir -p ./LiteXL.AppDir/usr/share/../bin
  mv ./LiteXL.AppDir/lite-xl ./LiteXL.AppDir/usr/bin
  mv ./LiteXL.AppDir/data ./LiteXL.AppDir/usr/share/lite-xl
  rm -rf ./LiteXL.AppDir/lib64 ./LiteXL.AppDir/include

  echo "Creating AppRun..."
	cat >> LiteXL.AppDir/AppRun <<- 'EOF'
	#!/bin/sh
	CURRENTDIR="$(dirname "$(readlink -f "$0")")"
	exec "$CURRENTDIR/usr/bin/lite-xl" "$@"
	EOF
  chmod +x LiteXL.AppDir/AppRun

  echo "Generating AppImage..."
  local version=""
  if [ -n "$VERSION" ]; then
    version="-$VERSION"
  fi

  APPIMAGE_EXTRACT_AND_RUN=1 ./appimagetool LiteXL.AppDir LiteXL${version}-${ARCH}-linux.AppImage
  rm -rf LiteXL.AppDir
}

setup_appimagetool
generate_appimage
