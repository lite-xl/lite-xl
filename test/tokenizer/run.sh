#!/bin/sh
# Golden-token corpus runner. See run.lua for what it does.
#
#   test/tokenizer/run.sh            # check the corpus against golden.txt
#   test/tokenizer/run.sh record     # regenerate golden.txt
#   LITE_XL=/path/to/lite-xl test/tokenizer/run.sh
#
# Picks the binary from $LITE_XL, then ./build/src/lite-xl, then PATH.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/../.." && pwd)
mode=${1:-check}

if [ -n "${LITE_XL:-}" ]; then
  bin=$LITE_XL
elif [ -x "$repo/build/src/lite-xl" ]; then
  bin=$repo/build/src/lite-xl
  # the in-tree binary looks for its data dir next to itself
  [ -e "$repo/build/src/data" ] || ln -sfn "$repo/data" "$repo/build/src/data"
elif command -v lite-xl >/dev/null 2>&1; then
  bin=lite-xl
else
  echo "no lite-xl binary: build one or set \$LITE_XL" >&2
  exit 2
fi

# LITE_USERDIR puts run.lua on package.path; LITE_XL_RUNTIME swaps it in for
# `core`, so the editor never opens a window.
LITE_USERDIR=$here LITE_XL_RUNTIME=run exec "$bin" "$mode" "$here"
