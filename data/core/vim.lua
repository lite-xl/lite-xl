local core = require "core"
local command = require "core.command"

local vim = {}

local command_buffer = {verb = '.', mult_accu = ''}

function command_buffer:reset()
  self.verb = '.'
  self.mult_accu = ''
end

function command_buffer:mult()
  return self.mult_accu == '' and 1 or tostring(self.mult_accu)
end

function command_buffer:add_mult_char(k)
  self.mult_accu = self.mult_accu .. k
end

local function table_find(t, e)
  for i = 1, #t do
    if t[i] == e then return i end
  end
end

local verbs_obj = {'c', 'd'}
local verbs_imm = {'a', 'h', 'i', 'j', 'k', 'l', 'o', 'p', 'u', 'v', 'x', 'y', 'O',
  'left', 'right', 'up', 'down', 'escape'}

local vim_objects = {'b', 'd', 'e', 'w', '^', '0', '$'}

local vim_object_map = {
  ['b'] = 'start-of-word',
  ['e'] = 'next-word-end',
  ['w'] = 'next-word-begin',
  ['$'] = 'end-of-line',
  ['^'] = 'start-of-line',
  ['0'] = 'start-of-line',
}

local function doc_command(action, command)
  return 'doc:' .. action .. '-' .. command
end

local function vim_execute(mode, verb, mult, object)
  local action = (mode == 'command' and 'move-to' or 'select-to')
  if verb == '.' then
    if object == '$' then
      command.perform_many(mult - 1, doc_command(action, 'next-line'))
      command.perform(doc_command(action, 'end-of-line'))
    else
      if object == 'e' then
        command.perform(doc_command(action, 'next-char'))
      end
      command.perform_many(mult, doc_command(action, vim_object_map[object]))
      if object == 'e' then
        command.perform(doc.command(action, 'previous-char'))
      end
    end
  elseif verb == 'd' then
    if mode == 'command' then
      if object == '$' then
        command.perform_many(mult - 1, 'doc:select-to-next-line')
        command.perform('doc:select-to-end-of-line')
      elseif object == 'd' then
        command.perform('doc:move-to-start-of-line')
        command.perform_many(mult, 'doc:select-to-next-line')
      else
        command.perform_many(mult, 'doc:select-to-' .. vim_object_map[object])
      end
    end
    command.perform('doc:copy')
    command.perform('doc:cut')
    command.perform('core:set-command-mode')
  elseif verb == 'c' then
    command.perform_many(mult, 'doc:select-to-' .. vim_object_map[object])
    command.perform('doc:copy')
    command.perform('doc:cut')
    command.perform('core:set-insert-mode')
  elseif verb == 'h' or verb == 'left' then
    command.perform_many(mult, doc_command(action, 'previous-char'))
  elseif verb == 'j' or verb == 'down' then
    command.perform_many(mult, doc_command(action, 'next-line'))
  elseif verb == 'k' or verb == 'up' then
    command.perform_many(mult, doc_command(action, 'previous-line'))
  elseif verb == 'l' or verb == 'right' then
    command.perform_many(mult, doc_command(action, 'next-char'))
  elseif verb == 'x' then
    command.perform_many(mult, 'doc:delete')
  elseif verb == 'a' then
    command.perform('core:set-insert-mode')
    command.perform('doc:move-to-next-char')
  elseif verb == 'i' then
    command.perform('core:set-insert-mode')
  elseif verb == 'o' then
    command.perform('doc:move-to-end-of-line')
    command.perform('doc:newline')
    command.perform('core:set-insert-mode')
  elseif verb == 'O' then
    command.perform('doc:move-to-start-of-line')
    command.perform('doc:newline')
    command.perform('doc:move-to-previous-line')
    command.perform('core:set-insert-mode')
  elseif verb == 'p' then
    command.perform('doc:paste')
  elseif verb == 'u' then
    command.perform('doc:undo')
  elseif verb == 'v' then
    command.perform('core:set-visual-mode')
  elseif verb == 'y' then
    command.perform('doc:copy')
    command.perform('doc:move-to-start-of-selection')
    command.perform('core:set-command-mode')
  elseif verb == 'escape' then
    command.perform('doc:move-to-end-of-selection')
    command.perform('core:set-command-mode')
  else
    return false
  end
  return true
end

function vim.on_text_input(mode, text, stroke)
  text = text or stroke
  if mode == 'command' or mode == 'visual' then
    if command_buffer.verb == '.' and table_find(verbs_imm, text) then
      vim_execute(mode, text, command_buffer:mult())
      command_buffer:reset()
      return true
    elseif command_buffer.verb == '.' and table_find(verbs_obj, text) then
      if mode == 'command' then
        command_buffer.verb = text
      else
        vim_execute(mode, text, command_buffer:mult())
        command_buffer:reset()
      end
      return true
    elseif string.byte(text) >= string.byte('0') and string.byte(text) <= string.byte('9') then
      command_buffer:add_mult_char(text)
      return true
    elseif table_find(vim_objects, text) then
      vim_execute(mode, command_buffer.verb, command_buffer:mult(), text)
      command_buffer:reset()
      return true
    elseif stroke == 'escape' then
      command_buffer:reset()
      return true
    end
  elseif mode == 'insert' then
    if stroke == 'escape' or stroke == 'ctrl+c' then
      core.set_editing_mode(core.active_view, 'command')
      return true
    end
    if stroke == 'backspace' then
      command.perform('doc:backspace')
    end
  end
  return false
end

return vim
