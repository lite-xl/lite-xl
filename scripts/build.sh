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
  echo "-b --builddir DIRNAME         Sets the name of the build directory (not path)."
  echo "                              Default: '$(get_default_build_dir)'."
  echo "   --debug                    Debug this script."
  echo "-f --forcefallback            Force to build dependencies statically."
  echo "-h --help                     Show this help and exit."
  echo "-d --debug-build              Builds a debug build."
  echo "-p --prefix PREFIX            Install directory prefix. Default: '/'."
  echo "-B --bundle                   Create an App bundle (macOS only)"
  echo "-A --addons                   Install extra plugins."
  echo "                              Default: If specified, install the welcome plugin."
  echo "                              An comma-separated list can be specified after this flag"
  echo "                              to specify a list of plugins to install."
  echo "                              If this option is not specified, no extra plugins will be installed."
  echo "-P --portable                 Create a portable binary package."
  echo "-r --reconfigure              Tries to reuse the meson build directory, if possible."
  echo "                              Default: Deletes the build directory and recreates it."
  echo "-O --pgo                      Use profile guided optimizations (pgo)."
  echo "                              macOS: disabled when used with --bundle,"
  echo "                              Windows: Implicit being the only option."
  echo "   --cross-platform PLATFORM  Cross compile for this platform."
  echo "                              The script will find the appropriate"
  echo "                              cross file in 'resources/cross'."
  echo "   --cross-arch ARCH          Cross compile for this architecture."
  echo "                              The script will find the appropriate"
  echo "                              cross file in 'resources/cross'."
  echo "   --cross-file CROSS_FILE    Cross compile with the given cross file."
  echo
}

main() {
  local platform="$(get_platform_name)"
  local arch="$(get_platform_arch)"
  local build_dir
  local plugins="-Dbundle_plugins="
  local prefix=/
  local build_type="release"
  local force_fallback
  local bundle="-Dbundle=false"
  local portable="-Dportable=false"
  local pgo
  local cross
  local cross_platform
  local cross_arch
  local cross_file
  local reconfigure
  local lpm_path
  local should_reconfigure
  local destdir="lite-xl"

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
      -d|--debug-build)
        build_type="debug"
        shift
        ;;
      -r|--reconfigure)
        should_reconfigure=true
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
      -A|--addons)
        if [[ -n $2 ]] && [[ $2 != -* ]]; then
          plugins="-Dbundle_plugins=$2"
          shift
        else
          plugins="-Dbundle_plugins=welcome"
        fi
        shift
        ;;
      -B|--bundle)
        if [[ "$platform" != "darwin" ]]; then
          echo "Warning: ignoring --bundle option, works only under macOS."
        else
          bundle="-Dbundle=true"
          destdir="Lite XL.app"
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
      --cross-arch)
        cross="true"
        cross_arch="$2"
        shift
        shift
        ;;
      --cross-platform)
        cross="true"
        cross_platform="$2"
        shift
        shift
        ;;
      --cross-file)
        cross="true"
        cross_file="$2"
        shift
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

  if [[ $platform == "macos" && $bundle == "-Dbundle=true" && $portable == "-Dportable=true" ]]; then
      echo "Warning: \"bundle\" and \"portable\" specified; excluding portable package."
      portable=""
  fi

  # if CROSS_ARCH is used, it will be picked up
  cross="${cross:-$CROSS_ARCH}"
  if [[ -n "$cross" ]]; then
    if [[ -n "$cross_file" ]] && ([[ -z "$cross_arch" ]] || [[ -z "$cross_platform" ]]); then
      echo "Warning: --cross-platform or --cross-platform not set; guessing it from the filename."
      # remove file extensions and directories from the path
      cross_file_name="${cross_file##*/}"
      cross_file_name="${cross_file_name%%.*}"
      # cross_platform is the string before encountering the first hyphen
      if [[ -z "$cross_platform" ]]; then
        cross_platform="${cross_file_name%%-*}"
        echo "Warning: Guessing --cross-platform $cross_platform"
      fi
      # cross_arch is the string after encountering the first hyphen
      if [[ -z "$cross_arch" ]]; then
        cross_arch="${cross_file_name#*-}"
        echo "Warning: Guessing --cross-arch $cross_arch"
      fi
    fi
    platform="${cross_platform:-$platform}"
    arch="${cross_arch:-$arch}"
    cross_file="--cross-file ${cross_file:-resources/cross/$platform-$arch.txt}"
    # reload build_dir because platform and arch might change
    if [[ "$build_dir" == "" ]]; then
      build_dir="$(get_default_build_dir "$platform" "$arch")"
    fi
  elif [[ "$build_dir" == "" ]]; then
    build_dir="$(get_default_build_dir)"
  fi

  # arch and platform specific stuff
  if [[ "$platform" == "macos" ]]; then
    macos_version_min="10.11"
    if [[ "$arch" == "arm64" ]]; then
      macos_version_min="11.0"
    fi
    export MACOSX_DEPLOYMENT_TARGET="$macos_version_min"
    export MIN_SUPPORTED_MACOSX_DEPLOYMENT_TARGET="$macos_version_min"
    export CFLAGS="-mmacosx-version-min=$macos_version_min"
    export CXXFLAGS="-mmacosx-version-min=$macos_version_min"
    export LDFLAGS="-mmacosx-version-min=$macos_version_min"
  fi

  if [[ $should_reconfigure == true ]] && [[ -d "${build_dir}" ]]; then
    reconfigure="--reconfigure"
  elif [[ -d "${build_dir}" ]]; then
    rm -rf "${build_dir}"
  fi

  if [[ -n "$plugins" ]] && [[ -z `command -v lpm` ]]; then
    mkdir -p "${build_dir}"
    lpm_path="$(pwd)/${build_dir}/lpm$(get_executable_extension)"
    if [[ ! -e "$lpm_path" ]]; then
      curl --insecure -L -o "$lpm_path" \
        "https://github.com/lite-xl/lite-xl-plugin-manager/releases/download/${LPM_VERSION:-latest}/lpm.$(get_platform_tuple)$(get_executable_extension)"
      chmod u+x "$lpm_path"
    fi
    export PATH="$(dirname "$lpm_path"):$PATH"
  fi

  CFLAGS=$CFLAGS LDFLAGS=$LDFLAGS meson setup \
    "${build_dir}" \
    --buildtype "$build_type" \
    --prefix "$prefix" \
    $cross_file \
    $force_fallback \
    $bundle \
    $portable \
    $pgo \
    $plugins \
    $reconfigure

  meson compile -C "${build_dir}"


  if [[ $pgo != "" ]]; then
    cp -r data "${build_dir}/src"
    "${build_dir}/src/lite-xl"
    meson configure -Db_pgo=use "${build_dir}"
    meson compile -C "${build_dir}"
    rm -fr "${build_dir}/src/data"
  fi

  meson install -C "${build_dir}" --destdir "$destdir" \
    --skip-subprojects=freetype2,lua,pcre2,sdl2 --no-rebuild
}

main "$@"
