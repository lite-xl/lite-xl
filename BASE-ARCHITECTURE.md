
# LiteXL Base Architecture

## High-Level Overview
LiteXL is a lightweight, extensible text editor built with a native C core and a Lua runtime for UI and plugins. It uses SDL3 for windowing/input and FreeType for font rendering. The architecture is layered:
- **C Core**: SDL3, FreeType, software renderer with command buffering (rencache), window abstraction (RenWindow), and Lua C API bindings.
- **Lua Core**: UI framework (View hierarchy), document model, tokenizer/syntax engine, command system, keymap, and plugin loading.
- **Plugins**: Lua modules and optional native C extensions using a dedicated plugin API.

## Startup Sequence
1. **C Entry (`src/main.c`)**: SDL init, create Lua state, set globals (`ARGS`, `PLATFORM`, `ARCH`, `RESTARTED`, `EXEFILE`), call `api_load_libs` to register C APIs, then `dofile` `data/core/start.lua`.
2. **Lua Bootstrap (`data/core/start.lua`)**: Set up `SCALE`, `PATHSEP`, `DATADIR`, `USERDIR`; configure `package.path`/`package.cpath`; override `require` for relative imports and native plugin loading.
3. **Core Initialization (`data/core/init.lua`)**: `require 'core'` loads core modules, creates `root_view`, `command_view`, `status_view`, `nag_view`, `title_view`; loads plugins; restores/creates window via `renwin` APIs.
4. **Run Loop**: `core.run()` drives the event loop; rendering uses `rencache` for dirty-region optimization.

## Component Directory Map
- `src/`: C core (renderer, window, rencache, API bindings, main)
- `data/core/`: Lua core modules (init, view, doc, command, keymap, etc.)
- `data/plugins/`: Built-in Lua plugins (autocomplete, language support, etc.)
- `resources/include/`: Headers for native plugin API (`lite_xl_plugin_api.h`)
- `docs/api/`: Lua API documentation

## Key Subsystems
- **Renderer (`src/renderer.c`)**: FreeType-based font rasterization, glyph atlas, subpixel/grayscale antialiasing, font groups with fallback, text drawing with underline/strikethrough.
- **RenWindow (`src/renwindow.c`)**: Window abstraction; supports direct window surface or SDL_Renderer-backed texture; handles HiDPI scaling and surface resizing.
- **Rencache (`src/rencache.c`)**: Software command buffer and cell-based dirty-region optimization; hashes per-cell command lists; merges changed cells into minimal dirty rects.
- **Lua API (`src/api/*.c`)**: C-to-Lua bindings for renderer, system, process, regex, UTF8, directory monitoring.
- **View System (`data/core/view.lua`)**: Base class for UI widgets; handles position/size, scrolling, scrollbars, mouse/keyboard input, scale changes.
- **Document Model (`data/core/doc/init.lua`)**: Text buffer with lines, selections, undo/redo, syntax detection, cursor/position helpers.
- **Tokenizer/Syntax (`data/core/tokenizer.lua`, `data/core/syntax.lua`)**: Incremental tokenizer with sub-syntax stack; syntax definitions with patterns and symbol tables.
- **Command System (`data/core/command.lua`)**: Registry of named commands; predicates for enabling/disabling; `command.perform` executes.
- **Keymap (`data/core/keymap.lua`)**: Maps shortcuts to command sequences; handles modkeys, mouse wheel, clicks; platform-specific modkey tables.
- **Plugin API (`resources/include/lite_xl_plugin_api.h`)**: Header-only wrapper for Lua C API; defines `luaopen_lite_xl_*` entrypoints; symbol wrapping to avoid Lua library conflicts.
- **Plugin Example (`data/plugins/autocomplete.lua`)**: Symbol extraction via background thread, fuzzy matching, UI suggestion list, per-plugin config schema.

## Per-File Summaries

### src/main.c
- **Entrypoint**: Initializes SDL, renderer (`ren_init`), custom events, Lua state. Sets global variables (`ARGS`, `PLATFORM`, `ARCH`, `RESTARTED`, `EXEFILE`). Calls `api_load_libs` to register C APIs, then `dofile` `data/core/start.lua`. Requires core module and calls `core.init()` and `core.run()`. Handles restart loop via `has_restarted` flag and `goto init_lua`.
- **Key Functions**: `main()`, `init_lua()` (loads core and runs), `api_load_libs()` (registers C APIs).

