#!/bin/bash
set -ex

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."; exit 1
fi

show_help() {
  echo
  echo "Lite XL dependecies installer. Mainly used for CI but can also work on users systems."
  echo "USE IT AT YOUR OWN RISK!"
  echo
  echo "Usage: $0 <OPTIONS>"
  echo
  echo "Available options:"
  echo
  echo "-l --lhelper              Install tools required by LHelper and doesn't"
  echo "                          install external libraries."
  echo "   --debug                Debug this script."
  echo
}

main() {
  local lhelper=false

  for i in "$@"; do
    case $i in
      -s|--lhelper)
        lhelper=true
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

  if [[ -n $1 ]]; then
    show_help
    exit 1
  fi

  if [[ "$OSTYPE" == "linux"* ]]; then
    if [[ $lhelper == true ]]; then
      sudo apt-get install -qq ninja-build
    else
      sudo apt-get install -qq ninja-build wayland-protocols libsdl2-dev libfreetype6
    fi
    pip3 install meson
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ $lhelper == true ]]; then
      brew install bash md5sha1sum ninja
    else
      brew install bash ninja sdl2
    fi
    pip3 install meson
    cd ~; npm install appdmg; cd -
    ~/node_modules/appdmg/bin/appdmg.js --version
  elif [[ "$OSTYPE" == "msys" ]]; then
    if [[ $lhelper == true ]]; then
      pacman --noconfirm -S \
        ${MINGW_PACKAGE_PREFIX}-{gcc,meson,ninja,ntldd,pkg-config,mesa} unzip
    else
      pacman --noconfirm -S \
        ${MINGW_PACKAGE_PREFIX}-{gcc,meson,ninja,ntldd,pkg-config,mesa,freetype,pcre2,SDL2} unzip
    fi
  fi
}

main "$@"
