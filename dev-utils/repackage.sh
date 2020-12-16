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

lite_copy_third_party_modules () {
    local build="$1"
    curl --insecure -L "https://github.com/rxi/lite-colors/archive/master.zip" -o "$build/rxi-lite-colors.zip"
    mkdir -p "$build/third/data/colors" "$build/third/data/plugins"
    unzip -qq "$build/rxi-lite-colors.zip" -d "$build"
    mv "$build/lite-colors-master/colors" "$build/third/data"
    rm -fr "$build/lite-colors-master"
    rm "$build/rxi-lite-colors.zip"
}

assets=($(wget --no-check-certificate -q -nv -O- https://api.github.com/repos/franko/lite-xl/releases/latest | grep "browser_download_url" | cut -d '"' -f 4))

workdir=".repackage"
rm -fr "$workdir" && mkdir "$workdir" && pushd "$workdir"

for url in "${assets[@]}"; do
    echo "getting: $url"
    wget -q --no-check-certificate "$url"
done

lite_copy_third_party_modules "."

for filename in $(ls -1 *.zip *.tar.*); do
    if [[ $filename == *".zip" ]]; then
        unzip -qq "$filename"
    elif [[ $filename == *".tar."* ]]; then
        tar xf "$filename"
    fi
    rm "$filename"
    if [ -f lite-xl/bin/lite ]; then
      chmod a+x lite-xl/bin/lite
    elif [ -f lite-xl/lite ]; then
      chmod a+x lite-xl/lite
    fi
    xcoredir="$(find lite-xl -type d -name 'core')"
    coredir="$(dirname $xcoredir)"
    echo "coredir: $coredir"
    cp -r "lite-xl" "lite-xl.original"
    for module_name in core plugins colors; do
        rm -fr "$coredir/$module_name"
        (cd .. && copy_directory_from_repo --strip-components=1 "data/$module_name" "$workdir/$coredir")
    done
    for module_name in plugins colors; do
        cp -r "third/data/$module_name" "$coredir"
    done
    if [[ $filename == *".zip" ]]; then
        zip -qq -r -9 "$filename" lite-xl
        diff -U 4 -r lite-xl.original lite-xl > "${filename/%.zip/.diff}"
    elif [[ $filename == *".tar."* ]]; then
        tar czf "${filename/%.tar.*/.tar.gz}" lite-xl
        diff -U 4 -r lite-xl.original lite-xl > "${filename/%.tar.*/.diff}"
    fi
    rm -fr lite-xl lite-xl.original
done

popd

