#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#import <Foundation/Foundation.h>

#include "bundle_open.h"

const char *resource_path_from_bundle()
{ @autoreleasepool
{
    NSFileManager* file_manager = [NSFileManager defaultManager];
    NSString* resource_path = [[NSBundle mainBundle] resourcePath];
    const char *resource_path_c = [resource_path UTF8String];
    size_t len = strlen(resource_path_c);
    char *resource_path_s = malloc(len + 1);
    if (resource_path_s) {
        memcpy(resource_path_s, resource_path_c, len + 1);
    }
    return resource_path_s;
}}

FILE* open_fp_from_bundle_or_fallback(const char *file, const char *mode)
{ @autoreleasepool
{
    FILE* fp = NULL;

    /* If the file mode is writable, skip all the bundle stuff because generally the bundle is read-only. */
    if(strcmp("r", mode) && strcmp("rb", mode)) {
        return fopen(file, mode);
    }

    NSFileManager* file_manager = [NSFileManager defaultManager];
    NSString* resource_path = [[NSBundle mainBundle] resourcePath];

    NSString* ns_string_file_component = [file_manager stringWithFileSystemRepresentation:file length:strlen(file)];

    NSString* full_path_with_file_to_try = [resource_path stringByAppendingPathComponent:ns_string_file_component];
    if([file_manager fileExistsAtPath:full_path_with_file_to_try]) {
        fp = fopen([full_path_with_file_to_try fileSystemRepresentation], mode);
    } else {
        fp = fopen(file, mode);
    }

    return fp;
}}

