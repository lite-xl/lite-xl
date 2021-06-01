-- mod-version:1 -- lite-xl 1.16
local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local RootView = require "core.rootview"
local CommandView = require "core.commandview"

config.scale_mode = "code"
config.scale_use_mousewheel = true

local scale_level = 0
local scale_steps = 0.1
local font_cache = setmetatable({}, { __mode = "k" })

-- the following should be kept in sync with core.style's default font settings
font_cache[style.font]      = { DATADIR .. "/fonts/font.ttf",      14   * SCALE }
font_cache[style.big_font]  = { DATADIR .. "/fonts/font.ttf",      34   * SCALE }
font_cache[style.icon_font] = { DATADIR .. "/fonts/icons.ttf",     14   * SCALE }
font_cache[style.code_font] = { DATADIR .. "/fonts/monospace.ttf", 13.5 * SCALE }


local load_font = renderer.font.load
function renderer.font.load(...)
  local res = load_font(...)
  font_cache[res] = { ... }
  return res
end


local function scale_font(font, s)
  local fc = font_cache[font]
  return renderer.font.load(fc[1], fc[2] * s)
end


local current_scale = SCALE
local default = current_scale


local function get_scale() return current_scale end


local function set_scale(scale)
  scale = common.clamp(scale, 0.2, 6)

  -- save scroll positions
  local scrolls = {}
  for _, view in ipairs(core.root_view.root_node:get_children()) do
    local n = view:get_scrollable_size()
    if n ~= math.huge and not view:is(CommandView) then
      scrolls[view] = view.scroll.y / (n - view.size.y)
    end
  end

  local s = scale / current_scale
  current_scale = scale

  if config.scale_mode == "ui" then
    SCALE = current_scale

    style.padding.x      = style.padding.x      * s
    style.padding.y      = style.padding.y      * s
    style.divider_size   = style.divider_size   * s
    style.scrollbar_size = style.scrollbar_size * s
    style.caret_width    = style.caret_width    * s
    style.tab_width      = style.tab_width      * s

    style.big_font  = scale_font(style.big_font,  s)
    style.icon_font = scale_font(style.icon_font, s)
    style.font      = scale_font(style.font,      s)
  end

  style.code_font = scale_font(style.code_font, s)

  -- restore scroll positions
  for view, n in pairs(scrolls) do
    view.scroll.y = n * (view:get_scrollable_size() - view.size.y)
    view.scroll.to.y = view.scroll.y
  end

  core.redraw = true
end


local on_mouse_wheel = RootView.on_mouse_wheel

function RootView:on_mouse_wheel(d, ...)
  if keymap.modkeys["ctrl"] and config.scale_use_mousewheel then
    if d < 0 then command.perform "scale:decrease" end
    if d > 0 then command.perform "scale:increase" end
  else
    return on_mouse_wheel(self, d, ...)
  end
end

local function res_scale()
    scale_level = 0
    set_scale(default)
end

local function inc_scale()
    scale_level = scale_level + 1
    set_scale(default + scale_level * scale_steps)
end

local function dec_scale()
    scale_level = scale_level - 1
    set_scale(default + scale_level * scale_steps)
end


command.add(nil, {
  ["scale:reset"   ] = function() res_scale() end,
  ["scale:decrease"] = function() dec_scale() end,
  ["scale:increase"] = function() inc_scale() end,
})

keymap.add {
  ["ctrl+0"] = "scale:reset",
  ["ctrl+-"] = "scale:decrease",
  ["ctrl+="] = "scale:increase",
}

return { get_scale = get_scale, set_scale = set_scale }

