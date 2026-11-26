---@meta

---
---Functionality to create and manage windows
---@class renwindow
renwindow = {}

---
---Window creation flags
---@class renwindow.flags
---@field transparent boolean? lets background colors with alpha show what is behind the window, if the platform supports it

---
---Create a new window
---
---@param title string the title given to the newly created window
---@param width integer? if nil or less than 1 will be calculated from display
---@param height integer? if nil or less than 1 will be calculated from display
---@param flags renwindow.flags? window creation flags
---
---@return renwindow
function renwindow.create(title, width, height, flags) end

---
---Get width and height of a window
---
---@param window renwindow
---
---@return number width
---@return number height
function renwindow.get_size(window) end

---
---Restore Window
---
---@return number
function renwindow._restore() end
