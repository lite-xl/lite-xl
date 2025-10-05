---@meta

---
---Functionality to create and manage windows
---@class renwindow
renwindow = {}

---
---Create a new window
---
---@param title string the title given to the newly created window
---@param width integer? if nil or less than 1 will be calculated from display
---@param height integer? if nil or less than 1 will be calculated from display
---
---@return renwindow
function renwindow.create(title, width, height) end

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
