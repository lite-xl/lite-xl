---@meta

---The command line arguments given to lite.
---@type table<integer, string>
ARGS = {}

---The current platform tuple used for native modules loading,
---for example: "x86_64-linux", "x86_64-darwin", "x86_64-windows", etc...
---@type string
ARCH = "Architecture-OperatingSystem"

---The current operating system.
---@type string | "Windows" | "Mac OS X" | "Linux" | "iOS" | "Android"
PLATFORM = "Operating System"

---The current text or ui scale.
---@type number
SCALE = 1.0

---Full path of lite executable.
---@type string
EXEFILE = "/path/to/lite"

---Path to the users home directory.
---@type string
HOME = "/path/to/user/dir"
