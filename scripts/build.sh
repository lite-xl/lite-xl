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
  echo "-f --forcefallback        Force to build dependencies statically."
  echo "-h --help                 Show this help and exit."
  echo "-p --prefix PREFIX        Install directory prefix. Default: '/'."
  echo "-B --bundle               Create an App bundle (macOS only)"
  echo "-P --portable             Create a portable binary package."
  echo "-O --pgo                  Use profile guided optimizations (pgo)."
  echo "-U --windows-lua-utf      Use the UTF8 patch for Lua."
  echo "                          macOS: disabled when used with --bundle,"
  echo "                          Windows: Implicit being the only option."
  echo "-r --release              Compile in release mode."
  echo
}

main() {
  local platform="$(get_platform_name)"
  local arch="$(get_platform_arch)"
  local build_dir="$(get_default_build_dir)"
  local build_type="debug"
  local prefix=/
  local force_fallback
  local bundle
  local portable
  local pgo
  local patch_lua

  local lua_subproject_path

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
      -f|--forcefallback)
        force_fallback="--wrap-mode=forcefallback"
        shift
        ;;
      -p|--prefix)
        prefix="$2"
        shift
        shift
        ;;
      -B|--bundle)
        if [[ "$platform" != "macos" ]]; then
          echo "Warning: ignoring --bundle option, works only under macOS."
        else
          bundle="-Dbundle=true"
        fi
        shift
        ;;
      -P|--portable)
        portable="-Dportable=true"
        shift
        ;;
      -O|--pgo)
        pgo="-Db_pgo=generate"
        shift
        ;;
      -U|--windows-lua-utf)
        patch_lua="true"
        shift
        ;;
      -r|--release)
        build_type="release"
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

  if [[ $platform == "macos" && -n $bundle && -n $portable ]]; then
      echo "Warning: \"bundle\" and \"portable\" specified; excluding portable package."
      portable=""
  fi

  if [[ $CROSS_ARCH != "" ]]; then
    if [[ $platform == "macos" ]]; then
      macos_version_min=10.11
      if [[ $CROSS_ARCH == "arm64" ]]; then
        cross_file="--cross-file resources/cross/macos_arm64.txt"
        macos_version_min=11.0
      fi
      export MACOSX_DEPLOYMENT_TARGET=$macos_version_min
      export MIN_SUPPORTED_MACOSX_DEPLOYMENT_TARGET=$macos_version_min
      export CFLAGS=-mmacosx-version-min=$macos_version_min
      export CXXFLAGS=-mmacosx-version-min=$macos_version_min
      export LDFLAGS=-mmacosx-version-min=$macos_version_min
    fi
  fi

  rm -rf "${build_dir}"

  CFLAGS=$CFLAGS LDFLAGS=$LDFLAGS meson setup \
    --buildtype=$build_type \
    --prefix "$prefix" \
    $cross_file \
    $force_fallback \
    $bundle \
    $portable \
    $pgo \
    "${build_dir}"

  lua_subproject_path=$(echo subprojects/lua-*/)
  if [[ $patch_lua == "true" ]] && [[ ! -z $force_fallback ]] && [[ -d $lua_subproject_path ]]; then
    patch -d $lua_subproject_path -p1 --forward < resources/windows/001-lua-unicode.diff
  fi

  meson compile -C "${build_dir}"

  if [[ $pgo != "" ]]; then
    cp -r data "${build_dir}/src"
    "${build_dir}/src/lite-xl"
    meson configure -Db_pgo=use "${build_dir}"
    meson compile -C "${build_dir}"
    rm -fr "${build_dir}/data"
  fi
}

main "$@"
