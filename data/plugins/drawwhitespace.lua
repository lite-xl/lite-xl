-- mod-version:3

local style = require "core.style"
local DocView = require "core.docview"
local common = require "core.common"
local config = require "core.config"

config.plugins.drawwhitespace = common.merge({
  enabled = true,
  show_leading = true,
  show_trailing = true,
  show_middle = true,

  show_middle_min = 1,

  color = style.syntax.whitespace or style.syntax.comment,
  leading_color = nil,
  middle_color = nil,
  trailing_color = nil,

  substitutions = {
    {
      char = " ",
      sub = "·",
      -- You can put any of the previous options here too.
      -- For example:
      -- show_middle_min = 2,
      -- show_leading = false,
    },
    {
      char = "\t",
      sub = "»",
    },
  },

  config_spec = {
    name = "Draw Whitespace",
    {
      label = "Enabled",
      description = "Disable or enable the drawing of white spaces.",
      path = "enabled",
      type = "toggle",
      default = true
    },
    {
      label = "Show Leading",
      description = "Draw whitespaces starting at the beginning of a line.",
      path = "show_leading",
      type = "toggle",
      default = true,
    },
    {
      label = "Show Middle",
      description = "Draw whitespaces on the middle of a line.",
      path = "show_middle",
      type = "toggle",
      default = true,
    },
    {
      label = "Show Trailing",
      description = "Draw whitespaces on the end of a line.",
      path = "show_trailing",
      type = "toggle",
      default = true,
    },
    {
      label = "Show Trailing as Error",
      description = "Uses an error square to spot them easily, requires 'Show Trailing' enabled.",
      path = "show_trailing_error",
      type = "toggle",
      default = false,
      on_apply = function(enabled)
        local found = nil
        local substitutions = config.plugins.drawwhitespace.substitutions
        for i, sub in ipairs(substitutions) do
          if sub.trailing_error then
            found = i
          end
        end
        if found == nil and enabled then
          table.insert(substitutions, {
            char = " ",
            sub = "█",
            show_leading = false,
            show_middle = false,
            show_trailing = true,
            trailing_color = style.error,
            trailing_error = true
          })
        elseif found ~= nil and not enabled then
          table.remove(substitutions, found)
        end
      end
    }
  }
}, config.plugins.drawwhitespace)

local function get_option(substitution, option)
  if substitution[option] == nil then
    return config.plugins.drawwhitespace[option]
  end
  return substitution[option]
end

local draw_line_text = DocView.draw_line_text
function DocView:draw_line_text(idx, x, y)
  if
    not config.plugins.drawwhitespace.enabled
    or
    getmetatable(self) ~= DocView
  then
    return draw_line_text(self, idx, x, y)
  end

  local font = (self:get_font() or style.syntax_fonts["whitespace"] or style.syntax_fonts["comment"])
  local ty = y + self:get_line_text_y_offset()
  local tx
  local text, offset, s, e = self.doc.lines[idx], 1
  local x1, _, x2, _ = self:get_content_bounds()
  local _offset = self:get_x_offset_col(idx, x1)

  for _, substitution in pairs(config.plugins.drawwhitespace.substitutions) do
    local char = substitution.char
    local sub = substitution.sub
    offset = _offset

    local show_leading = get_option(substitution, "show_leading")
    local show_middle = get_option(substitution, "show_middle")
    local show_trailing = get_option(substitution, "show_trailing")

    local show_middle_min = get_option(substitution, "show_middle_min")

    local base_color = get_option(substitution, "color")
    local leading_color = get_option(substitution, "leading_color") or base_color
    local middle_color = get_option(substitution, "middle_color") or base_color
    local trailing_color = get_option(substitution, "trailing_color") or base_color

    local pattern = char.."+"
    while true do
      s, e = text:find(pattern, offset)
      if not s then break end

      tx = self:get_col_x_offset(idx, s) + x

      local color = base_color
      local draw = false

      if e == #text - 1 then
        draw = show_trailing
        color = trailing_color
      elseif s == 1 then
        draw = show_leading
        color = leading_color
      else
        draw = show_middle and (e - s + 1 >= show_middle_min)
        color = middle_color
      end

      if draw then
        -- We need to draw tabs one at a time because they might have a
        -- different size than the substituting character.
        -- This also applies to any other char if we use non-monospace fonts
        -- but we ignore this case for now.
        if char == "\t" then
          for i = s,e do
            tx = self:get_col_x_offset(idx, i) + x
            tx = renderer.draw_text(font, sub, tx, ty, color)
          end
        else
          tx = renderer.draw_text(font, string.rep(sub, e - s + 1), tx, ty, color)
        end
      end

      if tx > x + x2 then break end
      offset = e + 1
    end
  end

  return draw_line_text(self, idx, x, y)
end
