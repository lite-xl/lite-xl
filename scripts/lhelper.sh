#!/bin/bash
set -e

show_help() {
  echo
  echo "Usage: $0 <OPTIONS>"
  echo
  echo "Available options:"
  echo
  echo "   --debug                Debug this script."
  echo "-h --help                 Show this help and exit."
  echo "-p --prefix PREFIX        Install directory prefix."
  echo "                          Default: '$HOME/.local'."
  echo
}

main() {
  local lhelper_prefix="$HOME/.local"

  for i in "$@"; do
    case $i in
      -h|--help)
        show_help
        exit 0
        ;;
      -p|--prefix)
        lhelper_prefix="$2"
        echo "LHelper prefix set to: \"${lhelper_prefix}\""
        shift
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

  if [[ ! -f ${lhelper_prefix}/bin/lhelper ]]; then

    git clone https://github.com/franko/lhelper.git

    # FIXME: This should be set in ~/.bash_profile if not using CI
    # export PATH="${HOME}/.local/bin:${PATH}"
    mkdir -p "${lhelper_prefix}/bin"
    pushd lhelper; bash install "${lhelper_prefix}"; popd

    if [[ "$OSTYPE" == "darwin"* ]]; then
      CC=clang CXX=clang++ lhelper create lite-xl -n
    else
      lhelper create lite-xl -n
    fi
  fi

  # Not using $(lhelper activate lite-xl) to support CI
  source "$(lhelper env-source lite-xl)"

  lhelper install freetype2
  lhelper install sdl2 2.0.14-wait-event-timeout-1
  lhelper install pcre2

  # Help MSYS2 to find the SDL2 include and lib directories to avoid errors
  # during build and linking when using lhelper.
  if [[ "$OSTYPE" == "msys" ]]; then
    CFLAGS=-I${LHELPER_ENV_PREFIX}/include/SDL2
    LDFLAGS=-L${LHELPER_ENV_PREFIX}/lib
  fi
}

main
