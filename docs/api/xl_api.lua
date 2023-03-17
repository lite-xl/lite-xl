---@meta

---
---Functions to load C functions that uses the native API.
---@class xl_api
xl_api = {}

---
---Loads a C library and gets a symbol from it.
---If "*" is provided, the library will be loaded and no symbol will be returned.
---This is a low level function and should not be used directly.
---
---@param path string The absolute path to the library.
---@param symbol string | "*" A symbol in the library, or "*" to load the library only.
---@param extended boolean If true, the symbol will be loaded with native API support.
---@returns fun(...: any): any the symbol, loaded as a Lua C function.
---@returns string an error message.
---@returns "open" | "init" the type of error encountered.
function xl_api.loadlib(path, symbol, extended) end
