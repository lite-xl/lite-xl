---@meta

---
---Functionality that allows the manipulation of pixels.
---@class canvas
canvas = {}

---
---Table that specifies the pixel format. Must be compatible with SDL.
---
---@class canvas.pixel_format
---@field public r_mask integer #Red channel mask
---@field public g_mask integer #Green channel mask
---@field public b_mask integer #Blue channel mask
---@field public a_mask integer #Alpha channel mask
---@field public bpp integer #Number of bits per pixel

---32 bits split in 8 bits per channel, in XRGB order.
---@type canvas.pixel_format
canvas.PIXELFORMAT_RGB888 = {}

---32 bits split in 8 bits per channel, in RGBA order.
---@type canvas.pixel_format
canvas.PIXELFORMAT_RGBA8888 = {}

---24 bits split in 8 bits per channel, in RGB order
---@type canvas.pixel_format
canvas.PIXELFORMAT_RGB24 = {}

---
---Returns the canvas sizes.
---
---@return integer width
---@return integer height
function canvas:get_size() end

---
---Sets the pixels of the canvas.
---
---@param pixel_data string #String of pixel data
---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@param pixel_format canvas.pixel_format? #Defaults to `canvas.PIXELFORMAT_RGBA8888`
function canvas:set_pixels(pixel_data, x, y, width, height, pixel_format) end

return canvas
