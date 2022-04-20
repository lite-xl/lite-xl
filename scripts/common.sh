#!/bin/bash

set -e

get_platform_name() {
  if [[ "$OSTYPE" == "msys" ]]; then
    echo "windows"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "macos"
  elif [[ "$OSTYPE" == "linux"* || "$OSTYPE" == "freebsd"* ]]; then
    echo "linux"
  else
    echo "UNSUPPORTED-OS"
  fi
}

get_arch () {
  if [ -z ${CPU_TYPE+x} ]; then
    uname -m
  else
    echo "$CPU_TYPE"
  fi
}

get_default_build_dir() {
  platform=$(get_platform_name)
  echo "build-$platform-$(get_arch)"
}

if [[ $(get_platform_name) == "UNSUPPORTED-OS" ]]; then
  echo "Error: unknown OS type: \"$OSTYPE\""
  exit 1
fi
