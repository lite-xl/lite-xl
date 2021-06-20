## Window creation for Retina displays

The file info.plist sets NSHighResolutionCapable to true. This is fine for High-DPI
and retina displays.

The `SDL_CreateWindow` is called with the flag `SDL_WINDOW_ALLOW_HIGHDPI`.
On Mac OS it means that, in source file `video/cocoa/SDL_cocoawindow.m`, from
function `Cocoa_CreateWindow`, SDL calls:

```objc
/* highdpi will be TRUE below */
BOOL highdpi = (window->flags & SDL_WINDOW_ALLOW_HIGHDPI) != 0;
[contentView setWantsBestResolutionOpenGLSurface:highdpi]
```

Documentation for `setWantsBestResolutionOpenGLSurface`:

https://developer.apple.com/documentation/appkit/nsview/1414938-wantsbestresolutionopenglsurface

with more details in "OpenGL Programming Guide for Mac", chapter
"Optimizing OpenGL for High Resolution":

https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/EnablingOpenGLforHighResolution/EnablingOpenGLforHighResolution.html#//apple_ref/doc/uid/TP40001987-CH1001-SW4

Citation from the official documentation:

You can opt in to high resolution by calling the method
`setWantsBestResolutionOpenGLSurface:` when you initialize the view, and
supplying YES as an argument:

```objc
[self  setWantsBestResolutionOpenGLSurface:YES];
```

If you don’t opt in, the system magnifies the rendered results.

The wantsBestResolutionOpenGLSurface property is relevant only for views to
which an NSOpenGLContext object is bound. Its value does not affect the behavior
of other views. For compatibility, wantsBestResolutionOpenGLSurface defaults to
NO, providing a 1-pixel-per-point framebuffer regardless of the backing scale
factor for the display the view occupies. Setting this property to YES for a
given view causes AppKit to allocate a higher-resolution framebuffer when
appropriate for the backing scale factor and target display.

To function correctly with wantsBestResolutionOpenGLSurface set to YES, a view
must perform correct conversions between view units (points) and pixel units as
needed. For example, the common practice of passing the width and height of
[self bounds] to glViewport() will yield incorrect results at high resolution,
because the parameters passed to the glViewport() function must be in pixels. As
a result, you’ll get only partial instead of complete coverage of the render
surface. Instead, use the backing store bounds:

```objc
[self convertRectToBacking:[self bounds]];
```

## Coordinates

The SDL function `SDL_GL_GetDrawableSize` will provide the size of the underlying drawable
in pixels. From the `SDL_video.h` header.

```c
/**
 *  \brief Get the size of a window's underlying drawable in pixels (for use
 *         with glViewport).
 *
 *  \param window   Window from which the drawable size should be queried
 *  \param w        Pointer to variable for storing the width in pixels, may be NULL
 *  \param h        Pointer to variable for storing the height in pixels, may be NULL
 *
 * This may differ from SDL_GetWindowSize() if we're rendering to a high-DPI
 * drawable, i.e. the window was created with SDL_WINDOW_ALLOW_HIGHDPI on a
 * platform with high-DPI support (Apple calls this "Retina"), and not disabled
 * by the SDL_HINT_VIDEO_HIGHDPI_DISABLED hint.
 *
 *  \sa SDL_GetWindowSize()
 *  \sa SDL_CreateWindow()
 */
extern DECLSPEC void SDLCALL SDL_GL_GetDrawableSize(SDL_Window * window, int *w,
                                                    int *h);
```

In turns it calls `Cocoa_GL_GetDrawableSize` from source file
`video/cocoa/SDL_cocoaopengl.m`. The function use the method
`[contentView convertRectToBacking:viewport]`:

```objc
    if (window->flags & SDL_WINDOW_ALLOW_HIGHDPI) {
        /* This gives us the correct viewport for a Retina-enabled view, only
         * supported on 10.7+. */
        if ([contentView respondsToSelector:@selector(convertRectToBacking:)]) {
            viewport = [contentView convertRectToBacking:viewport];
        }
    }
```

to give back the sizes in pixels.
