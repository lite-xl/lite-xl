#!/bin/bash

cxxcompiler="g++"
cxxflags="-Wall -O3 -g -std=c++03 -fno-exceptions -fno-rtti -Isrc -Ilib/font_renderer"
cxxflags+=" -DFONT_RENDERER_HEIGHT_HACK"
for package in libagg freetype2; do
  cxxflags+=" $(pkg-config --cflags $package)"
done

echo "compiling font renderer library..."

for f in `find lib -name "*.cpp"`; do
  $cxxcompiler -c $cxxflags $f -o "${f//\//_}.o"
  if [[ $? -ne 0 ]]; then
    got_error=true
  fi
done

if [[ $got_error ]]; then
  rm -f *.o
  exit 1
fi

ar -rcs libfontrenderer.a *.o

rm *.o
echo "font renderer library created"
