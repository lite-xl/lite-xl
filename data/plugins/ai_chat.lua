-- mod-version:4
--
-- AI Chat Sidebar Plugin for LiteXL
-- Provides a persistent sidebar for AI chat, similar to Cursor
--

local core = require "core"
local common = require "core.common"
local config = require "core.config"
local command = require "core.command"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"

-- Lazy load to avoid circular deps
local ai, agent_mod

local function get_ai()
  if not ai then ai = require "core.ai" end
  return ai
end

local function get_agent()
  if not agent_mod then agent_mod = require "core.agent" end
  return agent_mod
end


-- Configuration
config.plugins.ai_chat = common.merge({
  -- Sidebar width
  width = 350,
  -- Auto-approve safe tools (read-only operations)
  auto_approve_safe = false,
  -- Initially visible
  visible = false,
}, config.plugins.ai_chat)


---@class plugins.ai_chat.message
---@field role string "user" | "assistant" | "system"
---@field content string
---@field timestamp number


---@class plugins.ai_chat.AiChatView : core.view
local AiChatView = View:extend()

function AiChatView:new()
  AiChatView.super.new(self)
  
  self.messages = {}
  self.input_text = ""
  self.scrollable = true
  self.visible = config.plugins.ai_chat.visible
  self.target_size = config.plugins.ai_chat.width
  self.init_size = true
  
  -- Input cursor position
  self.input_cursor = 1
  
  -- Agent
  self.agent = nil
end


function AiChatView:init_agent()
  if self.agent then return end
  
  self.agent = get_agent().new({
    auto_approve = config.plugins.ai_chat.auto_approve_safe,
    on_message = function(role, content)
      self:add_message(role, content)
    end,
    on_tool_call = function(tool_name, args)
      self:add_message("system", "🔧 " .. tool_name)
    end,
    on_tool_result = function(tool_name, result)
      local preview = result:sub(1, 100)
      if #result > 100 then preview = preview .. "..." end
      self:add_message("system", "✓ " .. preview)
    end,
    on_approval_needed = function(tool_calls)
      local tools_list = {}
      for _, tc in ipairs(tool_calls) do
        table.insert(tools_list, tc["function"].name)
      end
      self:add_message("system", "⏸️ Approval needed: " .. table.concat(tools_list, ", "))
    end,
    on_complete = function()
      core.redraw = true
    end,
    on_error = function(err)
      self:add_message("system", "❌ " .. err)
    end,
  })
end


function AiChatView:__tostring()
  return "AI Chat"
end


function AiChatView:get_name()
  return "AI Chat"
end


---Add a message to the chat
---@param role string
---@param content string
function AiChatView:add_message(role, content)
  table.insert(self.messages, {
    role = role,
    content = content,
    timestamp = system.get_time(),
  })
  
  -- Scroll to bottom
  self.scroll.to.y = math.huge
  core.redraw = true
end


---Send the current input
function AiChatView:send()
  local text = self.input_text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return end
  
  self.input_text = ""
  self.input_cursor = 1
  
  -- Initialize agent if needed
  self:init_agent()
  
  -- Run agent
  if self.agent then
    self.agent:run(text)
  end
end


---Approve pending tool calls
function AiChatView:approve()
  if self.agent and self.agent.state.waiting_approval then
    self.agent:approve()
  end
end


---Reject pending tool calls
function AiChatView:reject()
  if self.agent and self.agent.state.waiting_approval then
    self.agent:reject()
  end
end


---Clear the chat
function AiChatView:clear()
  self.messages = {}
  if self.agent then
    self.agent:clear()
  end
  self.scroll.to.y = 0
  core.redraw = true
end


---Toggle sidebar visibility
function AiChatView:toggle()
  self.visible = not self.visible
  core.redraw = true
end


---Show sidebar
function AiChatView:show()
  self.visible = true
  core.redraw = true
end


---Hide sidebar
function AiChatView:hide()
  self.visible = false
  core.redraw = true
end


function AiChatView:set_target_size(axis, value)
  if axis == "x" then
    self.target_size = value
    return true
  end
end


