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
  echo "-d --destdir DIRNAME      Set the name of the package directory (not path)."
  echo "                          Default: 'lite-xl'."
  echo "-h --help                 Show this help and exit."
  echo "-p --prefix PREFIX        Install directory prefix. Default: '/'."
  echo "-v --version VERSION      Sets the version on the package name."
  echo "-a --addons               Install 3rd party addons."
  echo "   --debug                Debug this script."
  echo "-A --appimage             Create an AppImage (Linux only)."
  echo "-B --binary               Create a normal / portable package or macOS bundle,"
  echo "                          depending on how the build was configured. (Default.)"
  echo "-D --dmg                  Create a DMG disk image with AppDMG (macOS only)."
  echo "-I --innosetup            Create a InnoSetup package (Windows only)."
  echo "-r --release              Strip debugging symbols."
  echo "-S --source               Create a source code package,"
  echo "                          including subprojects dependencies."
  echo
}

source_package() {
  local build_dir=build-src
  local package_name=$1

  rm -rf ${build_dir}
  rm -rf ${package_name}
  rm -f ${package_name}.tar.gz

  meson subprojects download
  meson setup ${build_dir} -Dsource-only=true

  # Note: not using git-archive(-all) because it can't include subprojects ignored by git
  rsync -arv \
    --exclude /*build*/ \
    --exclude *.git* \
    --exclude lhelper \
    --exclude lite-xl* \
    --exclude submodules \
    . ${package_name}

  cp "${build_dir}/start.lua" "${package_name}/data/core"

  tar rf ${package_name}.tar ${package_name}
  gzip -9 ${package_name}.tar
}

main() {
  local arch="$(uname -m)"
  local platform="$(get_platform_name)"
  local build_dir="$(get_default_build_dir)"
  local dest_dir=lite-xl
  local prefix=/
  local version
  local addons=false
  local appimage=false
  local binary=false
  local dmg=false
  local innosetup=false
  local release=false
  local source=false

  # store the current flags to easily pass them to appimage script
  local flags="$@"

  for i in "$@"; do
    case $i in
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
      -h|--help)
        show_help
        exit 0
        ;;
      -p|--prefix)
        prefix="$2"
        shift
        shift
        ;;
      -v|--version)
        if [[ -n $2 ]]; then version="-$2"; fi
        shift
        shift
        ;;
      -A|--appimage)
        if [[ "$platform" != "linux" ]]; then
          echo "Warning: ignoring --appimage option, works only under Linux."
        else
          appimage=true
        fi
        shift
        ;;
      -B|--binary)
        binary=true
        shift
        ;;
      -D|--dmg)
        if [[ "$platform" != "macos" ]]; then
          echo "Warning: ignoring --dmg option, works only under macOS."
        else
          dmg=true
        fi
        shift
        ;;
      -I|--innosetup)
        if [[ "$platform" != "windows" ]]; then
          echo "Warning: ignoring --innosetup option, works only under Windows."
        else
          innosetup=true
        fi
        shift
        ;;
      -r|--release)
        release=true
        shift
        ;;
      -S|--source)
        source=true
        shift
        ;;
      -a|--addons)
        addons=true
        shift
        ;;
      --debug)
        set -x
        shift
        ;;
      *)
        # unknown option
        ;;
    esac
  done

  if [[ -n $1 ]]; then show_help; exit 1; fi

  # The source package doesn't require a previous build,
  # nor the following install step, so run it now.
  if [[ $source == true ]]; then source_package "lite-xl$version-src"; fi

  # No packages request
  if [[ $appimage == false && $binary == false && $dmg == false && $innosetup == false ]]; then
    # Source only, return.
    if [[ $source == true ]]; then return 0; fi
    # Build the binary package as default instead doing nothing.
    binary=true
  fi

  rm -rf "${dest_dir}"

  DESTDIR="$(pwd)/${dest_dir}" meson install --skip-subprojects -C "${build_dir}"

  local data_dir="$(pwd)/${dest_dir}/data"
  local exe_file="$(pwd)/${dest_dir}/lite-xl"

  local package_name=lite-xl$version-$platform-$arch
  local bundle=false
  local portable=false
  local stripcmd="strip"

  if [[ -d "${data_dir}" ]]; then
    echo "Creating a portable, compressed archive..."
    portable=true
    exe_file="$(pwd)/${dest_dir}/lite-xl"
    if [[ $platform == "windows" ]]; then
      exe_file="${exe_file}.exe"
      stripcmd="strip --strip-all"
    else
      # Windows archive is always portable
      package_name+="-portable"
    fi
  elif [[ $platform == "macos" && ! -d "${data_dir}" ]]; then
    data_dir="$(pwd)/${dest_dir}/Contents/Resources"
    if [[ -d "${data_dir}" ]]; then
      echo "Creating a macOS bundle application..."
      bundle=true
      # Specify "bundle" on compressed archive only, implicit on images
      if [[ $dmg == false ]]; then package_name+="-bundle"; fi
      rm -rf "Lite XL.app"; mv "${dest_dir}" "Lite XL.app"
      dest_dir="Lite XL.app"
      exe_file="$(pwd)/${dest_dir}/Contents/MacOS/lite-xl"
      data_dir="$(pwd)/${dest_dir}/Contents/Resources"
    fi
  fi

  if [[ $bundle == false && $portable == false ]]; then
    data_dir="$(pwd)/${dest_dir}/$prefix/share/lite-xl"
    exe_file="$(pwd)/${dest_dir}/$prefix/bin/lite-xl"
  fi

  mkdir -p "${data_dir}"

  if [[ $addons == true ]]; then
    addons_download "${build_dir}"
    addons_install "${build_dir}" "${data_dir}"
  fi

  # TODO: use --skip-subprojects when 0.58.0 will be available on supported
  # distributions to avoid subprojects' include and lib directories to be copied.
  # Install Meson with PIP to get the latest version is not always possible.
  pushd "${dest_dir}"
  find . -type d -name 'include' -prune -exec rm -rf {} \;
  find . -type d -name 'lib' -prune -exec rm -rf {} \;
  find . -type d -empty -delete
  popd

  if [[ $release == true ]]; then
    $stripcmd "${exe_file}"
  fi

  echo "Creating a compressed archive ${package_name}"
  if [[ $binary == true ]]; then
    rm -f "${package_name}".tar.gz
    rm -f "${package_name}".zip

    if [[ $platform == "windows" ]]; then
      zip -9rv ${package_name}.zip ${dest_dir}/*
    else
      tar czvf "${package_name}".tar.gz "${dest_dir}"
    fi
  fi

  if [[ $appimage == true ]]; then
    source scripts/appimage.sh $flags --static
  fi
  if [[ $bundle == true && $dmg == true ]]; then
    source scripts/appdmg.sh "${package_name}"
  fi
  if [[ $innosetup == true ]]; then
    source scripts/innosetup/innosetup.sh -b "${build_dir}"
  fi
}

main "$@"
