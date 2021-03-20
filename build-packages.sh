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
  local portable=""
  if [ "$1" == "-portable" ]; then
    portable="-portable"
    shift
  fi
  local build="$1"
  local arch="$2"
  local os="win"
  local pdir=".package-build/lite-xl"
  if [ "$portable" == "-portable" ]; then
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
  cp "$build/src/lite.exe" "$bindir"
  strip --strip-all "$bindir/lite.exe"
  pushd ".package-build"
  local package_name="lite-xl-$os-$arch$portable.zip"
  zip "$package_name" -r "lite-xl"
  mv "$package_name" ..
  popd
  rm -fr ".package-build"
  echo "created package $package_name"
}

lite_build_package_macosx () {
  local portable=""
  if [ "$1" == "-portable" ]; then
    portable="-portable"
    shift
  fi
  local build="$1"
  local arch="$2"
  local os="macosx"
  local pdir=".package-build/lite-xl.app/Contents/MacOS"
  if [ "$portable" == "-portable" ]; then
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
  local package_name="lite-xl-$os-$arch$portable.zip"
  zip "$package_name" -r "lite-xl.app"
  mv "$package_name" ..
  popd
  rm -fr ".package-build"
  echo "created package $package_name"
}

lite_build_package_linux () {
  local portable=""
  if [ "$1" == "-portable" ]; then
    portable="-portable"
    shift
  fi
  local build="$1"
  local arch="$2"
  local os="linux"
  local pdir=".package-build/lite-xl"
  if [ "$portable" == "-portable" ]; then
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
  if [ -z "$portable" ]; then
    mkdir -p "$pdir/share/applications" "$pdir/share/icons/hicolor/scalable/apps"
    cat << EOF > "$pdir/share/applications/lite-xl.desktop"
[Desktop Entry]
Type=Application
Name=Lite XL
Comment=A lightweight text editor written in Lua
Exec=lite %F
Icon=lite-xl
Terminal=false
StartupNotify=false
Categories=Utility;TextEditor;Development;
MimeType=text/plain;
EOF
    cp "dev-utils/lite.svg" "$pdir/share/icons/hicolor/scalable/apps/lite-xl.svg"
  fi
  pushd ".package-build"
  local package_name="lite-xl-$os-$arch$portable.tar.gz"
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

unset arch
while [ ! -z {$1+x} ]; do
  case $1 in
  -pgo)
    pgo=true
    shift
    ;;
  -branch=*)
    use_branch="${1#-branch=}"
    shift
    ;;
  *)
    arch="$1"
    break
  esac
done

if [ -z ${arch+set} ]; then
  echo "usage: $0 [options] <arch>"
  exit 1
fi

if [ -z ${use_branch+set} ]; then
  use_branch="$(git rev-parse --abbrev-ref HEAD)"
fi

build_dir=".build-$arch"

if [ -z ${pgo+set} ]; then
  lite_build "$build_dir"
else
  lite_build_pgo "$build_dir"
fi
lite_copy_third_party_modules "$build_dir"
lite_build_package "$build_dir" "$arch"
lite_build_package -portable "$build_dir" "$arch"

