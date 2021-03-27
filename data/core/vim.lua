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
local verbs_imm = {'a', 'h', 'i', 'j', 'k', 'l', 'p', 'u', 'x', 'y', 'left', 'right', 'up', 'down'}
local vim_objects = {'d', 'e', 'w', '^', '0', '$'}

local vim_object_map = {
  ['e'] = 'next-word-end',
  ['w'] = 'next-word-begin',
  ['$'] = 'end-of-line',
  ['^'] = 'start-of-line',
  ['0'] = 'start-of-line',
}

local function vim_execute(verb, mult, object)
  if verb == '.' then
    if object == '$' then
      command.perform_many(mult - 1, 'doc:move-to-next-line')
      command.perform('doc:move-to-end-of-line')
    else
      if object == 'e' then
        command.perform('doc:move-to-next-char')
      end
      command.perform_many(mult, 'doc:move-to-' .. vim_object_map[object])
      if object == 'e' then
        command.perform('doc:move-to-previous-char')
      end
    end
  elseif verb == 'd' then
    if object == '$' then
      command.perform_many(mult - 1, 'doc:select-to-next-line')
      command.perform('doc:select-to-end-of-line')
    elseif object == 'd' then
      command.perform('doc:move-to-start-of-line')
      command.perform_many(mult, 'doc:select-to-next-line')
    else
      command.perform_many(mult, 'doc:select-to-' .. vim_object_map[object])
    end
    command.perform('doc:copy')
    command.perform('doc:cut')
  elseif verb == 'c' then
    command.perform_many(mult, 'doc:select-to-' .. vim_object_map[object])
    command.perform('doc:copy')
    command.perform('doc:cut')
    command.perform('core:set-insert-mode')
  elseif verb == 'h' or verb == 'left' then
    command.perform_many(mult, 'doc:move-to-previous-char')
  elseif verb == 'j' or verb == 'down' then
    command.perform_many(mult, 'doc:move-to-next-line')
  elseif verb == 'k' or verb == 'up' then
    command.perform_many(mult, 'doc:move-to-previous-line')
  elseif verb == 'l' or verb == 'right' then
    command.perform_many(mult, 'doc:move-to-next-char')
  elseif verb == 'x' then
    command.perform_many(mult, 'doc:delete')
  elseif verb == 'a' then
    command.perform('core:set-insert-mode')
    command.perform('doc:move-to-next-char')
  elseif verb == 'i' then
    command.perform('core:set-insert-mode')
  elseif verb == 'p' then
    command.perform('doc:paste')
  elseif verb == 'u' then
    command.perform('doc:undo')
  else
    return false
  end
  return true
end

function vim.on_key_pressed(mode, stroke, k)
  if mode == 'command' then
    if command_buffer.verb == '.' and table_find(verbs_imm, stroke) then
      vim_execute(stroke, command_buffer:mult())
      command_buffer:reset()
      return true
    elseif command_buffer.verb == '.' and table_find(verbs_obj, stroke) then
      command_buffer.verb = stroke
      return true
    elseif string.byte(k) >= string.byte('0') and string.byte(k) <= string.byte('9') then
      command_buffer:add_mult_char(k)
      return true
    elseif table_find(vim_objects, stroke) then
      vim_execute(command_buffer.verb, command_buffer:mult(), stroke)
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
