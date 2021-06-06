#import <Foundation/Foundation.h>
#include "lua.h"

void set_macos_bundle_resources(lua_State *L)
{ @autoreleasepool
{
    /* Use resolved executablePath instead of resourcePath to allow lanching
       the lite-xl binary via a symlink, like typically done by Homebrew:

    /usr/local/bin/lite-xl -> /Applications/lite-xl.app/Contents/MacOS/lite-xl

       The resourcePath returns /usr/local in this case instead of
       /Applications/lite-xl.app/Contents/Resources, which makes later
       access to the resource files fail. Resolving the symlink to the
       executable and then the relative path to the expected directory
       Resources is a workaround for starting the application from both
       the launcher directly and the command line via the symlink.
     */
    NSString* executable_path = [[NSBundle mainBundle] executablePath];
    char resolved_path[PATH_MAX + 16 + 1];
    realpath([executable_path UTF8String], resolved_path);
    strcat(resolved_path, "/../../Resources");
    char resource_path[PATH_MAX + 1];
    realpath(resolved_path, resource_path);
    lua_pushstring(L, resource_path);
    lua_setglobal(L, "MACOS_RESOURCES");
}}


/* Thanks to mathewmariani, taken from his lite-macos github repository. */
void enable_momentum_scroll() {
  [[NSUserDefaults standardUserDefaults]
    setBool: YES
    forKey: @"AppleMomentumScrollSupported"];
}

