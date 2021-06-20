-- mod-version:1 -- lite-xl 1.16
local config = require "core.config"
local style = require "core.style"
local DocView = require "core.docview"

local draw_overlay = DocView.draw_overlay

function DocView:draw_overlay(...)
  local ns = ("n"):rep(config.line_limit)
  local ss = self:get_font():subpixel_scale()
  local offset = self:get_font():get_width_subpixel(ns) / ss
  local x = self:get_line_screen_position(1) + offset
  local y = self.position.y
  local w = math.ceil(SCALE * 1)
  local h = self.size.y

  local color = style.guide or style.selection
  renderer.draw_rect(x, y, w, h, color)

  draw_overlay(self, ...)
end