function AiChatView:update()
  -- Animate size
  local dest = self.visible and self.target_size or 0
  if self.init_size then
    self.size.x = dest
    self.init_size = nil
  else
    self:move_towards(self.size, "x", dest, nil, "ai_chat")
  end
  
  AiChatView.super.update(self)
end


function AiChatView:get_scrollable_size()
  if self.size.x <= 0 then return 0 end
  
  local font = style.font
  local lh = font:get_height() * 1.4
  local h = style.padding.y * 2 + lh * 4  -- Header space
  
  for _, msg in ipairs(self.messages) do
    local lines = self:wrap_text(msg.content, font, self.size.x - style.padding.x * 4)
    h = h + #lines * lh + style.padding.y * 2
  end
  
  -- Add input area height + some padding
  h = h + 200
  
  return h
end


---Wrap text to fit width
---@param text string
---@param font any
---@param max_width number
---@return string[]
function AiChatView:wrap_text(text, font, max_width)
  local lines = {}
  if max_width <= 0 then max_width = 200 end
  
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    if line == "" then
      table.insert(lines, "")
    elseif font:get_width(line) <= max_width then
      table.insert(lines, line)
    else
      -- Word wrap
      local current = ""
      for word in line:gmatch("%S+") do
        local test = current == "" and word or (current .. " " .. word)
        if font:get_width(test) <= max_width then
          current = test
        else
          if current ~= "" then
            table.insert(lines, current)
          end
          -- Handle very long words
          if font:get_width(word) > max_width then
            table.insert(lines, word)
            current = ""
          else
            current = word
          end
        end
      end
      if current ~= "" then
        table.insert(lines, current)
      end
    end
  end
  
  if #lines == 0 then
    table.insert(lines, "")
  end
  
  return lines
end


function AiChatView:supports_text_input()
  return self.visible
end


function AiChatView:on_text_input(text)
  if not self.visible then return end
  
  -- Insert text at cursor
  self.input_text = self.input_text:sub(1, self.input_cursor - 1) .. text .. self.input_text:sub(self.input_cursor)
  self.input_cursor = self.input_cursor + #text
  core.redraw = true
end


function AiChatView:on_mouse_pressed(button, x, y, clicks)
  if not self.visible or self.size.x <= 0 then return false end
  
  local caught = AiChatView.super.on_mouse_pressed(self, button, x, y, clicks)
  if caught then return true end
  
  -- Check if click is on send button
  local input_area_height = 100
  local input_y = self.position.y + self.size.y - input_area_height
  local send_btn_x = self.position.x + self.size.x - style.padding.x - 45
  local send_btn_y = input_y + 35
  
  if x >= send_btn_x and x <= send_btn_x + 40 and y >= send_btn_y and y <= send_btn_y + 30 then
    self:send()
    return true
  end
  
  -- Check approve/reject buttons when waiting
  if self.agent and self.agent.state.waiting_approval then
    local btn_y = input_y + 5
    local approve_x = self.position.x + style.padding.x
    local reject_x = approve_x + 80
    
    if y >= btn_y and y <= btn_y + 25 then
      if x >= approve_x and x <= approve_x + 70 then
        self:approve()
        return true
      elseif x >= reject_x and x <= reject_x + 70 then
        self:reject()
        return true
      end
    end
  end
  
  return true
end


function AiChatView:on_key_pressed(key)
  if not self.visible then return false end
  
  if key == "return" then
    self:send()
    return true
  elseif key == "shift+return" then
    self:on_text_input("\n")
    return true
  elseif key == "ctrl+return" then
    self:approve()
    return true
  elseif key == "escape" then
    if self.agent and self.agent.state.waiting_approval then
      self:reject()
    else
      self:hide()
    end
    return true
  elseif key == "backspace" then
    if self.input_cursor > 1 then
      self.input_text = self.input_text:sub(1, self.input_cursor - 2) .. self.input_text:sub(self.input_cursor)
      self.input_cursor = self.input_cursor - 1
      core.redraw = true
    end
    return true
  elseif key == "delete" then
    if self.input_cursor <= #self.input_text then
      self.input_text = self.input_text:sub(1, self.input_cursor - 1) .. self.input_text:sub(self.input_cursor + 1)
      core.redraw = true
    end
    return true
  elseif key == "left" then
    if self.input_cursor > 1 then
      self.input_cursor = self.input_cursor - 1
      core.redraw = true
    end
    return true
  elseif key == "right" then
    if self.input_cursor <= #self.input_text then
      self.input_cursor = self.input_cursor + 1
      core.redraw = true
    end
    return true
  elseif key == "home" then
    self.input_cursor = 1
    core.redraw = true
    return true
  elseif key == "end" then
    self.input_cursor = #self.input_text + 1
    core.redraw = true
    return true
  elseif key == "ctrl+l" then
    self:clear()
    return true
  end
  
  return false
