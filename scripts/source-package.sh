#!/bin/bash
set -ex

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Lite XL."
  exit 1
fi

show_help(){
  echo
  echo "Usage: $0 <OPTIONS>"
  echo
  echo "Available options:"
  echo
  echo "-b --builddir DIRNAME     Sets the name of the build directory (no path)."
  echo "                          Default: 'build'."
  echo "-d --destdir DIRNAME      Sets the name of the install directory (no path)."
  echo
}

BUILD_DIR=build
DEST_DIR=lite-xl-src

for i in "$@"; do
  case $i in
    -h|--belp)
      show_help
      exit 0
      ;;
    -b|--builddir)
      BUILD_DIR="$2"
      shift
      shift
      ;;
    -d|--destdir)
      DEST_DIR="$2"
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

if test -d ${BUILD_DIR}; then rm -rf ${BUILD_DIR}; fi
if test -d ${DEST_DIR}; then rm -rf ${DEST_DIR}; fi
if test -f ${DEST_DIR}.tar.gz; then rm ${DEST_DIR}.tar.gz; fi

meson subprojects download
meson setup ${BUILD_DIR}

rsync -arv \
  --exclude /*build*/ \
  --exclude *.git* \
  --exclude lhelper \
  --exclude lite-xl* \
  --exclude submodules \
  . ${DEST_DIR}

cp "${BUILD_DIR}/start.lua" "${DEST_DIR}/data/core"

tar rf ${DEST_DIR}.tar ${DEST_DIR}
gzip -9 ${DEST_DIR}.tar
