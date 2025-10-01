---@meta

---
---Functionality to create and manage windows
---@class renwindow
renwindow = {}

---
---Create a new window
---
--- 
---
---@param str string? if nil will be undefined
---@param x integer? if nil will be undefined
---@param y integer? if nil will be undefined
---@param width integer? if nil or less than 1 will be calculated from display
---@param height integer? if nil or less than 1 will be calculated from display
---
---@return renwindow
function renwindow.create(str, x, y, width, height) end

---
--- Get width and height of a window 
---
---@param window renwindow
---
---@return number width
---@return number height
function renwindow.get_size(window) end

---
--- Restore Window
---
---@return number
function renwindow._restore() end
