local M = {}

local latex_replacements = {
  ['\\"a'] = "ä",
  ['\\"o'] = "ö",
  ['\\"u'] = "ü",
  ['\\"A'] = "Ä",
  ['\\"O'] = "Ö",
  ['\\"U'] = "Ü",
  ['\\\'a'] = "á",
  ['\\\'e'] = "é",
  ['\\\'i'] = "í",
  ['\\\'o'] = "ó",
  ['\\\'u'] = "ú",
  ['\\\`a'] = "à",
  ['\\\`e'] = "è",
  ['\\\^a'] = "â",
  ['\\~n'] = "ñ",
  ['\\ss'] = "ß",
  ['\\"{a}'] = "ä",
  ['\\"{o}'] = "ö",
  ['\\"{u}'] = "ü",
}

local latex_wrappers = {
  "\\textit", "\\emph", "\\textbf", "\\textsc",
}

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function strip_latex(value)
  if not value then
    return ''
  end
  for _, wrapper in ipairs(latex_wrappers) do
    value = value:gsub(wrapper .. "%b{}", function(match)
      return match:sub(#wrapper + 2, -2)
    end)
  end
  value = value:gsub("%b{}", function(match)
    local inner = match:sub(2, -2)
    if inner:find("[{}]") then
      return inner
    end
    return inner
  end)
  for pattern, replacement in pairs(latex_replacements) do
    value = value:gsub(pattern, replacement)
  end
  value = value:gsub("\\", "")
  value = value:gsub("%s+", " ")
  return trim(value)
end

local function read_braced_value(str, start)
  local depth = 0
  local i = start
  local len = #str
  while i <= len do
    local ch = str:sub(i, i)
    if ch == '{' then
      depth = depth + 1
    elseif ch == '}' then
      depth = depth - 1
      if depth == 0 then
        return str:sub(start + 1, i - 1), i + 1
      end
    elseif ch == '\\' then
      i = i + 1
    end
    i = i + 1
  end
  return str:sub(start + 1), len + 1
end

local function read_quoted_value(str, start)
  local i = start + 1
  local len = #str
  while i <= len do
    local ch = str:sub(i, i)
    if ch == '"' and str:sub(i - 1, i - 1) ~= '\\' then
      return str:sub(start + 1, i - 1), i + 1
    end
    i = i + 1
  end
  return str:sub(start + 1), len + 1
end

local function parse_fields(body)
  local fields = {}
  local i = 1
  local len = #body
  while i <= len do
    while i <= len and body:sub(i, i):match('%s') do
      i = i + 1
    end
    if i > len then
      break
    end
    local name_start, name_end, name = body:find('([%w_%-]+)%s*=%s*', i)
    if not name_start then
      break
    end
    i = name_end + 1
    local value
    local next_char = body:sub(i, i)
    if next_char == '{' then
      value, i = read_braced_value(body, i)
    elseif next_char == '"' then
      value, i = read_quoted_value(body, i)
    else
      local value_start = i
      while i <= len and not body:sub(i, i):match('[,%n]') do
        i = i + 1
      end
      value = body:sub(value_start, i - 1)
    end
    fields[name:lower()] = strip_latex(value)
    local comma = body:find(',', i)
    if comma == i then
      i = i + 1
    end
  end
  return fields
end

local function parse_entry(raw_entry)
  local content = raw_entry:sub(2, -2)
  local key, rest = content:match('^%s*([^,%s]+)%s*,(.*)$')
  if not key then
    return nil
  end
  local fields = parse_fields(rest)
  return {
    key = trim(key),
    fields = fields,
  }
end

function M.parse(content)
  local entries = {}
  for entrytype, body in content:gmatch('@(%w+)%s*(%b{})') do
    local parsed = parse_entry(body)
    if parsed then
      parsed.entrytype = entrytype:lower()
      entries[#entries + 1] = parsed
    end
  end
  return entries
end

function M.parse_file(path)
  local fd = assert(io.open(path, 'r'))
  local content = fd:read('*a')
  fd:close()
  return M.parse(content)
end

return M
