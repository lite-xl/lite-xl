#!/bin/bash
set -ex

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."
  exit 1
fi

show_help(){
  echo
  echo "Usage: $0 <OPTIONS>"
  echo
  echo "Available options:"
  echo
  echo "-b --builddir DIRNAME     Sets the name of the build directory (not path)."
  echo "                          Default: 'build'."
  echo "-p --prefix PREFIX        Install directory prefix. Mandatory."
  echo "-s --static               Specify if building using static libraries"
  echo "                          by using lhelper tool."
  echo "-u --universal            Universal binary (macOS only)."
  echo
}

install_lhelper() {
  if [[ ! -d lhelper ]]; then
    git clone https://github.com/franko/lhelper.git
    pushd lhelper; bash install-github; popd

    if [[ "$OSTYPE" == "darwin"* ]]; then
      CC=clang CXX=clang++ lhelper create lite-xl -n
    else
      lhelper create lite-xl -n
    fi
  fi

  # Not using `lhelper activate lite-xl`
  source "$(lhelper env-source lite-xl)"

  lhelper install freetype2
  lhelper install sdl2 2.0.14-wait-event-timeout-1
  lhelper install pcre2

  # Help MSYS2 to find the SDL2 include and lib directories to avoid errors
  # during build and linking when using lhelper.
  if [[ "$OSTYPE" == "msys" ]]; then
    CFLAGS=-I${LHELPER_ENV_PREFIX}/include/SDL2
    LDFLAGS=-L${LHELPER_ENV_PREFIX}/lib
  fi
}

build() {
  if [[ "$OSTYPE" == "darwin"* && $UNIVERSAL == true ]]; then
    meson setup \
      --buildtype=release \
      --prefix "$PREFIX" \
      --wrap-mode=forcefallback \
      --cross-file=scripts/meson-macos-arm64.ini \
      --cross-file=scripts/meson-macos-x86_64.ini \
      "${BUILD_DIR}"
  else
    CFLAGS=$CFLAGS LDFLAGS=$LDFLAGS meson setup \
      --buildtype=release \
      --prefix "$PREFIX" \
      --wrap-mode=forcefallback \
      "${BUILD_DIR}"
  fi

  meson compile -C "${BUILD_DIR}"
}

BUILD_DIR=build
STATIC_BUILD=false
UNIVERSAL=false

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
    -p|--prefix)
      PREFIX="$2"
      shift
      shift
      ;;
    -s|--static)
      STATIC_BUILD=true
      shift
      ;;
    -u|--universal)
      UNIVERSAL=true
      shift
      ;;
    *)
      # unknown option
      ;;
  esac
done

if [[ -n $1 ]]; then
  show_help
  exit 1
fi

if [[ -z $PREFIX ]]; then
  echo "ERROR: prefix argument is missing."
  exit 1
fi

if [[ $STATIC_BUILD == true ]]; then
  install_lhelper
fi

build
