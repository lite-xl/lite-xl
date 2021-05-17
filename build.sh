#!/bin/bash

cflags+="-Wall -O3 -g -std=gnu11 -fno-strict-aliasing -Isrc -Ilib/font_renderer"
cflags+=" $(pkg-config --cflags lua5.2) $(sdl2-config --cflags)"
lflags="-static-libgcc -static-libstdc++"
for package in libagg freetype2 lua5.2 x11 libpcre2-8; do
  lflags+=" $(pkg-config --libs $package)"
done
lflags+=" $(sdl2-config --libs) -lm"

if [[ $* == *windows* ]]; then
  echo "cross compiling for windows is not yet supported"
  exit 1
else
  outfile="lite"
  compiler="gcc"
  cxxcompiler="g++"
fi

lib/font_renderer/build.sh || exit 1
libs=libfontrenderer.a

echo "compiling lite..."
for f in `find src -name "*.c"`; do
  $compiler -c $cflags $f -o "${f//\//_}.o"
  if [[ $? -ne 0 ]]; then
    got_error=true
  fi
done

if [[ ! $got_error ]]; then
  echo "linking..."
  $cxxcompiler -o $outfile *.o $libs $lflags
fi

echo "cleaning up..."
rm *.o *.a
echo "done"

