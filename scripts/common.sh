#!/bin/bash

set -e

get_platform_name() {
  if [[ "$OSTYPE" == "msys" ]]; then
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
  if [[ "$OSTYPE" == "msys" ]]; then
    echo ".exe"
  else
    echo ""
  fi
}

get_platform_arch() {
  arch=${CROSS_ARCH:-$(uname -m)}
  if [[ $MSYSTEM != "" ]]; then
    if [[ $MSYSTEM == "MINGW64" ]]; then
      arch=x86_64
    else
      arch=x86
    fi
  fi
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
