#include <SDL.h>
#include "renderer.h"

struct RenWindow {
  SDL_Window *window;
  RenRect clip; /* Clipping rect in pixel coordinates. */
#ifdef LITE_USE_SDL_RENDERER
  SDL_Renderer *renderer;
  SDL_Texture *texture;
  SDL_Surface *surface;
  int surface_scale;
#endif
};
typedef struct RenWindow RenWindow;

void renwin_init_surface(RenWindow *ren);
int  renwin_surface_scale(RenWindow *ren);
void renwin_clip_to_surface(RenWindow *ren);
void renwin_set_clip_rect(RenWindow *ren, RenRect rect);
void renwin_resize_surface(RenWindow *ren);
void renwin_show_window(RenWindow *ren);
void renwin_update_rects(RenWindow *ren, RenRect *rects, int count);
void renwin_free(RenWindow *ren);
SDL_Surface *renwin_get_surface(RenWindow *ren);

