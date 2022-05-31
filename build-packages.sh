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
  echo "Common options:"
  echo
  echo "-h --help                 Show this help and exit."
  echo "-b --builddir DIRNAME     Set the name of the build directory (not path)."
  echo "                          Default: '$(get_default_build_dir)'."
  echo "-p --prefix PREFIX        Install directory prefix."
  echo "                          Default: '/'."
  echo "   --debug                Debug this script."
  echo
  echo "Build options:"
  echo
  echo "-f --forcefallback        Force to build subprojects dependencies statically."
  echo "-B --bundle               Create an App bundle (macOS only)"
  echo "-P --portable             Create a portable package."
  echo "-O --pgo                  Use profile guided optimizations (pgo)."
  echo "                          Requires running the application iteractively."
  echo
  echo "Package options:"
  echo
  echo "-d --destdir DIRNAME      Set the name of the package directory (not path)."
  echo "                          Default: 'lite-xl'."
  echo "-v --version VERSION      Sets the version on the package name."
  echo "-A --appimage             Create an AppImage (Linux only)."
  echo "-D --dmg                  Create a DMG disk image (macOS only)."
  echo "                          Requires NPM and AppDMG."
  echo "-I --innosetup            Create an InnoSetup installer (Windows only)."
  echo "-r --release              Compile in release mode."
  echo "-S --source               Create a source code package,"
  echo "                          including subprojects dependencies."
  echo
}

main() {
  local build_dir
  local build_dir_option=()
  local dest_dir
  local dest_dir_option=()
  local prefix
  local prefix_option=()
  local version
  local version_option=()
  local debug
  local force_fallback
  local appimage
  local bundle
  local innosetup
  local portable
  local pgo
  local release

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
      -d|--destdir)
        dest_dir="$2"
        shift
        shift
        ;;
      -f|--forcefallback)
        force_fallback="--forcefallback"
        shift
        ;;
      -p|--prefix)
        prefix="$2"
        shift
        shift
        ;;
      -v|--version)
        version="$2"
        shift
        shift
        ;;
      -A|--appimage)
        appimage="--appimage"
        shift
        ;;
      -B|--bundle)
        bundle="--bundle"
        shift
        ;;
      -D|--dmg)
        dmg="--dmg"
        shift
        ;;
      -I|--innosetup)
        innosetup="--innosetup"
        shift
        ;;
      -P|--portable)
        portable="--portable"
        shift
        ;;
      -r|--release)
        release="--release"
        shift
        ;;
      -S|--source)
        source="--source"
        shift
        ;;
      -O|--pgo)
        pgo="--pgo"
        shift
        ;;
      --debug)
        debug="--debug"
        set -x
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

  if [[ -n $build_dir ]]; then build_dir_option=("--builddir" "${build_dir}"); fi
  if [[ -n $dest_dir ]]; then dest_dir_option=("--destdir" "${dest_dir}"); fi
  if [[ -n $prefix ]]; then prefix_option=("--prefix" "${prefix}"); fi
  if [[ -n $version ]]; then version_option=("--version" "${version}"); fi

  source scripts/build.sh \
    ${build_dir_option[@]} \
    ${prefix_option[@]} \
    $debug \
    $force_fallback \
    $bundle \
    $portable \
    $release \
    $pgo

  source scripts/package.sh \
    ${build_dir_option[@]} \
    ${dest_dir_option[@]} \
    ${prefix_option[@]} \
    ${version_option[@]} \
    --binary \
    --addons \
    $debug \
    $appimage \
    $dmg \
    $innosetup \
    $release \
    $source
}

main "$@"
