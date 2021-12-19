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
  git archive "$lite_branch" "$dirname" --format=tar | tar xf - -C "$destdir" "${tar_options[@]}"
}

lite_copy_third_party_modules () {
    local build="$1"
    curl --retry 5 --retry-delay 3 --insecure -L "https://github.com/lite-xl/lite-xl-colors/archive/master.zip" -o "$build/lite-xl-colors.zip" || exit 1
    mkdir -p "$build/third/data/colors" "$build/third/data/plugins"
    unzip -qq "$build/lite-xl-colors.zip" -d "$build"
    mv "$build/lite-xl-colors-master/colors" "$build/third/data"
    rm -fr "$build/lite-xl-colors-master"
    rm "$build/lite-xl-colors.zip"
}

lite_branch=master
while [ ! -z ${1+x} ]; do
  case "$1" in
    -dir)
    use_dir="$(realpath $2)"
    shift 2
    ;;
    -branch)
    lite_branch="$2"
    shift 2
    ;;
    *)
    echo "unknown option: $1"
    exit 1
    ;;
  esac
done

wget="wget --retry-connrefused --waitretry=1 --read-timeout=20 --no-check-certificate" 

workdir=".repackage"
rm -fr "$workdir" && mkdir "$workdir" && pushd "$workdir"

fetch_packages_from_github () {
  assets=($($wget -q -nv -O- https://api.github.com/repos/lite-xl/lite-xl/releases/latest | grep "browser_download_url" | cut -d '"' -f 4))

  for url in "${assets[@]}"; do
    echo "getting: $url"
    $wget -q "$url" || exit 1
  done
}

fetch_packages_from_dir () {
  for file in "$1"/*.zip "$1"/*.tar.* ; do
    echo "copying file $file"
    cp "$file" .
  done
}

if [ -z ${use_dir+x} ]; then
  fetch_packages_from_github
else
  fetch_packages_from_dir "$use_dir"
fi

lite_copy_third_party_modules "."

for filename in $(ls -1 *.zip *.tar.*); do
    if [[ $filename == *".zip" ]]; then
        unzip -qq "$filename"
    elif [[ $filename == *".tar."* ]]; then
        tar xf "$filename"
    fi
    rm "$filename"
    find lite-xl -name lite -exec chmod a+x '{}' \;
    start_file=$(find lite-xl -name start.lua)
    lite_version=$(cat "$start_file" | awk 'match($0, /^\s*VERSION\s*=\s*"(.+)"/, a) { print(a[1]) }')
    xcoredir="$(find lite-xl -type d -name 'core')"
    coredir="$(dirname $xcoredir)"
    echo "coredir: $coredir"
    cp -r "lite-xl" "lite-xl.original"
    for module_name in core plugins colors; do
        rm -fr "$coredir/$module_name"
        (cd .. && copy_directory_from_repo --strip-components=1 "data/$module_name" "$workdir/$coredir")
    done
    sed -i "s/@PROJECT_VERSION@/$lite_version/g" "$start_file"
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

