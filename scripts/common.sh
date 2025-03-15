#!/bin/bash

set -e

get_platform_name() {
  if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    echo "windows"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "darwin"
  elif [[ "$OSTYPE" == "linux"* || "$OSTYPE" == "freebsd"* ]]; then
    echo "linux"
  else
    echo "UNSUPPORTED-OS"
  fi
}

get_executable_extension() {
  if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    echo ".exe"
  else
    echo ""
  fi
}

get_platform_arch() {
  arch=${CROSS_ARCH:-$(uname -m)}
  if [[ $MSYSTEM != "" ]]; then
    case "$MSYSTEM" in
      MINGW64|UCRT64|CLANG64)
      arch=x86_64
      ;;
      MINGW32|CLANG32)
      arch=i686
      ;;
      CLANGARM64)
      arch=aarch64
      ;;
    esac
  fi
  [[ $arch == "arm64" ]] && arch="aarch64"
  echo "$arch"
}

get_platform_tuple() {
  platform="$(get_platform_name)"
  arch="$(get_platform_arch)"
  echo "$arch-$platform"
}

get_default_build_dir() {
  platform="${1:-$(get_platform_name)}"
  arch="${2:-$(get_platform_arch)}"
  echo "build-$arch-$platform"
}

if [[ $(get_platform_name) == "UNSUPPORTED-OS" ]]; then
  echo "Error: unknown OS type: \"$OSTYPE\""
  exit 1
fi
