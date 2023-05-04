---@meta

---
---Functionality that allows to share data between lite-xl processes.
---@class shmem
shmem = {}

---
---Open a shared memory container.
---
---@param namespace string
---@param capacity integer
---
---@return shmem | nil
---@return string errmsg
function shmem.open(namespace, capacity) end

---
---Adds or edits an existing element on the shared memory container.
---
---@param name string
---@param value string
---
---@return boolean updated
function shmem:set(name, value) end

---
---Retrieve the data associated to the named element on the shared memory container.
---
---@param name string
---
---@return string? data
function shmem:get(name) end

---
---Removes the specified element from the shared memory container.
---
---@param name string
function shmem:remove(name) end

---
---Remove all elements from the shared memory container.
---
function shmem:clear() end

---
---The amount of elements residing on the shared memory container.
---
---@return integer
function shmem:size() end

---
---Maximum amount of elements the shared memory container can store.
---
---@return integer
function shmem:capacity(name, value) end


return shmem
