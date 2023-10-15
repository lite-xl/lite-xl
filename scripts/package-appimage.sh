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
    if ! wget -O appimagetool "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-${ARCH}.AppImage" ; then
      echo "Could not download the appimagetool for the arch '${ARCH}'."
      exit 1
    else
      chmod 0755 appimagetool
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

generate_appimage() {
  [[ ! -e $BUILD_DIR ]] && scripts/build.sh $@

  if [ -e LiteXL.AppDir ]; then
    rm -rf LiteXL.AppDir
  fi

  echo "Creating LiteXL.AppDir..."

  DESTDIR="$(realpath LiteXL.AppDir)" meson install -C ${BUILD_DIR}
  mv AppRun LiteXL.AppDir/
  # These could be symlinks but it seems they doesn't work with AppimageLauncher
  cp resources/icons/lite-xl.svg LiteXL.AppDir/
  cp resources/linux/com.lite_xl.LiteXL.desktop LiteXL.AppDir/

  echo "Generating AppImage..."
  local version=""
  if [ -n "$VERSION" ]; then
    version="-$VERSION"
  fi

  ./appimagetool --appimage-extract-and-run LiteXL.AppDir LiteXL${version}-${ARCH}-linux.AppImage
  rm -rf LiteXL.AppDir
}

setup_appimagetool
download_appimage_apprun
generate_appimage
