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
  echo "--version    Use this version instead of git tags or GitHub outputs."
  echo "--debug      Debug this script."
  echo "--help       Show this message."
  echo
}

main() {
  local version

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
    if [[ "$GITHUB_REF" == "refs/tags/"* ]]; then
      version="${GITHUB_REF##*/}"
    else
      version="$(git describe --tags $(git rev-list --tags --max-count=1))"
      if [[ $? -ne 0 ]]; then version=""; fi
    fi
  fi

  if [[ -z "$version" ]]; then
    echo "error: cannot get latest git tag"
    exit 1
  fi

  export RELEASE_TAG="$version"
  envsubst '$RELEASE_TAG' > release-notes.md < resources/release-notes.md
}

main "$@"
