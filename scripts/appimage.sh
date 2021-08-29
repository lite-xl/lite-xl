#!/bin/env bash
set -ex

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."
  exit 1
fi

source scripts/common.sh

show_help(){
  echo
  echo "Usage: $0 <OPTIONS>"
  echo
  echo "Available options:"
  echo
  echo "-h --help                 Show this help and exits."
  echo "-b --builddir DIRNAME     Sets the name of the build dir (no path)."
  echo "                          Default: 'build'."
  echo "-n --nobuild              Skips the build step, use existing files."
  echo "-s --static               Specify if building using static libraries"
  echo "                          by using lhelper tool."
  echo "-v --version VERSION      Specify a version, non whitespace separated string."
  echo
}

ARCH="$(uname -m)"
BUILD_DIR="$(get_default_build_dir)"
RUN_BUILD=true
STATIC_BUILD=false

for i in "$@"; do
  case $i in
    -h|--belp)
      show_help
      exit 0
      ;;
    -b|--builddir)
      BUILD_DIR="$2"
      shift
      shift
      ;;
    -n|--nobuild)
      RUN_BUILD=false
      shift
      ;;
    -s|--static)
      STATIC_BUILD=true
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

# TODO: Versioning using git
#if [[ -z $VERSION && -d .git ]]; then
#  VERSION=$(git describe --tags --long | sed 's/^v//; s/\([^-]*-g\)/r\1/; s/-/./g')
#fi

if [[ -n $1 ]]; then
  show_help
  exit 1
fi

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

build_litexl() {
  if [ -e build ]; then
    rm -rf build
  fi

  if [ -e ${BUILD_DIR} ]; then
    rm -rf ${BUILD_DIR}
  fi

  echo "Build lite-xl..."
  sleep 1
  meson setup --buildtype=release --prefix /usr ${BUILD_DIR}
  meson compile -C ${BUILD_DIR}
}

generate_appimage() {
  if [ -e LiteXL.AppDir ]; then
    rm -rf LiteXL.AppDir
  fi

  echo "Creating LiteXL.AppDir..."

  DESTDIR="$(realpath LiteXL.AppDir)" meson install --skip-subprojects -C ${BUILD_DIR}
  mv AppRun LiteXL.AppDir/
  # These could be symlinks but it seems they doesn't work with AppimageLauncher
  cp resources/icons/lite-xl.svg LiteXL.AppDir/
  cp resources/linux/org.lite_xl.lite_xl.desktop LiteXL.AppDir/

  if [[ $STATIC_BUILD == false ]]; then
    echo "Copying libraries..."

    mkdir -p LiteXL.AppDir/usr/lib/

    local allowed_libs=(
      libfreetype
      libpcre2
      libSDL2
      libsndio
      liblua
    )

    while read line; do
      local libname="$(echo $line | cut -d' ' -f1)"
      local libpath="$(echo $line | cut -d' ' -f2)"
      for lib in "${allowed_libs[@]}" ; do
        if echo "$libname" | grep "$lib" > /dev/null ; then
          cp "$libpath" LiteXL.AppDir/usr/lib/
          continue 2
        fi
      done
      echo "  Ignoring: $libname"
    done < <(ldd build/src/lite-xl | awk '{print $1 " " $3}')
  fi

  echo "Generating AppImage..."
  local version=""
  if [ -n "$VERSION" ]; then
    version="-$VERSION"
  fi

  ./appimagetool LiteXL.AppDir LiteXL${version}-${ARCH}.AppImage
}

setup_appimagetool
download_appimage_apprun
if [[ $RUN_BUILD == true ]]; then build_litexl; fi
generate_appimage $1
