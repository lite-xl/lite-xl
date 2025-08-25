---@meta

---
---Core functionality that allows rendering any arbitrary set of pixels.
---@class canvas
canvas = {}

---@alias canvas.scale_mode "linear" | "nearest"


---
---Creates a new canvas.
---
---@param w integer
---@param h integer
---@param color renderer.color Background color to initialize the Canvas with
---@return canvas
function canvas.new(w, h, color) end

---
---Returns the Canvas size.
---
---@return integer w, integer h
function canvas:get_size() end

---
---Overwrites the pixels of the Canvas with the specified ones.
---
---@param pixels string
---@param x integer
---@param y integer
---@param w integer
---@param h integer
function canvas:set_pixels(pixels, x, y, w, h) end

---
---Copies (a part of) the Canvas in a new Canvas.
---
---If no arguments are passed, the Canvas is duplicated as-is.
---
---`new_w` and `new_h` specify the new size of the copied region.
---
---@param x? integer
---@param y? integer
---@param w? integer
---@param h? integer
---@param new_w? integer
---@param new_h? integer
---@param scale_mode? canvas.scale_mode
---@return canvas copied_canvas A copy of the Canvas
function canvas:copy(x, y, w, h, new_w, new_h, scale_mode) end

---
---Returns a scaled copy of the Canvas.
---
---@param new_w integer
---@param new_h integer
---@param scale_mode canvas.scale_mode
---@return canvas scaled_canvas A scaled copy of the Canvas
function canvas:scaled(new_w, new_h, scale_mode) end

return canvas
