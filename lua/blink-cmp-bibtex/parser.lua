--- BibTeX parser module
--- Parses BibTeX files and normalizes LaTeX commands to UTF-8
--- @module blink-cmp-bibtex.parser

local M = {}

--- LaTeX text formatting commands that should be stripped
--- @type string[]
local latex_wrappers = {
  "\\textit",
  "\\emph",
  "\\textbf",
  "\\textsc",
}

local accent_map = {
  ['"'] = {
    a = 'ä', A = 'Ä', e = 'ë', E = 'Ë', i = 'ï', I = 'Ï', o = 'ö', O = 'Ö', u = 'ü', U = 'Ü', y = 'ÿ', Y = 'Ÿ',
  },
  ["'"] = {
    a = 'á', A = 'Á', e = 'é', E = 'É', i = 'í', I = 'Í', o = 'ó', O = 'Ó', u = 'ú', U = 'Ú', y = 'ý', Y = 'Ý',
    c = 'ć', C = 'Ć', n = 'ń', N = 'Ń', s = 'ś', S = 'Ś', z = 'ź', Z = 'Ź',
  },
  ['`'] = {
    a = 'à', A = 'À', e = 'è', E = 'È', i = 'ì', I = 'Ì', o = 'ò', O = 'Ò', u = 'ù', U = 'Ù',
  },
  ['^'] = {
    a = 'â', A = 'Â', e = 'ê', E = 'Ê', i = 'î', I = 'Î', o = 'ô', O = 'Ô', u = 'û', U = 'Û', c = 'ĉ', C = 'Ĉ',
  },
  ['~'] = {
    a = 'ã', A = 'Ã', n = 'ñ', N = 'Ñ', o = 'õ', O = 'Õ',
  },
  ['='] = {
    a = 'ā', A = 'Ā', e = 'ē', E = 'Ē', i = 'ī', I = 'Ī', o = 'ō', O = 'Ō', u = 'ū', U = 'Ū',
  },
  ['.'] = {
    c = 'ċ', C = 'Ċ', e = 'ė', E = 'Ė', z = 'ż', Z = 'Ż',
  },
  ['u'] = {
    a = 'ă', A = 'Ă', e = 'ĕ', E = 'Ĕ', g = 'ğ', G = 'Ğ', i = 'ĭ', I = 'Ĭ', o = 'ŏ', O = 'Ŏ', u = 'ŭ', U = 'Ŭ',
  },
  ['v'] = {
    c = 'č', C = 'Č', s = 'š', S = 'Š', z = 'ž', Z = 'Ž', r = 'ř', R = 'Ř', n = 'ň', N = 'Ň', e = 'ě', E = 'Ě',
  },
  ['H'] = {
    o = 'ő', O = 'Ő', u = 'ű', U = 'Ű',
  },
  ['c'] = {
    c = 'ç', C = 'Ç', s = 'ş', S = 'Ş', t = 'ţ', T = 'Ţ',
  },
  ['k'] = {
    a = 'ą', A = 'Ą', e = 'ę', E = 'Ę',
  },
  ['r'] = {
    a = 'å', A = 'Å', u = 'ů', U = 'Ů',
  },
}

local simple_commands = {
  aa = 'å',
  AA = 'Å',
  ae = 'æ',
  AE = 'Æ',
  oe = 'œ',
  OE = 'Œ',
  ss = 'ß',
  o = 'ø',
  O = 'Ø',
  l = 'ł',
  L = 'Ł',
  dh = 'ð',
  DH = 'Ð',
  th = 'þ',
  TH = 'Þ',
  i = 'i',
  j = 'j',
}

local accent_letter_aliases = {
  ['\\i'] = 'i',
  ['\\j'] = 'j',
}

--- Trim whitespace from both ends of a string
--- @param value string The string to trim
--- @return string The trimmed string
local function trim(value)
  return value:match('^%s*(.-)%s*$') or ''
end

