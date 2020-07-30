#!/bin/bash

copy_directory_from_repo () {
  local dirname="$1"
  local destdir="$2"
  git --work-tree="$destdir" checkout HEAD -f -- "$dirname"
}

# Check if build directory is ok to be used to build.
build_dir_is_usable () {
  local build="$1"
  if [[ $build == */* || -z "$build" ]]; then
    echo "invalid build directory, no path allowed: \"$build\""
    return 1
  fi
  git ls-files --error-unmatch "$build" &> /dev/null
  if [ $? == 0 ]; then
    echo "invalid path, \"$build\" is under revision control"
    return 1
  fi
}

# Ordinary release build
lite_build () {
  local build="$1"
  build_dir_is_usable "$build" || exit 1
  rm -fr "$build"
  meson setup --buildtype=release "$build" || exit 1
  ninja -C "$build" || exit 1
}

# Build using Profile Guided Optimizations (PGO)
lite_build_pgo () {
  local build="$1"
  build_dir_is_usable "$build" || exit 1
  rm -fr "$build"
  meson setup --buildtype=release -Db_pgo=generate "$build" || exit 1
  ninja -C "$build" || exit 1
  copy_directory_from_repo data "$build/src"
  "$build/src/lite"
  meson configure -Db_pgo=use "$build"
  ninja -C "$build" || exit 1
}

lite_build_package_windows () {
  build="$1"
  version="$2"
  arch="$3"
  os="win"
  local pdir=".package-build/lite-xl"
  mkdir -p "$pdir"
  copy_directory_from_repo data "$pdir"
  cp "$build/src/lite.exe" "$pdir"
  strip --strip-all "$pdir/lite.exe"
  pushd ".package-build"
  local package_name="lite-xl-$version-$os-$arch.zip"
  zip "$package_name" -r "lite-xl"
  mv "$package_name" ..
  popd
  rm -fr ".package-build"
  echo "created package $package_name"
}

lite_build_package_macosx () {
  build="$1"
  version="$2"
  arch="$3"
  os="macosx"
  local pdir=".package-build/lite-xl.app/Contents/MacOS"
  mkdir -p "$pdir"
  copy_directory_from_repo data "$pdir"
  cp "$build/src/lite" "$pdir"
  strip "$pdir/lite"
  pushd ".package-build"
  local package_name="lite-xl-$version-$os-$arch.zip"
  zip "$package_name" -r "lite-xl.app"
  mv "$package_name" ..
  popd
  rm -fr ".package-build"
  echo "created package $package_name"
}

lite_build_package_linux () {
  build="$1"
  version="$2"
  arch="$3"
  os="linux"
  local pdir=".package-build/lite-xl"
  mkdir -p "$pdir"
  copy_directory_from_repo data "$pdir"
  cp "$build/src/lite" "$pdir"
  strip "$pdir/lite"
  pushd ".package-build"
  local package_name="lite-xl-$version-$os-$arch.tar.gz"
  tar czf "$package_name" "lite-xl"
  mv "$package_name" ..
  popd
  rm -fr ".package-build"
  echo "created package $package_name"
}

lite_build_package () {
  if [[ "$OSTYPE" == msys || "$OSTYPE" == win32 ]]; then
    lite_build_package_windows "$@"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    lite_build_package_macosx "$@"
  elif [[ "$OSTYPE" == "linux"* || "$OSTYPE" == "freebsd"* ]]; then
    lite_build_package_linux "$@"
  else
    echo "Unknown OS type \"$OSTYPE\""
    exit 1
  fi
}

if [[ -z "$1" || -z "$2" ]]; then
  echo "usage: $0 <version> <arch>"
  exit 1
fi

if [[ "$1" == "-pgo" ]]; then
  pgo=true
  shift
fi

version="$1"
arch="$2"
build_dir=".build-$arch"

if [ -z ${pgo+set} ]; then
  lite_build "$build_dir"
else
  lite_build_pgo "$build_dir"
fi
lite_build_package "$build_dir" "$version" "$arch"

