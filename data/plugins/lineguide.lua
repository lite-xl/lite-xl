-- mod-version:3
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local style = require "core.style"
local DocView = require "core.docview"
local CommandView = require "core.commandview"

config.plugins.lineguide = common.merge({
  enabled = false,
  width = 2,
  rulers = {
    -- 80,
    -- 100,
    -- 120,
    config.line_limit
  }
}, config.plugins.lineguide)

local function get_ruler(v)
  local result = nil
  if type(v) == 'number' then
    result = { columns = v }
  elseif type(v) == 'table' then
    result = v
  end
  return result
end

local draw_overlay = DocView.draw_overlay
function DocView:draw_overlay(...)
  draw_overlay(self, ...)

  if config.plugins.lineguide.enabled and not self:is(CommandView) then
    local line_x = self:get_line_screen_position(1)
    local character_width = self:get_font():get_width("n")
    local ruler_width = config.plugins.lineguide.width
    local ruler_color = style.guide or style.selection

    for k,v in ipairs(config.plugins.lineguide.rulers) do
      local ruler = get_ruler(v)

      if ruler then
        local x = line_x + (character_width * ruler.columns)
        local y = self.position.y
        local w = ruler_width
        local h = self.size.y

        renderer.draw_rect(x, y, w, h, ruler.color or ruler_color)
      end
    end
  end
end

command.add(nil, {
  ["lineguide:toggle"] = function()
    config.plugins.lineguide.enabled = not config.plugins.lineguide.enabled
  end
})
