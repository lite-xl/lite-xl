#!/bin/sh
# C-tokenizer-core differential + throughput check. See diff.lua.
#
#   test/tokenizer/diff.sh [dir]      # dir defaults to the repo root
#
# Needs a build with the C core (src/api/tokenizer.c). Binary from $LITE_XL,
# then ./build/src/lite-xl, then PATH.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo=$(CDPATH= cd -- "$here/../.." && pwd)
target=${1:-$repo}

if [ -n "${LITE_XL:-}" ]; then bin=$LITE_XL
elif [ -x "$repo/build/src/lite-xl" ]; then
  bin=$repo/build/src/lite-xl
  # the in-tree binary looks for its data dir next to itself
  [ -e "$repo/build/src/data" ] || ln -sfn "$repo/data" "$repo/build/src/data"
elif command -v lite-xl >/dev/null 2>&1; then bin=lite-xl
else echo "no lite-xl binary: build one or set \$LITE_XL" >&2; exit 2
fi

LITE_USERDIR=$here LITE_XL_RUNTIME=diff exec "$bin" diff "$target"
