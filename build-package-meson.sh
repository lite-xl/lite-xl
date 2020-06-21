#!/bin/bash

lite_build_pgo () {
  build="$1"
  if [[ $build == */* || -z "$build" ]]; then
    echo "invalid build directory, no path allowed: \"$build\""
    exit 1
  fi
  git ls-files --error-unmatch "$build" &> /dev/null
  if [ $? == 0 ]; then
    echo "invalid path, \"$build\" is under revision control"
    exit 1
  fi
  rm -fr "$build"
  meson setup --buildtype=release -Db_pgo=generate "$build" || exit 1
  ninja -C "$build" || exit 1
  cp -r data "$build/src"
  "$build/src/lite"
  meson configure -Db_pgo=use "$build"
  ninja -C "$build" || exit 1
}

lite_build_package () {
  build="$1"
  version="$2"
  arch="$3"
  lite_exe=lite
  strip=strip
  if [[ "$OSTYPE" == msys || "$OSTYPE" == win32 ]]; then
    lite_exe=lite.exe
    strip="strip --strip-all"
  fi
  local pdir=".package-build/lite-xl-$version"
  mkdir -p "$pdir"
  cp -r data "$pdir"
  cp "$build/src/$lite_exe" "$pdir"
  $strip "$pdir/$lite_exe"
  pushd ".package-build"
  local package_name
  if [[ "$OSTYPE" == msys || "$OSTYPE" == win32 ]]; then
    package_name="lite-xl-$version-$arch.zip"
    zip "$package_name" -r "lite-xl-$version"
  else
    package_name="lite-xl-$version-$arch.tar.gz"
    tar czf "$package_name" "lite-xl-$version"
  fi
  mv "$package_name" ..
  popd
  rm -fr ".package-build"
  echo "created package $package_name"
}

if [[ -z "$1" || -z "$2" ]]; then
  echo "usage: $0 <version> <arch>"
  exit 1
fi

version="$1"
arch="$2"
build_dir=".build-$arch"

lite_build_pgo "$build_dir"
lite_build_package "$build_dir" "$version" "$arch"