### src/renderer.c
- **Font Rendering**: FreeType integration; glyph atlas with multiple surfaces; subpixel/grayscale antialiasing; font groups with fallback. Supports bold/italic/underline/strikethrough styles and hinting options.
- **Text Drawing**: `ren_draw_text` iterates UTF-8 codepoints, retrieves glyphs via `font_group_get_glyph`, blends subpixel/grayscale glyphs onto destination surface.
- **Rect Drawing**: `ren_draw_rect` fills rectangles with solid or blended colors.
- **Font Management**: `ren_font_load`, `ren_font_copy`, `ren_font_group_set_size`, `ren_font_group_get_width/height`.
- **Helpers**: UTF-8 decoding, whitespace detection, tab width calculation.

### src/renwindow.c
- **Window Abstraction**: `RenWindow` wraps SDL_Window and either a direct surface or an SDL_Renderer texture. Handles HiDPI scaling (`query_surface_scale`).
- **Surface Management**: `renwin_init_surface` creates/resizes the backing surface; `renwin_resize_surface` recreates on size/scale change.
- **Drawing/Updating**: `renwin_update_rects` copies dirty rects to the window (via SDL_UpdateWindowSurfaceRects or SDL_Renderer texture update).
- **Clipping**: `renwin_set_clip_rect` sets the drawing clip.

### src/rencache.c
- **Command Buffer**: Stores drawing commands (`SET_CLIP`, `DRAW_TEXT`, `DRAW_RECT`) in a growable buffer per window.
- **Cell Hashing**: Divides the screen into a grid (`CELLS_X`/`CELLS_Y`), hashes command lists per cell, and tracks changes from the previous frame.
- **Dirty Region Merging**: `push_rect` merges overlapping cells into minimal dirty rectangles.
- **Frame Rendering**: `rencache_end_frame` redraws only dirty regions, then swaps cell buffers and resets the command buffer.

### src/api/renderer.c
- **Lua Bindings for Renderer**: Provides `renderer` module with functions `begin_frame`, `end_frame`, `draw_rect`, `draw_text`, `set_clip_rect`, `get_size`.
- **Font API**: `renderer.font` metatable with `load`, `copy`, `group`, `get_width/height/size`, `set_size/tab_size`, `get_path`.
- **Font Options**: Parses antialiasing, hinting, and style flags from Lua tables.
- **Target Window**: Uses a global target window (`ren_get_target_window`) set by `begin_frame`/`end_frame`.

### data/core/view.lua
- **Base View Class**: Defines position, size, scroll, cursor, scrollbars, and scale handling.
- **Input Handling**: `on_mouse_pressed/released/moved`, `on_mouse_wheel`, `on_text_input`, `on_ime_text_editing`.
- **Scrolling**: Animated scrolling via `move_towards`; scrollbar widgets (`v_scrollbar`, `h_scrollbar`) with dragging.
- **Lifecycle**: `try_close`, `get_name`, `supports_text_input`, `on_scale_change`.
- **Drawing**: `draw_background`, `draw_scrollbar`, `draw` (no-op by default).

### resources/include/lite_xl_plugin_api.h
- **Plugin API Header**: Wraps Lua C API to avoid symbol conflicts. Defines `LITE_XL_PLUGIN_ENTRYPOINT` and `luaopen_lite_xl_*` entrypoints.
- **Symbol Wrapping**: In the plugin, `SYMBOL_DECLARE` creates static function pointers and fallback stubs; `lite_xl_plugin_init` resolves symbols from the host.
- **Configuration**: Includes Lua configuration (`luaconf.h`) for number types and paths.
- **Usage**: Compile native plugins without linking to Lua; call `lite_xl_plugin_init(XL)` in the entrypoint.

### data/plugins/autocomplete.lua
- **Symbol Extraction**: Background thread scans open documents for symbols using `config.symbol_pattern`, caches per document, respects `max_symbols`.
- **Suggestions**: Fuzzy matches symbols against the partial input; supports scopes (global, local, related, none). Merges syntax-defined symbols and document symbols.
- **UI**: Draws a suggestion list below the cursor with icons and descriptions; handles selection, insertion, and closing.
- **Configuration**: Extensive config schema (`config_spec`) for min length, max height, icons, scope, etc.
- **API**: `autocomplete.add` registers symbol tables; `autocomplete.complete` triggers manually.