end


function AiChatView:draw()
  -- Only draw if visible and has width
  if not self.visible or self.size.x <= 0 then return end
  
  self:draw_background(style.background)
  
  local font = style.font
  local lh = font:get_height() * 1.4
  local x = self.position.x + style.padding.x
  local y = self.position.y + style.padding.y - self.scroll.y
  local w = self.size.x - style.padding.x * 2
  local msg_width = w - style.padding.x
  
  -- Draw sidebar border on left edge
  renderer.draw_rect(self.position.x, self.position.y, 1, self.size.y, style.divider or style.dim)
  
  -- Draw header
  local title_font = style.big_font or font
  renderer.draw_text(title_font, "AI Assistant", x, y, style.accent)
  y = y + title_font:get_height() + style.padding.y / 2
  
  -- Status indicator
  local status = "Ready"
  local status_color = style.dim
  if self.agent then
    local state = self.agent:get_state_string()
    if state == "running" then 
      status = "Working..."
      status_color = style.good or style.accent
    elseif state == "waiting_approval" then 
      status = "Waiting approval"
      status_color = style.warn or style.accent
    elseif state == "error" then 
      status = "Error"
      status_color = style.error
    end
  end
  renderer.draw_text(font, status, x, y, status_color)
  y = y + lh
  
  -- Separator
  renderer.draw_rect(x, y, w, 1, style.divider or style.dim)
  y = y + style.padding.y
  
  -- Empty state
  if #self.messages == 0 then
    local empty_y = y + 40
    local greeting = "What can I do for you?"
    local greeting_w = font:get_width(greeting)
    renderer.draw_text(font, greeting, x + (w - greeting_w) / 2, empty_y, style.accent)
    
    local hint = "Type a message below"
    local hint_w = font:get_width(hint)
    renderer.draw_text(font, hint, x + (w - hint_w) / 2, empty_y + lh * 1.5, style.dim)
  end
  
  -- Draw messages
  for _, msg in ipairs(self.messages) do
    local is_user = msg.role == "user"
    local is_system = msg.role == "system"
    
    -- Message styling
    local bg_color, text_color, label
    if is_user then
      bg_color = style.selection
      text_color = style.text
      label = "You"
    elseif is_system then
      bg_color = style.line_number2 or style.background2
      text_color = style.dim
      label = nil
    else
      bg_color = style.background2
      text_color = style.text
      label = "AI"
    end
    
    local msg_lines = self:wrap_text(msg.content, font, msg_width)
    local msg_height = #msg_lines * lh + style.padding.y
    if label then msg_height = msg_height + lh / 2 end
    
    -- Draw message background
    renderer.draw_rect(x, y, w, msg_height, bg_color)
    
    local ty = y + style.padding.y / 2
    
    -- Draw label
    if label then
      local label_color = is_user and style.accent or (style.good or style.accent)
      renderer.draw_text(font, label .. ":", x + style.padding.x / 2, ty, label_color)
      ty = ty + lh / 2 + 2
    end
    
    -- Draw message content
    for _, line in ipairs(msg_lines) do
      renderer.draw_text(font, line, x + style.padding.x / 2, ty, text_color)
      ty = ty + lh
    end
    
    y = y + msg_height + style.padding.y / 2
  end
  
  -- Fixed input area at bottom
  local input_area_height = 100
  local input_y = self.position.y + self.size.y - input_area_height
  
  -- Input area background
  renderer.draw_rect(self.position.x, input_y, self.size.x, input_area_height, style.background2)
  renderer.draw_rect(self.position.x, input_y, self.size.x, 1, style.accent)
  
  local content_y = input_y + 8
  
  -- Approval buttons if needed
  if self.agent and self.agent.state.waiting_approval then
    local btn_x = self.position.x + style.padding.x
    
    -- Approve button
    renderer.draw_rect(btn_x, content_y, 70, 25, style.good or { 80, 160, 80, 255 })
    renderer.draw_text(font, "Approve", btn_x + 8, content_y + 5, style.background)
    
    -- Reject button
    renderer.draw_rect(btn_x + 80, content_y, 60, 25, style.error or { 180, 80, 80, 255 })
    renderer.draw_text(font, "Reject", btn_x + 88, content_y + 5, style.background)
    
    content_y = content_y + 30
  end
  
  -- Input label
  renderer.draw_text(font, "Message:", self.position.x + style.padding.x, content_y, style.dim)
  content_y = content_y + lh
  
  -- Input text area background
  local text_x = self.position.x + style.padding.x
  local text_w = self.size.x - style.padding.x * 2 - 50
  local text_h = 30
  
  renderer.draw_rect(text_x, content_y, text_w, text_h, style.background)
  
  -- Input text or placeholder
  local display_text = self.input_text
  local display_color = style.text
  if display_text == "" then
    display_text = "Type here..."
    display_color = style.dim
  end
  
  -- Truncate if too long
  local max_display_width = text_w - 10
  while font:get_width(display_text) > max_display_width and #display_text > 0 do
    display_text = display_text:sub(2)
  end
  
  renderer.draw_text(font, display_text, text_x + 5, content_y + 7, display_color)
  
  -- Cursor (blinking)
  if (system.get_time() * 2) % 1 < 0.5 then
    local cursor_offset = font:get_width(self.input_text:sub(1, self.input_cursor - 1))
    if cursor_offset > max_display_width then cursor_offset = max_display_width end
    renderer.draw_rect(text_x + 5 + cursor_offset, content_y + 5, 2, font:get_height(), style.caret)
  end
  
  -- Send button
  local send_x = self.position.x + self.size.x - style.padding.x - 45
  renderer.draw_rect(send_x, content_y, 40, text_h, style.accent)
  renderer.draw_text(font, ">", send_x + 15, content_y + 7, style.background)
  
  -- Hint text at very bottom
  local hint = "Enter: send | Esc: close"
  local hint_y = self.position.y + self.size.y - font:get_height() - 5
  renderer.draw_text(font, hint, self.position.x + style.padding.x, hint_y, style.dim)
  
  self:draw_scrollbar()
