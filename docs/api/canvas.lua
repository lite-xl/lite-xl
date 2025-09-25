---@meta

---
---Core functionality that allows rendering any arbitrary set of pixels.
---@class canvas
canvas = {}

---@alias canvas.scale_mode "linear" | "nearest"

---
---Creates a new canvas.
---
---@param width integer
---@param height integer
---@param color renderer.color Background color to initialize the Canvas with
---@return canvas
function canvas.new(width, height, color) end

---
---Returns the Canvas size.
---
---@return integer w, integer h
function canvas:get_size() end

---
---Returns the pixels of the specified portion of the Canvas.
---
---If the coordinates are not specified, the whole Canvas is considered.
---The pixel format is RGBA32.
---
---@param x? integer
---@param y? integer
---@param width? integer
---@param height? integer
---@return string pixels
function canvas:get_pixels(pixels, x, y, width, height) end

---
---Overwrites the pixels of the Canvas with the specified ones.
---
---The pixel format *must be* RGBA32.
---
---@param pixels string
---@param x integer
---@param y integer
---@param width integer
---@param height integer
function canvas:set_pixels(pixels, x, y, width, height) end

---
---Copies (a part of) the Canvas in a new Canvas.
---
---If no arguments are passed, the Canvas is duplicated as-is.
---
---`new_width` and `new_height` specify the new size of the copied region.
---
---@param x? integer
---@param y? integer
---@param width? integer
---@param height? integer
---@param new_width? integer
---@param new_height? integer
---@param scale_mode? canvas.scale_mode
---@return canvas copied_canvas A copy of the Canvas
function canvas:copy(x, y, width, height, new_width, new_height, scale_mode) end

---
---Returns a scaled copy of the Canvas.
---
---@param new_width integer
---@param new_height integer
---@param scale_mode canvas.scale_mode
---@return canvas scaled_canvas A scaled copy of the Canvas
function canvas:scaled(new_width, new_height, scale_mode) end

---
---Set the region of the Canvas where draw operations will take effect.
---
---@param x integer
---@param y integer
---@param width integer
---@param height integer
function renderer.set_clip_rect(x, y, width, height) end

---
---Draw a rectangle.
---
---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@param color renderer.color
---@param replace boolean Overwrite the content with the specified color. Useful when dealing with alpha.
function renderer.draw_rect(x, y, width, height, color, replace) end

---
---Draw text and return the x coordinate where the text finished drawing.
---
---@param font renderer.font
---@param text string
---@param x number
---@param y integer
---@param color renderer.color
---@param tab_data? renderer.tab_data
---
---@return number x
function renderer.draw_text(font, text, x, y, color, tab_data) end

---
---Draw a Canvas.
---
---@param canvas canvas
---@param x integer
---@param y integer
---@param blend boolean Whether to blend the Canvas, or replace the pixels
function renderer.draw_canvas(canvas, x, y, blend) end

return canvas
