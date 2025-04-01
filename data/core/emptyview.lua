local core = require "core"
local style = require "core.style"
local keymap = require "core.keymap"
local View = require "core.view"

---@class core.emptyview : core.view
---@field super core.view
local EmptyView = View:extend()

function EmptyView:__tostring() return "EmptyView" end

function EmptyView:get_name()
  return "Get Started"
end

function EmptyView:get_filename()
  return ""
end

EmptyView.commands = {
  { fmt = "%s to run a command", cmd = "core:find-command" },
  { fmt = "%s to open a file from the project", cmd = "core:find-file" },
  { fmt = "%s to change project folder", cmd = "core:change-project-folder" },
  { fmt = "%s to open a project folder", cmd = "core:open-project-folder" },
}

function EmptyView:draw()
  self:draw_background(style.background)
  -- x,y center-point
  local x = self.position.x + self.size.x / 2
  local y = self.position.y + self.size.y / 2
  local divider_w = math.ceil(1 * SCALE)
  local cmds_x = x + math.ceil(divider_w /2) + style.padding.x
  local logo_right_side = x - math.ceil(divider_w/2) - style.padding.x

  local displayed_cmds = {}
  for _, command in ipairs(self.commands) do
    local keybinding = keymap.get_binding(command.cmd)
     if keybinding ~= nil then
      table.insert(displayed_cmds,{
        fmt = command.fmt,
        keybinding = keybinding
      })
     end
  end
  local cmd_h = style.font:get_height() + style.padding.y
  local cmds_y = y - ((cmd_h * #displayed_cmds)/2)
  for i, cmd in ipairs(displayed_cmds) do
    local cmd_text = string.format(cmd.fmt, cmd.keybinding)
    renderer.draw_text(style.font, cmd_text, cmds_x, cmds_y + cmd_h*(i-1), style.dim)
  end

  local title = "Lite XL"
  local version = VERSION
  local logo_h = style.big_font:get_height(title)
  local logo_y = y - logo_h + logo_h/4
  local logo_x = logo_right_side - style.big_font:get_width(title)
  local vers_x = logo_right_side - style.font:get_width(version)
  local vers_y = y + logo_h/8
  renderer.draw_text(style.big_font, title, logo_x, logo_y, style.dim)
  renderer.draw_text(style.font, version, vers_x, vers_y, style.dim)

  local divider_y =  math.min(cmds_y, logo_y) - style.padding.y
  local divider_h = (y - divider_y)*2
  renderer.draw_rect(x - divider_w/2, divider_y, divider_w, divider_h, style.dim)
end

return EmptyView
