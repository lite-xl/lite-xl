#!/bin/bash
set -e

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."; exit 1
fi

source scripts/common.sh

show_help() {
  echo
  echo "Usage: $0 <OPTIONS>"
  echo
  echo "Available options:"
  echo
  echo "-b --builddir DIRNAME     Sets the name of the build directory (not path)."
  echo "                          Default: '$(get_default_build_dir)'."
  echo "   --debug                Debug this script."
  echo
}

main() {
  local build_dir=$(get_default_build_dir)
  local arch

  if [[ $MSYSTEM == "MINGW64" ]]; then arch=x64; else arch=Win32; fi

  for i in "$@"; do
    case $i in
      -h|--help)
        show_help
        exit 0
        ;;
      -b|--builddir)
        build_dir="$2"
        shift
        shift
        ;;
      --debug)
        set -x
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

  # Copy MinGW libraries dependencies.
  # MSYS2 ldd command seems to be only 64bit, so use ntldd
  # see https://github.com/msys2/MINGW-packages/issues/4164
  echo "Linked libraries:"
  ntldd -R "${build_dir}/src/lite-xl.exe"

  echo "Copy dll's:"
  local mingwLibsDir="${build_dir}/mingwLibs$arch"
  mkdir -p "$mingwLibsDir"
  ntldd -R "${build_dir}/src/lite-xl.exe" \
    | grep mingw \
    | awk '{print $3}' \
    | sed 's#\\#/#g' \
    | xargs -I '{}' cp -v '{}' $mingwLibsDir

  "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" -dARCH=$arch "${build_dir}/scripts/innosetup.iss"
  pushd "${build_dir}/scripts"; mv LiteXL*.exe "./../../"; popd
}

main "$@"
