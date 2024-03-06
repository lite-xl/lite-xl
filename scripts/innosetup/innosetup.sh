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
  echo "-v --version VERSION      Sets the version on the package name."
  echo "-a --addons               Tell the script we are packaging an install with addons."
  echo "   --debug                Debug this script."
  echo
}

main() {
  local build_dir=$(get_default_build_dir)
  local addons=false
  local arch
  local arch_file
  local version
  local output

  case "$MSYSTEM" in
    MINGW64|UCRT64|CLANG64)
    arch=x64
    arch_file=x86_64
    ;;
    MINGW32|CLANG32)
    arch=x86
    arch_file=i686
    ;;
    CLANGARM64)
    arch=arm64
    arch_file=aarch64
    ;;
    *)
    echo "error: unsupported MSYSTEM type: $MSYSTEM"
    exit 1
    ;;
  esac

  initial_arg_count=$#

  for i in "$@"; do
    case $i in
      -h|--help)
        show_help
        exit 0
        ;;
      -a|--addons)
        addons=true
        shift
        ;;
      -b|--builddir)
        build_dir="$2"
        shift
        shift
        ;;
      -v|--version)
        if [[ -n $2 ]]; then version="-$2"; fi
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

  # show help if no valid argument was found
  if [ $initial_arg_count -eq $# ]; then
    show_help
    exit 1
  fi

  if [[ $addons == true ]]; then
    version="${version}-addons"
  fi

  output="LiteXL${version}-${arch_file}-setup"

  "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" -dARCH=$arch //F"${output}" "${build_dir}/scripts/innosetup.iss"
  pushd "${build_dir}/scripts"; mv LiteXL*.exe "./../../"; popd
}

main "$@"
