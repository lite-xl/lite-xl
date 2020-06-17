#!/bin/bash

cflags="-Wall -O3 -g -std=gnu11 -fno-strict-aliasing -Isrc -Ilib/font_renderer"
cxxflags="-Wall -O3 -g -std=c++03 -fno-exceptions -fno-rtti -Isrc -Ilib/font_renderer"
libcflags=
lflags=
for package in libagg freetype2 lua5.2; do
  libcflags+=" $(pkg-config --cflags $package)"
  lflags+=" $(pkg-config --libs $package)"
done
libcflags+=" $(sdl2-config --cflags)"
lflags+=" $(sdl2-config --libs) -lm"

if [[ $* == *windows* ]]; then
  echo "cross compiling for windows is not yet supported"
  exit 1
else
  platform="unix"
  outfile="lite"
  compiler="gcc"
  cxxcompiler="g++"
fi

echo "compiling ($platform)..."
for f in `find src -name "*.c"`; do
  $compiler -c $cflags $f -o "${f//\//_}.o" $libcflags
  if [[ $? -ne 0 ]]; then
    got_error=true
  fi
done

for f in `find lib -name "*.cpp"`; do
  $cxxcompiler -c $cxxflags $f -o "${f//\//_}.o" $libcflags
  if [[ $? -ne 0 ]]; then
    got_error=true
  fi
done

if [[ ! $got_error ]]; then
  echo "linking..."
  $cxxcompiler -o $outfile *.o $lflags
fi

echo "cleaning up..."
rm *.o
echo "done"