--- Replace a LaTeX accent with its UTF-8 equivalent
--- @param accent string The accent character
--- @param letter string The base letter
--- @return string|nil The accented character or nil if not found
local function replace_accent(accent, letter)
  local map = accent_map[accent]
  if not map then
    return nil
  end
  return map[letter]
end

--- Strip LaTeX commands and convert to plain UTF-8 text
--- @param value string|nil The string to process
--- @return string The stripped and normalized string
local function strip_latex(value)
  if not value then
    return ''
  end
  for _, wrapper in ipairs(latex_wrappers) do
    value = value:gsub(wrapper .. "%b{}", function(match)
      return match:sub(#wrapper + 2, -2)
    end)
  end
  value = value:gsub("\\([\"'`%^~=%.uvHcrk])%s*%{?(\\?%a)%}?", function(accent, letter)
    if letter:sub(1, 1) == '\\' then
      letter = accent_letter_aliases[letter] or letter:sub(2)
    end
    return replace_accent(accent, letter) or letter
  end)
  value = value:gsub("\\(%a+)", function(command)
    local replacement = simple_commands[command]
    if replacement then
      return replacement
    end
    return ''
  end)
  value = value:gsub("%b{}", function(match)
    return match:sub(2, -2)
  end)
  value = value:gsub("~", " ")
  value = value:gsub("\\", "")
  value = value:gsub("%s+", " ")
  return trim(value)
end

--- Read a balanced block of text (e.g., matching braces)
--- @param str string The input string
--- @param start number Starting position
--- @param open_char string Opening character
--- @param close_char string Closing character
--- @return string|nil, number The extracted block and next position
local function read_balanced_block(str, start, open_char, close_char)
  if not open_char or not close_char then
    return nil, start
  end
  local depth = 0
  local i = start
  local len = #str
  while i <= len do
    local ch = str:sub(i, i)
    if ch == open_char then
      depth = depth + 1
    elseif ch == close_char then
      depth = depth - 1
      if depth == 0 then
        return str:sub(start, i), i + 1
      end
    elseif ch == '\\' then
      i = i + 1
    end
    i = i + 1
  end
  return str:sub(start), len + 1
end

--- Read a braced value from a BibTeX field
--- @param str string The input string
--- @param start number Starting position
--- @return string, number The extracted value and next position
local function read_braced_value(str, start)
  local block, next_index = read_balanced_block(str, start, '{', '}')
  if not block then
    return '', next_index
  end
  return block:sub(2, -2), next_index
end

--- Read a quoted value from a BibTeX field
--- @param str string The input string
--- @param start number Starting position
--- @return string, number The extracted value and next position
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

--- Parse BibTeX entry fields
--- @param body string The entry body content
--- @return table<string, string> Parsed fields as key-value pairs
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

--- Parse a single BibTeX entry
--- @param raw_entry string The raw entry text
--- @return table|nil Parsed entry with key and fields, or nil if invalid
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

--- Parse BibTeX content into a list of entries
--- @param content string The BibTeX file content
--- @return table[] List of parsed entries
function M.parse(content)
  local entries = {}
  local i = 1
  local len = #content
  while i <= len do
    local entry_start, entry_end, entrytype = content:find('@(%w+)', i)
    if not entry_start then
      break
    end
    local pos = entry_end + 1
    while pos <= len and content:sub(pos, pos):match('%s') do
      pos = pos + 1
    end
    local opener = content:sub(pos, pos)
    local closer = nil
    if opener == '{' then
      closer = '}'
    elseif opener == '(' then
      closer = ')'
    end
    local block, next_index = read_balanced_block(content, pos, opener, closer)
    if block then
      local parsed = parse_entry(block)
      if parsed then
        parsed.entrytype = entrytype:lower()
        entries[#entries + 1] = parsed
      end
      i = next_index
    else
      i = pos + 1
    end
  end
  return entries
end

--- Parse a BibTeX file and return all entries
--- @param path string The file path to parse
--- @return table[] List of parsed entries
--- @error Throws an error if the file cannot be opened
function M.parse_file(path)
  local fd, err = io.open(path, 'r')
  if not fd then
    error(string.format('Cannot open file %s: %s', path, err or 'unknown error'))
  end
  local content = fd:read('*a')
  fd:close()
  
  -- Check file extension to determine format
  if path:match('%.ya?ml$') then
    return M.parse_hayagriva(content)
  end
  
  return M.parse(content)
end

--- Remove surrounding quotes from a string
--- Handles both single and double quotes, but only if they match at both ends
--- @param value string The string to unquote
--- @return string The unquoted string
local function unquote(value)
  if not value or value == '' then
    return ''
  end
  -- Remove matching double quotes
  if value:match('^".*"$') then
    return value:sub(2, -2)
  end
  -- Remove matching single quotes
  if value:match("^'.*'$") then
    return value:sub(2, -2)
  end
  return value
end

--- Map Hayagriva field names to BibTeX equivalents
--- @param field_name string The Hayagriva field name
--- @return string The BibTeX field name
local function map_hayagriva_field(field_name)
  if field_name == 'date' then
    return 'year'
  end
  return field_name
end

--- Parse Hayagriva YAML content into BibTeX-compatible entries
--- @param content string The YAML file content
--- @return table[] List of parsed entries
function M.parse_hayagriva(content)
  local entries = {}
  
  -- Simple YAML parser for Hayagriva format
  -- This is a basic parser that handles common Hayagriva structures
  -- It doesn't aim to be a full YAML parser but supports the subset used by Hayagriva
  local current_key = nil
  local current_entry = nil
  local current_field = nil
  local collecting_array = false
  local array_values = {}
  
  for line in content:gmatch('[^\r\n]+') do
    -- Skip empty lines and comments
    if line:match('^%s*$') or line:match('^%s*#') then
      goto continue
    end
    
    -- Top-level key (entry key) - no leading whitespace before key
    -- Supports keys with alphanumeric, underscore, and hyphen
    -- We use a conservative pattern to avoid ambiguity with the colon field separator
    local key = line:match('^([%w_%-]+):%s*$')
    if key then
      -- Finalize any array being collected
      if collecting_array and current_field and #array_values > 0 then
        current_entry[current_field] = table.concat(array_values, ' and ')
        collecting_array = false
        array_values = {}
        current_field = nil
      end
      
      -- Save previous entry if exists
      if current_key and current_entry then
        entries[#entries + 1] = {
          key = current_key,
          entrytype = current_entry.type or 'misc',
          fields = current_entry,
        }
      end
      -- Start new entry
      current_key = key
      current_entry = {}
      goto continue
    end
    
    -- Array item (starts with - after whitespace)
    local array_item = line:match('^%s+%-%s+(.+)$')
    if array_item and collecting_array then
      array_item = unquote(array_item)
      array_values[#array_values + 1] = trim(array_item)
      goto continue
    end
    
    -- Field within an entry (has leading whitespace)
    local field, value = line:match('^%s+([%w_%-]+):%s*(.*)$')
    if field and current_entry then
      -- Finalize any previous array being collected
      if collecting_array and current_field and #array_values > 0 then
        current_entry[current_field] = table.concat(array_values, ' and ')
        array_values = {}
      end
      
      -- Remove quotes from value if present
      value = unquote(value)
      value = trim(value)
      
      -- Map Hayagriva fields to BibTeX fields
      local field_lower = field:lower()
      local mapped_field = map_hayagriva_field(field_lower)
      
      if value == '' then
        -- Empty value means array follows
        collecting_array = true
        current_field = mapped_field
      else
        collecting_array = false
        current_field = nil
        
        if field_lower == 'type' then
          current_entry.type = value
        else
          current_entry[mapped_field] = value
        end
      end
    end
    
    ::continue::
  end
  
  -- Finalize any array being collected
  if collecting_array and current_field and #array_values > 0 then
    current_entry[current_field] = table.concat(array_values, ' and ')
  end
  
  -- Add the last entry
  if current_key and current_entry then
    entries[#entries + 1] = {
      key = current_key,
      entrytype = current_entry.type or 'misc',
      fields = current_entry,
    }
  end
  
  return entries
end

return M
