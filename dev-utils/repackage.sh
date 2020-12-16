#!/bin/bash

# strip-components is normally set to 1 to strip the initial "data" from the
# directory path.
copy_directory_from_repo () {
  local tar_options=()
  if [[ $1 == --strip-components=* ]]; then
    tar_options+=($1)
    shift
  fi
  local dirname="$1"
  local destdir="$2"
  git archive master "$dirname" --format=tar | tar xf - -C "$destdir" "${tar_options[@]}"
}

assets=($(wget --no-check-certificate -q -nv -O- https://api.github.com/repos/franko/lite-xl/releases/latest | grep "browser_download_url" | cut -d '"' -f 4))

workdir=".repackage"
rm -fr "$workdir" && mkdir "$workdir" && pushd "$workdir"

for url in "${assets[@]}"; do
    wget --no-check-certificate "$url"
done

for filename in $(ls -1); do
    if [[ $filename == *".zip" ]]; then
        unzip "$filename"
    elif [[ $filename == *".tar."* ]]; then
        tar xf "$filename"
    fi
    rm "$filename"
    xcoredir="$(find lite-xl -type d -name 'core')"
    coredir="$(dirname $xcoredir)"
    echo "coredir: $coredir"
    for module_name in core plugins; do
      rm -fr "$coredir/$module_name"
      (cd .. && copy_directory_from_repo --strip-components=1 "data/$module_name" "$workdir/$coredir")
    done
    if [[ $filename == *".zip" ]]; then
        zip -r -9 "$filename" lite-xl
    elif [[ $filename == *".tar."* ]]; then
        tar czf "${filename/%.tar.*/.tar.gz}" lite-xl
    fi
    rm -fr lite-xl
done

popd

