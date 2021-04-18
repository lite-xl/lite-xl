#ifndef BUNDLE_OPEN_H
#define BUNDLE_OPEN_H

#include <stdio.h>

const char *resource_path_from_bundle();
FILE* open_fp_from_bundle_or_fallback(const char *file, const char *mode);

#endif
