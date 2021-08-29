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
  echo "                          macOS: disabled when used with --bundle,"
  echo "                          Windows: Implicit being the only option."
  echo
}

main() {
  local platform="$(get_platform_name)"
  local build_dir="$(get_default_build_dir)"
  local prefix=/
  local force_fallback
  local bundle
  local portable

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

  rm -rf "${build_dir}"

  CFLAGS=$CFLAGS LDFLAGS=$LDFLAGS meson setup \
    --buildtype=release \
    --prefix "$prefix" \
    $force_fallback \
    $bundle \
    $portable \
    "${build_dir}"

  meson compile -C "${build_dir}"
}

main "$@"
