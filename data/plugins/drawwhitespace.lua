-- mod-version:4 priority: 2000

local core = require "core"
local style = require "core.style"
local DocView = require "core.docview"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"

config.plugins.drawwhitespace = common.merge({
  enabled = false,
  show_leading = true,
  show_trailing = true,
  show_middle = true,
  show_selected_only = false,

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
      -- show_middle_min = 2
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
      default = false
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
      label = "Show Selected Only",
      description = "Only draw whitespaces if it is within a selection.",
      path = "show_selected_only",
      type = "toggle",
      default = false,
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


local draw_whitespace = {}
draw_whitespace = common.merge({}, config.plugins.drawwhitespace)
for i, sub in ipairs(draw_whitespace.substitutions) do
  draw_whitespace.substitutions[i] = common.merge(config.plugins.drawwhitespace, sub)
end

local old_draw_token = DocView.draw_token
function DocView:draw_token(tx, ty, text, style)
  if not style.dw then return old_draw_token(self, tx, ty, text, style) end
  local width = (style.font or self:get_font()):get_width(text) + tx
  if not style.dw.selection then 
    old_draw_token(self, tx, ty, style.dw.text, style) 
    return width
  end
  local start_selection, end_selection
  for idx, line1, col1, line2, col2 in self:get_selections() do
    if line1 <= style.dw.line and line2 >= style.dw.line then
      if line1 < style.dw.line and line2 > style.dw.line then
        start_selection, end_selection = style.dw.col1, style.dw.col2
        break
      elseif line1 < style.dw.line then
        start_selection = style.dw.col1
        end_selection = math.max(col2, end_selection or col1)
      elseif line2 > style.dw.line then
        start_selection = math.min(col1, start_selection or col2)
        end_selection = style.dw.col2
      else
        start_selection = math.min(col1, start_selection or col2)
        end_selection = math.max(col2, end_selection or col1)
      end
    end
  end
  if start_selection and start_selection <= style.dw.col2 and end_selection >= style.dw.col1 then
    old_draw_token(self, tx, ty, style.dw.text:usub(start_selection - style.dw.col1 + 1, end_selection - style.dw.col1 + 1), style)
    return width
  end
  return old_draw_token(self, tx, ty, text, style)
end

local old_tokenize = DocView.tokenize
function DocView:tokenize(line, ...)
  local tokens = old_tokenize(self, line, ...)
  if not self.draw_whitespace and not draw_whitespace.enabled then return tokens end
  
  local new_tokens = {}  
  for idx, type, line, col1, col2, style in self:each_token(tokens) do
    if type == "doc" then
      local text = self:get_token_text(type, line, col1, col2, style)
      local substituted_tokens = {}
      for _, sub in pairs(draw_whitespace.substitutions) do
        local offset = 1  
        while true do
          local pattern = sub.char
          -- Do tabs individually, because they have different widths from regular characters.
          if sub.char ~= "\t" then pattern = pattern.."+" end
          local s, e = text:ufind(pattern, offset)
          if not s then break end
          
          local color = sub.color
          local draw = false
          if e >= col2 - 1 and idx == #tokens then
            draw = sub.show_trailing
            color = sub.trailing_color or color
          elseif s == 1 and col1 == 1 then
            draw = sub.show_leading
            color = sub.leading_color or color
          else
            draw = sub.show_middle and (e - s + 1 >= sub.show_middle_min)
            color = sub.middle_color or color
          end
          if draw then
            table.insert(substituted_tokens, { 
              selection = sub.show_selected_only, 
              line = line,
              color = color,
              text = string.rep(sub.sub, e - s + 1),
              col1 = s + col1 - 1,
              col2 = e + col1 - 1 
            })
          end
          offset = e + 1
        end
      end
      table.sort(substituted_tokens, function(a,b) return a.col1 < b.col1 end)
      local offset = col1
      for i, token in ipairs(substituted_tokens) do
        if token.col1 > offset then
          common.push_token(new_tokens, type, line, offset, token.col1 - 1, style)
        end
        common.push_token(new_tokens, type, line, token.col1, token.col2, common.merge(style, { dw = token, color = token.color }))
        offset = token.col2 + 1
      end
      if offset <= col2 then
        common.push_token(type, line, offset, col2, style)
      end
    else
      common.push_token(type, line, col1, col2, style)
    end
  end
  return new_tokens
end

function draw_whitespace:toggle_global(setting)
  if setting == nil then setting = not self.enabled end
  self.enabled = setting
  for _, dv in ipairs(core.root_view.root_node:get_children()) do
    if dv:is(DocView) then
      dv:invalidate_cache()
    end
  end
end

function draw_whitespace:toggle_dv(dv, setting)
  if setting == nil then setting = not dv.draw_whitespace end
  dv.draw_whitespace = setting
  dv:invalidate_cache()
end

command.add(DocView, {
  ["draw-whitespace:toggle"]  = function(dv, setting) draw_whitespace:toggle_dv(dv, setting) end,
  ["draw-whitespace:disable"] = function(dv) draw_whitespace:toggle_dv(dv, false) end,
  ["draw-whitespace:enable"]  = function(dv) draw_whitespace:toggle_dv(dv, true) end,
  ["draw-whitespace:toggle-global"]  = function(dv, setting) draw_whitespace:toggle_global(setting) end,
  ["draw-whitespace:disable-global"] = function(dv) draw_whitespace:toggle_global(false) end,
  ["draw-whitespace:enable-global"]  = function(dv) draw_whitespace:toggle_global(true) end
})

return draw_whitespace
