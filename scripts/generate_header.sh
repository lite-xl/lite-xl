#!/bin/bash

##### CONFIG

# symbols to ignore
IGNORE_SYM='luaL_pushmodule'

##### CONFIG


# https://stackoverflow.com/a/13062682
uncomment() {
  [ $# -eq 2 ] && arg="$1" || arg=""
  eval file="\$$#"
  sed 's/a/aA/g; s/__/aB/g; s/#/aC/g' "$file" | \
    gcc -P -E $arg - | \
    sed 's/aC/#/g; s/aB/__/g; s/aA/a/g'
}

# this is the magic that turns multiline statements into
# single line statements
# LITERALLY DOES NOT WORK WITH PREPROCESSOR
onelineize() {
  grep -v '^#' | sed -e ':r;$!{N;br};s/\([^{;]\)\n\s*/\1 /g'
}

discard_preprocessors() {
  grep -v '#\(include\|if\|endif\)'
}

# sed regex for extracting data from function signature
# if this isn't regex, idk what is
# LUA_API (return type as \2) (function name as \3) (args as \4)
sym_regex='^LUA\(LIB\)\?_API\s\+\([^(]\+\)\s*(\([^)]\+\))\s\+(\([^)]\+\));'

# get funcptr declarations
ptrize() {
  grep '^LUA' | grep -v "$IGNORE_SYM" | sed -e "s/$sym_regex/static\t\2(*\3)\t(\4);/"
}

# create a stub function that warns user when calling it
makestub() {
  grep '^LUA' | grep -v "$IGNORE_SYM" | sed -e "s/$sym_regex/static\t\2\t__lite_xl_fallback_\3\t(\4) { fputs(\"warning: \3 is a stub\", stderr); }/"
}

import_sym() {
  grep '^LUA' | grep -v "$IGNORE_SYM" | sed -e "s/$sym_regex/\tIMPORT_SYMBOL(\3, \2, \4);/"
}

decl() {
  echo "/** $(basename "$1") **/"
  echo

  header="$(uncomment $1 | discard_preprocessors)"
  header1="$(onelineize <<< "$header")"

  # typedef
  grep -v '^\(LUA\|#\|extern\)' <<< "$header1"
  # funcptrs
  ptrize <<< "$header1"
  # defines
  (grep '^#' | grep -v "$IGNORE_SYM") <<< "$header"
  # stubs
  makestub <<< "$header1"
}

decl_import() {
  uncomment $1 | onelineize | import_sym
}

generate_header() {
  local LUA_PATH="$1"
  echo "#ifndef LITE_XL_PLUGIN_API"
  echo "#define LITE_XL_PLUGIN_API"
  echo "/**"
  echo "The lite_xl plugin API is quite simple. Any shared library can be a plugin file, so long"
  echo "as it has an entrypoint that looks like the following, where xxxxx is the plugin name:"
  echo '#include "lite_xl_plugin_api.h"'
  echo "int luaopen_lite_xl_xxxxx(lua_State* L, void* XL) {"
  echo "  lite_xl_plugin_init(XL);"
  echo "  ..."
  echo "  return 1;"
  echo "}"
  echo "In linux, to compile this file, you'd do: 'gcc -o xxxxx.so -shared xxxxx.c'. Simple!"
  echo "Due to the way the API is structured, you *should not* link or include lua libraries."
  echo "This file was automatically generated. DO NOT MODIFY DIRECTLY."
  echo "**/"
  echo
  echo
  echo "#include <stdarg.h>"
  echo "#include <stdio.h> // for BUFSIZ? this is kinda weird"
  echo
  echo "/** luaconf.h **/"
  echo
  uncomment "$LUA_PATH/luaconf.h"
  echo

  decl "$LUA_PATH/lua.h"
  echo
  decl "$LUA_PATH/lauxlib.h"
  echo "static  void (*luaL_openlibs)      (lua_State *L);"
  echo 'static  void  __lite_xl_fallback_luaL_openlibs    (lua_State *L) { fputs("warning: luaL_openlibs is a stub", stderr); }'
  echo

  echo "#define IMPORT_SYMBOL(name, ret, ...) name = (name = (ret (*) (__VA_ARGS__)) symbol(#name), name == NULL ? &__lite_xl_fallback_##name : name)"
  echo "static void lite_xl_plugin_init(void *XL) {"
  echo -e "\tvoid* (*symbol)(const char *) = (void* (*) (const char *)) XL;"

  decl_import "$LUA_PATH/lua.h"
  decl_import "$LUA_PATH/lauxlib.h"
  echo -e "\tIMPORT_SYMBOL(luaL_openlibs, void, lua_State* L);"

  echo "}"
  echo "#endif"
}

show_help() {
  echo -e "Usage: $0 <OPTIONS> prefix"
  echo
  echo -e "Available options:"
  echo -e "-p\t--prefix\tSet prefix (where to find lua.h and lauxlib.h)"
}

main() {
  local prefix=""

  for i in "$@"; do
    case $i in
      -h|--help)
        show_help
        exit 0
        ;;
      -p|--prefix)
        prefix="$2"
        shift
        shift
        ;;
      *)
        ;;
    esac
  done

  generate_header "$prefix"
}

main "$@"
# create a stub function that warns user when calling it
