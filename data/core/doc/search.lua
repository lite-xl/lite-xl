local search = {}

local default_opt = {}


local function pattern_lower(str)
  if str:sub(1, 1) == "%" then
    return str
  end
  return str:lower()
end


local function init_args(doc, line, col, text, opt)
  opt = opt or default_opt
  line, col = doc:sanitize_position(line, col)

  if opt.no_case and not opt.regex then
    text = text:lower()
  end

  return doc, line, col, text, opt
end


local function plain_rfind(text, pattern, index)
  local len = #text
  text = text:reverse()
  pattern = pattern:reverse()
  if index >= 0 then
    index = len - index + 1
  else
    index = index * -1
  end
  local s, e = text:find(pattern, index, true)
  return e and len - e + 1, s and len - s + 1
end


local function rfind(text, pattern, index, plain)
  if plain then return plain_rfind(text, pattern, index) end
  local s, e = text:find(pattern)
  local last_s, last_e
  if index < 0 then index = #text - index + 1 end
  while e and e <= index do
    last_s, last_e = s, e
    s, e = text:find(pattern, s + 1)
  end
  return last_s, last_e
end


local function rcmatch(re, text, index)
  local s, e = re:cmatch(text)
  local last_s, last_e
  if index < 0 then index = #text - index + 1 end
  while e and e <= index + 1 do
    last_s, last_e = s, e
    s, e = re:cmatch(text, s + 1)
  end
  return last_s, last_e
end


function search.find(doc, line, col, text, opt)
  doc, line, col, text, opt = init_args(doc, line, col, text, opt)

  local re
  if opt.regex then
    re = regex.compile(text, opt.no_case and "i" or "")
  end
  local start, finish, step = line, #doc.lines, 1
  if opt.reverse then
    start, finish, step = line, 1, -1
  end
  for line = start, finish, step do
    local line_text = doc.lines[line]
    if opt.regex then
      local s, e
      if opt.reverse then
        s, e = rcmatch(re, line_text, col - 1)
      else
        s, e = re:cmatch(line_text, col)
      end
      if s then
        return line, s, line, e
      end
      col = opt.reverse and -1 or 1
    else
      if opt.no_case then
        line_text = line_text:lower()
      end
      local s, e
      if opt.reverse then
        s, e = rfind(line_text, text, col - 1, true)
      else
        s, e = line_text:find(text, col, true)
      end
      if s then
        return line, s, line, e + 1
      end
      col = opt.reverse and -1 or 1
    end
  end

  if opt.wrap then
    opt = { no_case = opt.no_case, regex = opt.regex, reverse = opt.reverse }
    if opt.reverse then
      return search.find(doc, #doc.lines, #doc.lines[#doc.lines], text, opt)
    else
      return search.find(doc, 1, 1, text, opt)
    end
  end
end


return search
