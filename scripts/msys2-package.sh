#!/bin/bash
set -ex

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."
  exit 1
fi

# FIXME:
# For some strange reason sometimes some errors occurs randomly on
# GitHub Actions MINGW32 build, one of:
# - The environment variable $INSTALL_NAME is correct,
#   but it expands with a drive letter at the end (all builds).
# - Error on line 70 in D:\a\lite-xl\lite-xl\build\innosetup.iss:
#   No files found matching "D:/a/lite-xl/lite-xl/build/mingwLibsWin32/*" (release only).

show_help(){
  echo
  echo "Usage: $0 <OPTIONS>"
  echo
  echo "Available options:"
  echo
  echo "-b --builddir DIRNAME     Sets the name of the build directory (not path)."
  echo "                          Default: 'build'."
  echo "-d --destdir DIRNAME      Sets the name of the install directory (not path)."
  echo
}

BUILD_DIR=build

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
    -d|--destdir)
      DEST_DIR="$2"
      shift
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

DESTDIR="$(pwd)/${DEST_DIR}" meson install --skip-subprojects -C ${BUILD_DIR}

zip -9rv ${DEST_DIR}.zip ${DEST_DIR}/*
