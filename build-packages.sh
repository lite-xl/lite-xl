#!/bin/bash

# strip-components is normally set to 1 to strip the initial "data" from the
# directory path.
copy_directory_from_repo () {
  local tar_options=()
  if [[ $1 == --strip-components=* ]]; then
    tar_options+=($1)
    shift
  fi
  local dirname="$1"
  local destdir="$2"
  git archive "$use_branch" "$dirname" --format=tar | tar xf - -C "$destdir" "${tar_options[@]}"
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
  local meson_options=("-Dportable=$1")
  local build="$2"
  build_dir_is_usable "$build" || exit 1
  rm -fr "$build"
  meson setup --buildtype=release "${meson_options[@]}" "$build" || exit 1
  ninja -C "$build" || exit 1
}

# Build using Profile Guided Optimizations (PGO)
lite_build_pgo () {
  local meson_options=("-Dportable=$1")
  local build="$2"
  build_dir_is_usable "$build" || exit 1
  rm -fr "$build"
  meson setup --buildtype=release "${meson_options[@]}" -Db_pgo=generate "$build" || exit 1
  ninja -C "$build" || exit 1
  copy_directory_from_repo data "$build/src"
  "$build/src/lite"
  meson configure -Db_pgo=use "$build"
  ninja -C "$build" || exit 1
}

lite_build_package_windows () {
  local portable="$1"
  local build="$2"
  local version="$3"
  local arch="$4"
  local os="win"
  local pdir=".package-build/lite-xl"
  if [ $portable == "true" ]; then
    local bindir="$pdir"
    local datadir="$pdir/data"
  else
    echo "WARNING: using non portable option on unix-like system"
    local bindir="$pdir/bin"
    local datadir="$pdir/share/lite-xl"
  fi
  mkdir -p "$bindir"
  mkdir -p "$datadir"
  for module_name in core plugins colors fonts; do
    copy_directory_from_repo --strip-components=1 "data/$module_name" "$datadir"
  done
  for module_name in plugins colors; do
    cp -r "$build/third/data/$module_name" "$datadir"
  done
  cp "$build/src/lite.exe" "$bindir"
  strip --strip-all "$bindir/lite.exe"
  pushd ".package-build"
  local package_name="lite-xl-$os-$arch.zip"
  zip "$package_name" -r "lite-xl"
  mv "$package_name" ..
  popd
  rm -fr ".package-build"
  echo "created package $package_name"
}

lite_build_package_macosx () {
  local portable="$1"
  local build="$2"
  local version="$3"
  local arch="$4"
  local os="macosx"
  local pdir=".package-build/lite-xl.app/Contents/MacOS"
  if [ $portable == "true" ]; then
    local bindir="$pdir"
    local datadir="$pdir/data"
  else
    local bindir="$pdir/bin"
    local datadir="$pdir/share/lite-xl"
  fi
  mkdir -p "$bindir"
  mkdir -p "$datadir"
  for module_name in core plugins colors fonts; do
    copy_directory_from_repo --strip-components=1 "data/$module_name" "$datadir"
  done
  for module_name in plugins colors; do
    cp -r "$build/third/data/$module_name" "$datadir"
  done
  cp "$build/src/lite" "$bindir"
  strip "$bindir/lite"
  pushd ".package-build"
  local package_name="lite-xl-$os-$arch.zip"
  zip "$package_name" -r "lite-xl.app"
  mv "$package_name" ..
  popd
  rm -fr ".package-build"
  echo "created package $package_name"
}

lite_build_package_linux () {
  local portable="$1"
  local build="$2"
  local version="$3"
  local arch="$4"
  local os="linux"
  local pdir=".package-build/lite-xl"
  if [ $portable == "true" ]; then
    echo "WARNING: using portable option on unix-like system"
    local bindir="$pdir"
    local datadir="$pdir/data"
  else
    local bindir="$pdir/bin"
    local datadir="$pdir/share/lite-xl"
  fi
  mkdir -p "$bindir"
  mkdir -p "$datadir"
  for module_name in core plugins colors fonts; do
    copy_directory_from_repo --strip-components=1 "data/$module_name" "$datadir"
  done
  for module_name in plugins colors; do
    cp -r "$build/third/data/$module_name" "$datadir"
  done
  cp "$build/src/lite" "$bindir"
  strip "$bindir/lite"
  pushd ".package-build"
  local package_name="lite-xl-$os-$arch.tar.gz"
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

lite_copy_third_party_modules () {
  local build="$1"
  curl --insecure -L "https://github.com/rxi/lite-colors/archive/master.zip" -o "$build/rxi-lite-colors.zip"
  mkdir -p "$build/third/data/colors" "$build/third/data/plugins"
  unzip "$build/rxi-lite-colors.zip" -d "$build"
  mv "$build/lite-colors-master/colors" "$build/third/data"
  rm -fr "$build/lite-colors-master"
}

if [[ -z "$1" || -z "$2" ]]; then
  echo "usage: $0 [options] <version> <arch>"
  exit 1
fi

portable=false
while [ ! -z {$1+x} ]; do
  case $1 in
  -pgo)
    pgo=true
    shift
    ;;
  -portable)
    portable=true
    shift
    ;;
  -branch=*)
    use_branch="${1#-branch=}"
    shift
    ;;
  *)
    version="$1"
    arch="$2"
    break
  esac
done

if [ -z ${use_branch+set} ]; then
  use_branch="$(git rev-parse --abbrev-ref HEAD)"
fi

build_dir=".build-$arch"

if [ -z ${pgo+set} ]; then
  lite_build "$portable" "$build_dir"
else
  lite_build_pgo "$portable" "$build_dir"
fi
lite_copy_third_party_modules "$build_dir"
lite_build_package "$portable" "$build_dir" "$version" "$arch"