end


-- =============================================================================
-- Plugin setup - similar to treeview
-- =============================================================================

local view = AiChatView()

-- Initialize the view by splitting the active node (similar to treeview)
local function init_sidebar()
  local node = core.root_view:get_active_node()
  
  -- Split to the right
  view.node = node:split("right", view, { x = true }, true)
  
  -- Set initial size based on visibility
  if not view.visible then
    view.size.x = 0
  else
    view.size.x = view.target_size
  end
end

-- Call init immediately (like treeview does)
init_sidebar()


-- Commands
command.add(nil, {
  ["ai:toggle-chat"] = function()
    view:toggle()
    if view.visible then
      core.set_active_view(view)
    end
  end,
  
  ["ai:open-chat"] = function()
    view:show()
    core.set_active_view(view)
  end,
  
  ["ai:close-chat"] = function()
    view:hide()
  end,
  
  ["ai:send"] = function()
    view:send()
  end,
  
  ["ai:clear-chat"] = function()
    view:clear()
  end,
  
  ["ai:approve"] = function()
    view:approve()
  end,
  
  ["ai:reject"] = function()
    view:reject()
  end,
})


-- Keybindings
keymap.add({
  ["ctrl+shift+a"] = "ai:toggle-chat",
})


-- Add button to toolbar after treeview loads
local function add_toolbar_button()
  local ok, treeview = pcall(require, "plugins.treeview")
  if ok and treeview and treeview.toolbar then
    table.insert(treeview.toolbar.toolbar_commands, {
      symbol = "*",  -- asterisk as AI symbol (available in icon font)
      command = "ai:toggle-chat"
    })
  end
end

-- Defer toolbar button addition
core.add_thread(function()
  coroutine.yield(0.1)
  add_toolbar_button()
end)


return view