### data/core/doc/highlighter.lua
- **Incremental Syntax Highlighting**: Runs in a background thread (`core.add_thread`). Retokenizes lines from `first_invalid_line` to `max_wanted_line` in chunks.
- **State Management**: Stores per-line token lists and state (`init_state`). Invalidates lines on edits (`insert_notify`, `remove_notify`, `invalidate`).
- **Tokenization**: Delegates to `tokenizer.tokenize` for each line; handles time-slicing and resume state.
- **Plugin Hook**: `update_notify` called after lines are retokenized.

### data/core/keymap.lua
- **Shortcut Mapping**: Maps normalized shortcut strings to commands (strings or functions). Supports multiple commands per shortcut.
- **Modkeys**: Tracks pressed modifier keys; platform-specific modkey tables (`modkeys-generic`, `modkeys-macos`).
- **Event Handling**: `on_key_pressed` resolves shortcuts and executes commands; `on_mouse_wheel` and `on_mouse_pressed` translate wheel/click events to shortcuts.
- **Binding Management**: `add`, `add_direct`, `unbind`, `get_binding(s)`. Normalizes shortcuts and maintains reverse map.

### data/core/init.lua
- **Core Initialization**: Loads core modules (`require 'core.*'`), constructs root view and UI views (command, status, nag, title). Loads plugins from `USERDIR/plugins` and `DATADIR/plugins`. Restores or creates the window.
- **Session Management**: `load_session`/`save_session` restore open files and project.
- **Entry Points**: `core.init` called from C after Lua state is ready; `core.run` starts the main loop.
- **Plugin Loading**: Iterates plugin directories, `require` each plugin; handles errors via `core.try`.

### data/core/start.lua
- **Bootstrap**: Sets global `SCALE`, `PATHSEP`, `DATADIR`, `USERDIR`. Configures `package.path` and `package.cpath` for user and system directories. Overrides `require` to support relative imports and native plugin loading (`package.native_plugins`).
- **Environment**: Expects `LITE_XL_RUNTIME` env var to override core module name.

### data/core/tokenizer.lua
- **Incremental Tokenizer**: `tokenize(syntax, text, state, resume)` tokenizes a line, returning tokens, new state, and optional resume flag for incomplete tokens.
- **Subsyntax Stack**: Encodes subsyntax state as a string of bytes; pushes/pops subsyntaxes via patterns.
- **Time-Slicing**: If tokenization exceeds a timeout, returns with `resume=true` to continue later.
- **Iteration**: `each_token` iterates over token ranges.

### data/core/syntax.lua
- **Syntax Registry**: `syntax.add` registers syntax definitions with patterns, symbols, and files. `syntax.get` retrieves syntax by filename.
- **Pattern Validation**: Checks pattern types (string, table, list) and compiles regex patterns.
- **Symbol Patterns**: `syntax.symbols` maps symbol names to types for autocomplete.

### data/core/command.lua
- **Command Registry**: `command.add` registers named commands (functions or strings). `command.perform` executes a command by name, optionally passing arguments.
- **Predicates**: Commands can have predicates (string, table, function) to enable/disable them.
- **Defaults**: `command.add_defaults` loads commands from `data/core/commands/*`.

### data/core/doc/init.lua
- **Document Model**: Stores lines, selections, undo/redo stacks, clean/dirty flags, and syntax.
- **Selections**: `get_selection`, `set_selection`, `add_selection`, `set_cursor`; supports multiple selections.
- **Editing**: `insert`, `delete`, `replace`; manages undo/redo groups.
- **File I/O**: `load`, `save`; optionally reloads on external changes.
- **Position Helpers**: `position_offset`, `get_text`, `get_char_at`.

### data/core/docview.lua
- **Document View**: Renders a `Doc` with line numbers, gutter, selections, and cursor. Handles scrolling, IME, and mouse input.
- **Layout**: `get_line_height`, `get_gutter_width`, `get_line_text_position`.
- **Input**: `on_mouse_pressed` (set cursor/selection), `on_text_input` (insert text), `on_key_pressed` (commands).
- **Scrolling**: `scroll_to_line`, `scroll_to_make_visible`; animated scrolling.

### data/core/rootview.lua
- **Root View**: Manages a tree of `Node` objects, each containing a view or split (horizontal/vertical). Handles tab dragging, dropping, and context menus.
- **Node Operations**: `split_node`, `close_node`, `move_tab`, `add_node`.
- **Mouse**: `on_mouse_pressed/released/moved` handle tab dragging, node resizing, and context menu invocation.

