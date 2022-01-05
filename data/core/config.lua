local core = require "core"
local common = require "core.common"
local config = {}

config.fps = 60
config.max_log_items = 80
config.message_timeout = 5
config.mouse_wheel_scroll = 50 * SCALE
config.scroll_past_end = true
config.file_size_limit = 10
config.ignore_files = "^%."
config.symbol_pattern = "[%a_][%w_]*"
config.non_word_chars = " \t\n/\\()\"':,.;<>~!@#$%^&*|+=[]{}`?-"
config.undo_merge_timeout = 0.3
config.max_undos = 10000
config.max_tabs = 8
config.always_show_tabs = true
config.highlight_current_line = true
config.line_height = 1.2
config.indent_size = 2
config.tab_type = "soft"
config.line_limit = 80
config.max_symbols = 4000
config.max_project_files = 2000
config.transitions = true
config.animation_rate = 1.0
config.blink_period = 0.8
config.disable_blink = false
config.draw_whitespace = false
config.borderless = false
config.tab_close_button = true
config.max_clicks = 3

config.plugins = {}
local function check_defaults(name, defaults, t)
  for k, _ in pairs(t) do
    local has_value = nil
    for e, _ in pairs(defaults) do
      has_value = has_value or k == "__name" or e == k
    end
    if not has_value then
      core.error("Unknown config value '%s' for plugin '%s'.", k, name)
    end
  end
end
local plugin_metatable
plugin_metatable = {
  __index = function(t,k) 
    return rawget(plugin_metatable, k) or rawget(t, k)
  end,
  __newindex = function(t, k ,v)
    if t.__default and rawget(t, k) == nil then
      check_defaults(rawget(t, "__name"), t, { [k] = v })
    end
    rawset(t, k, v)
  end,
  default = function(t, s) 
    check_defaults(rawget(t, "__name"), s, t)
    for k, v in pairs(s) do if rawget(t,k) == nil then t[k] = v end end
    t.__default = true
  end
}
-- Allow you to set plugin configs even if we haven't seen the plugin before.
setmetatable(config.plugins, { 
  __index = function(t, k) 
    if rawget(t, k) == nil then 
      local v = { __name = k } 
      setmetatable(v, plugin_metatable)
      rawset(t, k, v)
    end 
    return rawget(t, k) 
  end 
})

-- Disable these plugins by default.
config.plugins.trimwhitespace = false
config.plugins.lineguide = false
config.plugins.drawwhitespace = false

return config
