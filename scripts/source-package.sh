#!/bin/bash
set -ex
echo $0
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
  echo "-d --destdir DIRNAME     Sets the name of the install directory (no path)."
  echo
}

for i in "$@"; do
  case $i in
    -h|--belp)
      show_help
      exit 0
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

if test -d ${DEST_DIR}; then rm -rf ${DEST_DIR}; fi
if test -f ${DEST_DIR}.tar.gz; then rm ${DEST_DIR}.tar.gz; fi

meson subprojects download

rsync -arv \
  --exclude /*build*/ \
  --exclude *.git* \
  --exclude lhelper \
  --exclude lite-xl* \
  --exclude submodules \
  . ${DEST_DIR}

tar rf ${DEST_DIR}.tar ${DEST_DIR}
gzip -9 ${DEST_DIR}.tar
