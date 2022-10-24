local core = require "core"

local ime = { }

function ime.reset()
  ime.editing = false
  ime.last_location = { x = 0, y = 0, w = 0, h = 0 }
end

---Convert from utf-8 offset and length (from SDL) to byte offsets
---@param text string @Textediting string
---@param start integer @0-based utf-8 offset of the starting position of the selection
---@param length integer @Size of the utf-8 length of the selection
function ime.ingest(text, start, length)
  if #text == 0 then
    -- finished textediting
    ime.reset()
    return "", 0, 0
  end

  ime.editing = true

  if start < 0 then
    -- we assume no selection and caret at the end
    return text, #text, 0
  end

  -- start is 0-based, so we use start + 1
  local start_byte = utf8.offset(text, start + 1)
  if not start_byte then
    -- bad start offset
    -- we assume it meant the last byte of the text
    start_byte = #text
  else
    start_byte = math.min(start_byte - 1, #text)
  end

  if length < 0 then
    -- caret only
    return text, start_byte, 0
  end

  local end_byte = utf8.offset(text, start + length + 1)
  if not end_byte or end_byte - 1 < start_byte then
    -- bad length, assume caret only
    return text, start_byte, 0
  end

  end_byte = math.min(end_byte - 1, #text)
  return text, start_byte, end_byte - start_byte
end

---Forward the given textediting SDL event data to Views.
---@param text string @Textediting string
---@param start integer @0-based utf-8 offset of the starting position of the selection
---@param length integer @Size of the utf-8 length of the selection
function ime.on_text_editing(text, start, length, ...)
  if ime.editing or #text > 0 then
    core.root_view:on_ime_text_editing(ime.ingest(text, start, length, ...))
  end
end

---Stop IME composition.
---Might not completely work on every platform.
function ime.stop()
  if ime.editing then
    -- SDL_ClearComposition for now doesn't work everywhere
    system.clear_ime()
    ime.on_text_editing("", 0, 0)
  end
end

---Set the bounding box of the text pertaining the IME.
---The IME will draw its interface based on this info.
---@param x number
---@param y number
---@param w number
---@param h number
function ime.set_location(x, y, w, h)
  if not ime.last_location or
     ime.last_location.x ~= x or
     ime.last_location.y ~= y or
     ime.last_location.w ~= w or
     ime.last_location.h ~= h
  then
    ime.last_location.x, ime.last_location.y, ime.last_location.w, ime.last_location.h = x, y, w, h
    system.set_text_input_rect(x, y, w, h)
  end
end

ime.reset()
return ime
