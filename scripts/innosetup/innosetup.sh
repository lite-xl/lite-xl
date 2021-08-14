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
  echo
}

innosetup() {
  # MSYS2 ldd command seems to be only 64bit, so use ntldd
  # see https://github.com/msys2/MINGW-packages/issues/4164
  if [[ $MSYSTEM == "MINGW64" ]]; then
    ARCH=x64
  else
    ARCH=Win32
  fi

  local mingwLibsDir=$BUILD_DIR/mingwLibs$ARCH
  mkdir -p "$mingwLibsDir"
  ntldd -R "$BUILD_DIR/src/lite-xl.exe" | grep mingw | awk '{print $3}' | sed 's#\\#/#g' | xargs -I '{}' cp -v '{}' $mingwLibsDir

  /c/Program\ Files\ \(x86\)/Inno\ Setup\ 6/ISCC.exe -dARCH=$ARCH $BUILD_DIR/innosetup.iss
  mv $BUILD_DIR/LiteXL*.exe $(pwd)
}

BUILD_DIR=build

for i in "$@"; do
  case $i in
    -h|--belp)
      show_help
      exit 0
      ;;
    -b|--BUILD_DIR)
      BUILD_DIR="$2"
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

innosetup