### data/core/common.lua
- **Utilities**: UTF-8 helpers, `clamp`, `lerp`, `round`, `fuzzy_match`, path helpers, `serialize`, `mkdirp`, `rm`, `draw_text` wrapper.
- **Color**: `lerp_color`, color blending.
- **Platform**: `platform` variable for OS detection.

### data/core/config.lua
- **Configuration**: Global `config` table; `config.import` merges tables; `config.apply` validates against a schema.
- **Schema**: Used by plugins to define config specifications (`config_spec`).

### data/core/style.lua
- **Theming**: Loads color schemes from `data/colors/`. Provides `style` table with colors, fonts, and sizes.
- **Font Loading**: `style.code_font` loads the primary code font.

### data/core/statusview.lua
- **Status Bar**: Shows current file, cursor position, line count, and notifications. Handles command palette and messages.

### data/core/commandview.lua
- **Command Palette**: UI for searching and executing commands. Fuzzy matches command names and descriptions.

### data/core/contextmenu.lua
- **Context Menu**: Shows a context menu on right-click. Managed by `ContextMenuView`.

### data/core/scrollbar.lua
- **Scrollbar Widget**: Vertical/horizontal scrollbar with dragging and hover. Used by `View`.

### data/core/node.lua
- **Node Container**: Used by `RootView` to represent splits and tabs.

### data/core/object.lua
- **Base Class**: Simple class system with `Object:extend()`.

### data/core/project.lua
- **Project Management**: `ProjectScan` thread watches directories for file changes. `project_files` command lists files.

### data/core/process.lua
- **Process Execution**: Wraps `system.spawn` to run processes and capture output.

### data/core/regex.lua
- **Regex Wrapper**: Exposes Lua regex functions.

### data/core/ime.lua
- **IME Support**: Handles Input Method Editor events.

### data/core/logview.lua
- **Log View**: Displays log messages.

### data/core/nagview.lua
- **Nag View**: Shows persistent notifications.

### data/core/titleview.lua
- **Title Bar**: Custom title bar (if enabled).

### data/core/emptyview.lua
- **Empty View**: Placeholder for empty areas.

### data/core/storage.lua
- **Storage**: Persists data to `USERDIR`.

### data/core/strict.lua
- **Strict Mode**: Enforces global variable declarations.

### data/core/utf8string.lua
- **UTF-8 String**: UTF-8 string utilities.

### data/core/dirwatch.lua
- **Directory Watcher**: Watches directories for changes.

### data/core/modkeys-*.lua
- **Modkey Tables**: Platform-specific modifier key mappings.

### data/core/commands/*.lua
- **Command Definitions**: Core commands (e.g., `core:quit`, `doc:save`, `root:split`). Loaded by `command.add_defaults`.

### data/core/doc/*.lua
- **Document Extensions**: `highlighter` (syntax highlighting), `search` (text search), `translate` (character translation).

### data/plugins/*.lua
- **Built-in Plugins**: Autocomplete, language support, whitespace drawing, line wrapping, macros, project search, tree view, etc.

### src/api/*.c
- **Lua API Bindings**: `renderer`, `renwindow`, `system`, `process`, `regex`, `utf8`, `dirmonitor`.

### src/api/dirmonitor/*.c
- **Directory Monitoring**: Platform-specific backends (inotify, FSEvents, kqueue, Windows).

### src/*.c
- **C Core**: `main.c` (entry), `renderer.c` (font/text rendering), `renwindow.c` (window abstraction), `rencache.c` (render cache), `custom_events.c` (custom SDL events), `arena_allocator.c` (memory allocator).

### src/*.h
- **Headers**: Public headers for renderer, window, rencache, API.

### subprojects/
- **Subprojects**: FreeType2 wrap.

### scripts/
- **Build Scripts**: Meson build scripts, packaging scripts, fontello config.

### resources/
- **Resources**: Icons, desktop files, macOS resources, Windows resources.

### docs/
- **Documentation**: API docs, README, changelog, contributing guide.

### licenses/
- **Licenses**: License information.

### .github/
- **GitHub**: GitHub Actions workflows.

### .editorconfig, .gitattributes, .gitignore
- **Config**: Editor config, git attributes, git ignore.

### meson.build, meson_options.txt
- **Build**: Meson build configuration and options.

### manifest.json
- **Manifest**: Package manifest.

### changelog.md, CONTRIBUTING.md, LICENSE, README.md
- **Docs**: Changelog, contributing guide, license