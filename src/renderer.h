#ifndef RENDERER_H
#define RENDERER_H

#include <SDL3/SDL.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __GNUC__
#define UNUSED __attribute__((__unused__))
#else
#define UNUSED
#endif


#define FONT_FALLBACK_MAX 10
typedef struct RenFont RenFont;
typedef enum { FONT_HINTING_NONE, FONT_HINTING_SLIGHT, FONT_HINTING_FULL } ERenFontHinting;
typedef enum { FONT_ANTIALIASING_NONE, FONT_ANTIALIASING_GRAYSCALE, FONT_ANTIALIASING_SUBPIXEL } ERenFontAntialiasing;
typedef enum { FONT_STYLE_BOLD = 1, FONT_STYLE_ITALIC = 2, FONT_STYLE_UNDERLINE = 4, FONT_STYLE_SMOOTH = 8, FONT_STYLE_STRIKETHROUGH = 16 } ERenFontStyle;
typedef struct { uint8_t b, g, r, a; } RenColor;
typedef struct { int x, y, width, height; } RenRect;
typedef struct { double offset; } RenTab;
typedef struct { SDL_Surface *surface; int scale; } RenSurface;

struct RenWindow;
typedef struct RenWindow RenWindow;

RenFont* ren_font_load(const char *filename, float size, ERenFontAntialiasing antialiasing, ERenFontHinting hinting, unsigned char style);
RenFont* ren_font_copy(RenFont* font, float size, ERenFontAntialiasing antialiasing, ERenFontHinting hinting, int style);
const char* ren_font_get_path(RenFont *font);
void ren_font_free(RenFont *font);
int ren_font_group_get_tab_size(RenFont **font);
int ren_font_group_get_height(RenFont **font);
float ren_font_group_get_size(RenFont **font);
void ren_font_group_set_size(RenFont **font, float size, int surface_scale);
#ifdef LITE_USE_SDL_RENDERER
void update_font_scale(RenWindow *window_renderer, RenFont **fonts);
#endif
void ren_font_group_set_tab_size(RenFont **font, int n);
double ren_font_group_get_width(RenFont **font, const char *text, size_t len, RenTab tab, int *x_offset);
double ren_draw_text(RenSurface *rs, RenFont **font, const char *text, size_t len, float x, int y, RenColor color, RenTab tab);

void ren_draw_rect(RenSurface *rs, RenRect rect, RenColor color);

int video_init(void);
int ren_init(void);
void ren_free(void);
RenWindow* ren_create(SDL_Window *win);
void ren_destroy(RenWindow* window_renderer);
void ren_resize_window(RenWindow *window_renderer);
void ren_update_rects(RenWindow *window_renderer, RenRect *rects, int count);
void ren_set_clip_rect(RenWindow *window_renderer, RenRect rect);
void ren_get_size(RenWindow *window_renderer, int *x, int *y); /* Reports the size in points. */
size_t ren_get_window_list(RenWindow ***window_list_dest);
RenWindow* ren_find_window(SDL_Window *window);
RenWindow* ren_find_window_from_id(uint32_t id);
RenWindow* ren_get_target_window(void);
void ren_set_target_window(RenWindow *window);

#endif
