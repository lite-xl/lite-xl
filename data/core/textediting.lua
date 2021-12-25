local core = require "core"

local textediting = { }

function textediting.reset()
  textediting.editing = false
  textediting.buffer = { "" }
  textediting.starts = { [0] = 1 }
  textediting.last_start = 0
end

-- SDL manages IME composition with chunks of 32 bytes.
-- 
-- For each chunk `start` is the total number of characters (not bytes)
-- of the preceding chunks, and `length` is the number of characters of the
-- current chunk.
-- 
-- Every time the composition changes, SDL sends all the chunks again,
-- in order, one at a time.
function textediting.ingest(text, start, length)
  if #text == 0 then
    -- finished textediting
    textediting.reset()
    return "", 0, 0
  end

  if start < textediting.last_start then
    -- restarted textediting
    textediting.reset()
  end

  textediting.editing = true

  if not textediting.starts[start] then
    -- new segment
    textediting.starts[start] = #textediting.buffer + 1
  end
  textediting.buffer[textediting.starts[start]] = text

  textediting.last_start = start
  return table.concat(textediting.buffer), 0, start + length
end

function textediting.on_text_editing(...)
  core.root_view:on_text_editing(textediting.ingest(...))
end

function textediting.stop()
  if textediting.editing then
    textediting.reset()
    -- https://github.com/libsdl-org/SDL/issues/4847
    -- TODO: when SDL supports it, call SDL_ResetTextInput to reset the IME
    -- with something like
    -- system.stop_ime()
    -- For now just remove the ingested content
    textediting.on_text_editing("", 0, 0)
  end
end

function textediting.set_ime_location(x, y, w, h)
  system.set_text_input_rect(x, y, w, h)
end

textediting.reset()
return textediting
