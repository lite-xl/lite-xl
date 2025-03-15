#!/usr/bin/env bash

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."; exit 1
fi

show_help() {
  echo
  echo "Release notes generator for lite-xl releases."
  echo "USE IT AT YOUR OWN RISK!"
  echo
  echo "Usage: $0 <OPTIONS>"
  echo
  echo "Available options:"
  echo
  echo "--version    The current version used to generate release notes."
  echo "--debug      Debug this script."
  echo "--help       Show this message."
  echo
}

main() {
  local version
  local last_version

  for i in "$@"; do
    case $i in
      --debug)
        set -x
        shift
        ;;
      --help)
        show_help
        exit 0
        ;;
      --version)
        version="$2"
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
    exit 0
  fi

  if [[ -z "$version" ]]; then
    echo "error: a version must be provided"
    exit 1
  fi

  # use gh cli to get the last version
  read -r last_version < <(gh release list --exclude-pre-releases --limit 1 | awk 'BEGIN {FS="\t"}; {print $3}')
  if [[ -z "$last_version" ]]; then
    echo "error: cannot get last release git tag"
    exit 1
  fi

  export RELEASE_TAG="$version"
  export LAST_RELEASE_TAG="$last_version"
  envsubst '$RELEASE_TAG:$LAST_RELEASE_TAG' > release-notes.md < resources/release-notes.md
}

main "$@"
