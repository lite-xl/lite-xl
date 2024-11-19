local core = require "core"
local style = require "core.style"
local keymap = require "core.keymap"
local View = require "core.view"

---@class core.emptyview : core.view
---@field super core.view
local EmptyView = View:extend()

function EmptyView:get_name()
  return "Get Started"
end

function EmptyView:get_filename()
  return ""
end

-- commands are now easily extensible
EmptyView.commands = {
  { fmt = "%s to run a command", cmd = "core:find-command" },
  { fmt = "%s to open a file from the project", cmd = "core:find-file" },
  { fmt = "%s to change project folder", cmd = "core:change-project-folder" },
  { fmt = "%s to open a project folder", cmd = "core:open-project-folder" },
}

function EmptyView:draw()
  self:draw_background(style.background)
  local center_x = self.position.x + self.size.x / 2
  local center_y = self.position.y + self.size.y / 2

  local divider_w = math.ceil(1 * SCALE)
  local left_edge_of_commands = center_x + (divider_w /2) + style.padding.x
  local right_edge_of_logo = center_x - (divider_w/2) - style.padding.x

  -- determine how many commands will be displayed to get the height
  local displayed_commands = {}
  for _, command in ipairs(self.commands) do
    local keybinding = keymap.get_binding(command.cmd)
     if keybinding ~= nil then
      table.insert(displayed_commands,{
        fmt = command.fmt,
        keybinding = keybinding
      })
     end
  end

  -- Draw commands
  local height_of_each_command = style.font:get_height() + style.padding.y
  local top_of_commands = center_y - ((height_of_each_command * #displayed_commands)/2)

  -- draw the commands to the right, left-justified
  for i, line in ipairs(displayed_commands) do
    local text = string.format(line.fmt, line.keybinding)
    renderer.draw_text(style.font, text, left_edge_of_commands, top_of_commands + (i-1)*height_of_each_command, style.dim)
  end



  local title = "Lite XL"
  local version = VERSION
  local logo_h = style.big_font:get_height(title)
  local logo_w = style.big_font:get_width(title)

  local logo_y = center_y - (logo_h + style.font:get_height(version))/2
  local version_y = logo_y + logo_h

  local logo_x = right_edge_of_logo - style.big_font:get_width(title)
  local version_x = right_edge_of_logo - style.font:get_width(version)

  renderer.draw_text(style.big_font, title, logo_x, logo_y, style.dim)
  renderer.draw_text(style.font, version, version_x, version_y, style.dim)




  -- set the divider to the larger of the logo height or the commands heigth
  local divider_y =  math.min(top_of_commands, logo_y-style.padding.y)
  local divider_h = (center_y - divider_y)*2
  renderer.draw_rect(center_x - divider_w/2,divider_y, divider_w, divider_h, style.dim)

end


return EmptyView
