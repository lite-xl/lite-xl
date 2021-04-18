#import <Foundation/Foundation.h>

#include "bundle_open.h"

void set_macos_bundle_resources(lua_State *L)
{ @autoreleasepool
{
    NSString* resource_path = [[NSBundle mainBundle] resourcePath];
    lua_pushstring(L, [resource_path UTF8String]);
    lua_setglobal(L, "MACOS_RESOURCES");
}}

