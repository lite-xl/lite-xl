# Starter Contributions for LiteXL

Below are three approachable starter tasks, each with a clear file pointer and a small, well-defined scope.

## 1. Fix a Minor UI Bug in the Autocomplete Plugin
**File**: [`data/plugins/autocomplete.lua`](data/plugins/autocomplete.lua:1)
**Issue**: The autocomplete suggestion list does not constrain its maximum height correctly when the window is near the bottom of the screen, causing it to extend beyond the window bounds.
**Details**:
- In `get_suggestions_rect` (around line 391), the y position is calculated without checking if the suggestions list would exceed the window height.
- Add a check: if `y + max_height > window_height`, flip the list to appear above the cursor instead.
- This involves a few lines of logic and a test by opening a file near the bottom of the window and triggering autocomplete.
**Why it's a good start**: Small, self-contained, UI-focused, and the file is already well-documented.

## 2. Improve Documentation for a Core Command
**File**: [`data/core/commands/doc.lua`](data/core/commands/doc.lua:1)
**Issue**: Several commands lack descriptive docstrings, making them less discoverable via the command palette.
**Details**:
- Add a clear docstring to commands such as `doc:select-none`, `doc:toggle-line-comments`, and `doc:move-lines-up` (if missing).
- Example for `doc:select-none`: `"Deselect any text selection in the document."`
- Follow the existing pattern in the file where commands are defined with a description string.
- Verify by opening the command palette (`ctrl+shift+p`) and searching for the updated commands.
**Why it's a good start**: No code logic changes, improves user experience, and teaches the command system.

## 3. Add a Simple Plugin Example
**File**: Create a new plugin at [`data/plugins/hello.lua`](data/plugins/hello.lua:1)
**Task**: Write a minimal plugin that adds a command `hello:world` which shows a status bar message "Hello, LiteXL!".
**Details**:
- Use the existing plugin structure as a template (e.g., [`data/plugins/quote.lua`](data/plugins/quote.lua:1)).
- Register the command using `command.add` and display a message via `core.status_view:show_message`.
- Add a keybinding in `keymap.add` (e.g., `ctrl+shift+h`) to trigger the command.
- Test by loading the plugin and pressing the shortcut.
**Why it's a good start**: Introduces the plugin system, command registration, and keymaps without complex dependencies.