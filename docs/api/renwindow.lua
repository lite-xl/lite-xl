---@meta

---
---Functionality to create and manage windows
---@class renwindow
renwindow = {}

---
---Create a new window
---
---@param width integer? if nil or less than 1 will be calculated from display
---@param height integer? if nil or less than 1 will be calculated from display
---
---@return renwindow
function renwindow.create(width, height) end

---
---Change the window title.
---
---@param title string
function renwindow:set_title(title) end

---
--- Set the width and height of a window
---
---@return number width
---@return number height
function renwindow:set_size(w, h) end


---
--- Get width and height of a window 
---
---@return number width
---@return number height
function renwindow:get_size() end

---@alias renwindow.mode
---| "normal"
---| "minimized"
---| "maximized"
---| "fullscreen"

---
---Change the window mode.
---
---@param mode renwindow.mode
function renwindow:set_mode(mode) end

---
---Retrieve the window mode.
---
---@return renwindow.mode mode
function renwindow:get_mode() end

---
---Check if the window currently has focus.
---
---@return boolean
function renwindow:has_focus() end

---
---Raise the main window and give it input focus.
---Note: may not always be obeyed by the users window manager.
function renwindow:raise() end

---
---Toggle between bordered and borderless.
---
---@param bordered boolean
function renwindow:set_bordered(bordered) end
