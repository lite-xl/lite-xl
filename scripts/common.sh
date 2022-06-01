#!/bin/bash

set -e

addons_download() {
  local build_dir="$1"

  if [[ -d "${build_dir}/third/data/colors" ]]; then
    echo "Warning: found previous addons installation, skipping."
    echo "  addons path: ${build_dir}/third/data/colors"
    return 0
  fi

  # Download third party color themes
  curl --insecure \
    -L "https://github.com/lite-xl/lite-xl-colors/archive/master.zip" \
    -o "${build_dir}/lite-xl-colors.zip"

  mkdir -p "${build_dir}/third/data/colors"
  unzip "${build_dir}/lite-xl-colors.zip" -d "${build_dir}"
  mv "${build_dir}/lite-xl-colors-master/colors" "${build_dir}/third/data"
  rm -rf "${build_dir}/lite-xl-colors-master"

  # Download widgets library
  curl --insecure \
    -L "https://github.com/lite-xl/lite-xl-widgets/archive/master.zip" \
    -o "${build_dir}/lite-xl-widgets.zip"

  unzip "${build_dir}/lite-xl-widgets.zip" -d "${build_dir}"
  mv "${build_dir}/lite-xl-widgets-master" "${build_dir}/third/data/widget"

  # Downlaod thirdparty plugins
  curl --insecure \
    -L "https://github.com/lite-xl/lite-xl-plugins/archive/2.1.zip" \
    -o "${build_dir}/lite-xl-plugins.zip"

  unzip "${build_dir}/lite-xl-plugins.zip" -d "${build_dir}"
  mv "${build_dir}/lite-xl-plugins-2.1/plugins" "${build_dir}/third/data"
  rm -rf "${build_dir}/lite-xl-plugins-2.1"
}

# Addons installation: some distributions forbid external downloads
# so make it as optional module.
addons_install() {
  local build_dir="$1"
  local data_dir="$2"

  for module_name in colors widget; do
    cp -r "${build_dir}/third/data/$module_name" "${data_dir}"
  done

  mkdir -p "${data_dir}/plugins"

  for plugin_name in settings; do
    cp -r "${build_dir}/third/data/plugins/${plugin_name}.lua" \
      "${data_dir}/plugins/"
  done
}

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

get_default_build_dir() {
  platform=$(get_platform_name)
  arch=$(uname -m)
  if [[ $MSYSTEM != "" ]]; then
    if [[ $MSYSTEM == "MINGW64" ]]; then
      arch=x86_64
    else
      arch=i686
    fi
  fi
  echo "build-$platform-$arch"
}

if [[ $(get_platform_name) == "UNSUPPORTED-OS" ]]; then
  echo "Error: unknown OS type: \"$OSTYPE\""
  exit 1
fi
