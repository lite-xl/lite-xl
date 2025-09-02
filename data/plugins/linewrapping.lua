-- mod-version:4 --priority:10
local core = require "core"
local common = require "core.common"
local DocView = require "core.docview"
local Doc = require "core.doc"
local style = require "core.style"
local config = require "core.config"
local command = require "core.command"
local keymap = require "core.keymap"
local translate = require "core.doc.translate"


config.plugins.linewrapping = common.merge({
	-- The type of wrapping to perform. Can be "letter" or "word".
  mode = "letter",
	-- If nil, uses the DocView's size, otherwise, uses this exact width. Can be a function.
  width_override = nil,
	-- Whether or not to draw a guide
  guide = true,
  -- Whether or not we should indent ourselves like the first line of a wrapped block.
  indent = true,
  -- Whether or not to enable wrapping by default when opening files.
  enable_by_default = false,
  -- Requires tokenization
  require_tokenization = false,
  -- The config specification used by gui generators
  config_spec = {
    name = "Line Wrapping",
    {
      label = "Mode",
      description = "The type of wrapping to perform.",
      path = "mode",
      type = "selection",
      default = "letter",
      values = {
        {"Letters", "letter"},
        {"Words", "word"}
      }
    },
    {
      label = "Guide",
      description = "Whether or not to draw a guide.",
      path = "guide",
      type = "toggle",
      default = true
    },
    {
      label = "Indent",
      description = "Whether or not to follow the indentation of wrapped line.",
      path = "indent",
      type = "toggle",
      default = true
    },
    {
      label = "Enable by Default",
      description = "Whether or not to enable wrapping by default when opening files.",
      path = "enable_by_default",
      type = "toggle",
      default = false
    },
    {
      label = "Require Tokenization",
      description = "Use tokenization when applying wrapping.",
      path = "require_tokenization",
      type = "toggle",
      default = false
    }
  }
}, config.plugins.linewrapping)

local function split_token(font, text, mode, width)
  local offset = 0
  local last_break = nil
  for i = 1, text:ulen() do
    offset = offset + font:get_width(text:usub(i, i))
    if offset >= width then return last_break or (i - 1) end
    if mode == "word" or text:usub(i, i) == " " then last_break = i end
  end
  return nil
end

local old_draw = DocView.draw
function DocView:draw()
  old_draw(self)
  if not self.wrapping then return end
  local new_width = self.size.x
  if self.wrapping and config.plugins.linewrapping.guide and config.plugins.linewrapping.width_override then
    local width = config.plugins.linewrapping.width_override
    if type(width) == "function" then width = width(self) end

    local x, y = docview:get_content_offset()
    local gw = docview:get_gutter_width()
    renderer.draw_rect(x + gw + width, y, 1, core.root_view.size.y, style.selection)
    new_width = width
  end
  if self.wrapping_width and self.wrapping_width ~= new_width then self:invalidate_cache() end
  self.wrapping_width = new_width
end

local old_get_h_scrollable_size = DocView.get_h_scrollable_size
function DocView:get_h_scrollable_size()
  if self.wrapping then return 0 end
  return old_get_h_scrollable_size(self)
end

local old_tokenize = DocView.tokenize
function DocView:tokenize(line, visible)
  if not self.wrapping then return old_tokenize(self, line, visible) end
  local tokens = {}
  local x, y = self:get_content_offset()
  local gw = self:get_gutter_width()
  local width = self.size.x - gw
  if config.plugins.linewrapping.width_override then
    width = config.plugins.linewrapping.width_override
    if type(width) == "function" then width = width(self) end
  end

  local docstart = x + gw + style.padding.x
  local offset = docstart
  local docend = docstart + width

  for _, type, l, s, e, style in self:each_token(old_tokenize(self, line, visible)) do
    local font = self:get_font() or style.font
    while true do
      local text = self:get_token_text(type, l, s, e)
      local w = font:get_width(text)
      table.insert(tokens, type)
      table.insert(tokens, l)
      if offset + w >= docend then
        local i = split_token(font, text, config.plugins.linewrapping.mode, docend - offset)
        assert(i)
        if type == "doc" then
          table.insert(tokens, s)
          table.insert(tokens, s + i - 1)
          s = i + s
        else
          table.insert(tokens, l:usub(1, i))
          table.insert(tokens, false)
          l = l:usub(i+1)
        end
        table.insert(tokens, style)

        table.insert(tokens, "virtual")
        table.insert(tokens, line)
        table.insert(tokens, "\n")
        table.insert(tokens, false)
        table.insert(tokens, style)

        offset = docstart
      else
        table.insert(tokens, s)
        table.insert(tokens, e)
        table.insert(tokens, style)
        break
      end
    end
  end
  return tokens
end

command.add(nil, {
  ["line-wrapping:enable"] = function()
    if core.active_view and core.active_view.doc then
      core.active_view.wrapping = true
      core.active_view:invalidate_cache()
    end
  end,
  ["line-wrapping:disable"] = function()
    if core.active_view and core.active_view.doc then
      core.active_view.wrapping = false
      core.active_view:invalidate_cache()
    end
  end,
  ["line-wrapping:toggle"] = function()
    if core.active_view and core.active_view.doc and core.active_view.wrapping then
      command.perform("line-wrapping:disable")
    else
      command.perform("line-wrapping:enable")
    end
  end
})

keymap.add {
  ["f10"] = "line-wrapping:toggle",
}
