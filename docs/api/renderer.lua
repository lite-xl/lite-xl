---@meta

---
---Core functionality to render or draw elements into the screen.
---@class renderer
renderer = {}

---
---Array of bytes that represents a color used by the rendering functions.
---Note: indexes for rgba are numerical 1 = r, 2 = g, 3 = b, 4 = a but for
---documentation purposes the letters r, g, b, a were used.
---@class renderer.color
---@field public r number Red
---@field public g number Green
---@field public b number Blue
---@field public a number Alpha

---
---Advanced font variation options for OpenType/FreeType variation fonts.
---This is a table that has key-value pairs of parametric axis tag/names and the value.
---It can also contain a string at index 1, which the string will be used as a named variation.
---The values are converted to 16.16 packed fraction for Opentype and Truetype fonts.
---Only axis tags that are supported by the font will be applied.
---Only standard Opentype tags will be documented here; for supported tags their value ranges,
---please refer to the font documentation.
---@see https://fonts.google.com/knowledge/glossary/parametric_axis
---@see https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_Fonts/Variable_Fonts_Guide
---@see https://learn.microsoft.com/en-us/typography/opentype/spec/dvaraxisreg
---@class renderer.variationoptions
---@field public ital number Italicizes the font
---@field public opsz number Optical size
---@field public slnt number Slant, can be used if ital is unavailable
---@field public wdth number Width
---@field public wght number Weight
renderer.variationoptions = {}

---
---Represent options that affect a font's rendering.
---@class renderer.fontoptions
---@field public antialiasing "'none'" | "'grayscale'" | "'subpixel'"
---@field public hinting "'slight'" | "'none'" | '"full"'
---@field public bold boolean Emboldens the font. For advanced options, see renderer.variationoptions.
---@field public italic boolean Italicizes the font. For advanced options, see renderer.variationoptions.
---@field public underline boolean
---@field public smoothing boolean
---@field public strikethrough boolean
---@field public variation string | renderer.variationoptions
renderer.fontoptions = {}

---
---@class renderer.font
renderer.font = {}

---
---Create a new font object.
---
---@param path string
---@param size number
---@param options? renderer.fontoptions
---
---@return renderer.font
function renderer.font.load(path, size, options) end

---
---Combines an array of fonts into a single one for broader charset support,
---the order of the list determines the fonts precedence when retrieving
---a symbol from it.
---
---@param fonts renderer.font[]
---
---@return renderer.font
function renderer.font.group(fonts) end

---
---Clones a font object into a new one.
---
---@param size? number Optional new size for cloned font.
---@param options? renderer.fontoptions
---
---@return renderer.font
function renderer.font:copy(size, options) end

---
---Set the amount of characters that represent a tab.
---
---@param chars integer Also known as tab width.
function renderer.font:set_tab_size(chars) end

---
---Get the width in pixels of the given text when
---rendered with this font.
---
---@param text string
---
---@return number
function renderer.font:get_width(text) end

---
---Get the height in pixels that occupies a single character
---when rendered with this font.
---
---@return number
function renderer.font:get_height() end

---
---Get the current size of the font.
---
---@return number
function renderer.font:get_size() end

---
---Set a new size for the font.
---
---@param size number
function renderer.font:set_size(size) end

---
---Get the current path of the font as a string if a single font or as an
---array of strings if a group font.
---
---@return string | table<integer, string>
function renderer.font:get_path() end

---
---Toggles drawing debugging rectangles on the currently rendered sections
---of the window to help troubleshoot the renderer.
---
---@param enable boolean
function renderer.show_debug(enable) end

---
---Get the size of the screen area been rendered.
---
---@return number width
---@return number height
function renderer.get_size() end

---
---Tell the rendering system that we want to build a new frame to render.
function renderer.begin_frame() end

---
---Tell the rendering system that we finished building the frame.
function renderer.end_frame() end

---
---Set the region of the screen where draw operations will take effect.
---
---@param x number
---@param y number
---@param width number
---@param height number
function renderer.set_clip_rect(x, y, width, height) end

---
---Draw a rectangle.
---
---@param x number
---@param y number
---@param width number
---@param height number
---@param color renderer.color
function renderer.draw_rect(x, y, width, height, color) end

---
---Draw text and return the x coordinate where the text finished drawing.
---
---@param font renderer.font
---@param text string
---@param x number
---@param y number
---@param color renderer.color
---
---@return number x
function renderer.draw_text(font, text, x, y, color) end


return renderer
