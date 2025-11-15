local config = require('blink-bibtex.config')
local scan = require('blink-bibtex.scan')
local cache = require('blink-bibtex.cache')

local Source = {}
Source.__index = Source

local cmp_kinds = require('blink.cmp.types').CompletionItemKind
local completion_kind = cmp_kinds.Reference or cmp_kinds.Value or cmp_kinds.Text or 1

local function table_is_empty(tbl)
  if not tbl then
    return true
  end
  if vim.tbl_isempty then
    return vim.tbl_isempty(tbl)
  end
  return next(tbl) == nil
end

local function sanitize_prefix(prefix)
  prefix = prefix or ''
  local normalized = prefix:gsub(';', ',')
  local segments = vim.split(normalized, ',', { trimempty = false })
  local candidate = segments[#segments] or ''
  candidate = candidate:gsub('^%s+', '')
  candidate = candidate:gsub('%s+$', '')
  return candidate
end

local function format_author_list(fields)
  local author = fields.author
  if (not author or author == '') and fields.editor then
    author = fields.editor
  end
  if not author or author == '' then
    return nil
  end
  local names = vim.split(author, '%s+and%s+', { trimempty = true })
  if #names == 0 then
    return author
  end
  if #names == 1 then
    return names[1]
  end
  if #names == 2 then
    return string.format('%s & %s', names[1], names[2])
  end
  local last = names[#names]
  names[#names] = '& ' .. last
  return table.concat(names, ', ')
end

local function format_container(fields)
  local journal = fields.journaltitle or fields.journal
  local booktitle = fields.booktitle
  local publisher = fields.publisher
  local location = fields.location or fields.address
  if journal then
    return journal
  end
  if booktitle then
    if publisher then
      if location then
        return string.format('%s — %s (%s)', booktitle, publisher, location)
      end
      return string.format('%s — %s', booktitle, publisher)
    end
    return booktitle
  end
  if publisher and location then
    return string.format('%s (%s)', publisher, location)
  end
  return publisher or nil
end

local function format_detail(entry)
  local fields = entry.fields or {}
  local author = format_author_list(fields) or 'Unknown'
  local year = fields.year or fields.date or 'n.d.'
  local title = fields.title or fields.booktitle or '[no title]'
  local container = format_container(fields)
  if container then
    return string.format('%s (%s) – %s (%s)', author, year, title, container)
  end
  return string.format('%s (%s) – %s', author, year, title)
end

local function format_documentation(entry)
  local fields = entry.fields or {}
  local author = format_author_list(fields)
  local year = fields.year or fields.date or 'n.d.'
  local title = fields.title or fields.booktitle or '[no title]'
  local journal = fields.journaltitle or fields.journal
  local publisher = fields.publisher
  local volume = fields.volume
  local number = fields.number or fields.issue
  local pages = fields.pages
  local doi = fields.doi
  local url = fields.url
  local lines = {}
  if author then
    table.insert(lines, string.format('%s (%s).', author, year))
  else
    table.insert(lines, string.format('(%s).', year))
  end
  table.insert(lines, string.format('%s.', title))
  if journal then
    local segment = journal
    if volume then
      segment = string.format('%s, %s', segment, volume)
      if number then
        segment = string.format('%s(%s)', segment, number)
      end
    end
    if pages then
      segment = string.format('%s, %s', segment, pages)
    end
    table.insert(lines, segment)
  elseif publisher then
    if pages then
      table.insert(lines, string.format('%s, %s', publisher, pages))
    else
      table.insert(lines, publisher)
    end
  end
  if doi then
    table.insert(lines, string.format('https://doi.org/%s', doi:gsub('^https?://doi.org/', '')))
  elseif url then
    table.insert(lines, url)
  end
  return table.concat(lines, '\n')
end

local function match_latex_citation(text, opts)
  local brace_start = text:match('()%{[^{}]*$')
  if not brace_start then
    return nil
  end
  local prefix = text:sub(brace_start + 1)
  local before = text:sub(1, brace_start - 1)
  local cursor = #before
  while cursor > 0 and before:sub(cursor, cursor):match('%s') do
    cursor = cursor - 1
  end
  local function skip_optional()
    while cursor > 0 and before:sub(cursor, cursor) == ']' do
      cursor = cursor - 1
      local depth = 1
      while cursor > 0 and depth > 0 do
        local ch = before:sub(cursor, cursor)
        if ch == '[' then
          depth = depth - 1
        elseif ch == ']' then
          depth = depth + 1
        end
        cursor = cursor - 1
      end
      while cursor > 0 and before:sub(cursor, cursor):match('%s') do
        cursor = cursor - 1
      end
    end
  end
  skip_optional()
  local command_segment = before:sub(1, cursor)
  local command = command_segment:match('\\([%a@]+)$')
  if not command then
    return nil
  end
  for _, allowed in ipairs(opts.citation_commands or {}) do
    if command == allowed then
      return {
        prefix = prefix,
        command = command,
        trigger = 'latex',
      }
    end
  end
  return nil
end

local function match_pandoc_citation(text)
  local prefix = text:match('%[@([^%]]*)$')
  if prefix then
    return { prefix = prefix, trigger = 'pandoc' }
  end
  local boundary = text:match('[^%w@]@([%w:_%-%./]*)$')
  if boundary then
    return { prefix = boundary, trigger = 'pandoc' }
  end
  local line_start = text:match('^@([%w:_%-%./]*)$')
  if line_start then
    return { prefix = line_start, trigger = 'pandoc' }
  end
  return nil
end

local function extract_context(context, opts)
  local line = context.line or ''
  local col = context.cursor and context.cursor[2] or #line
  local text = line:sub(1, col)
  local latex = match_latex_citation(text, opts)
  if latex then
    return latex
  end
  return match_pandoc_citation(text)
end

local function filter_entries(entries, prefix)
  local items = {}
  local lowered = prefix:lower()
  for _, entry in ipairs(entries) do
    if lowered == '' or entry.key:lower():find(lowered, 1, true) == 1 then
      table.insert(items, entry)
    end
  end
  return items
end

function Source.new(opts, provider_config)
  local self = setmetatable({}, Source)
  self.opts = config.extend(opts)
  self.provider_config = provider_config or {}
  return self
end

function Source:get_completions(context, callback)
  local bufnr = context.buffer or vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  if #self.opts.filetypes > 0 and not vim.tbl_contains(self.opts.filetypes, ft) then
    callback()
    return function() end
  end
  local detection = extract_context(context, self.opts)
  if not detection then
    callback()
    return function() end
  end
  local prefix = sanitize_prefix(detection.prefix)
  local paths = scan.resolve_bib_paths(bufnr, self.opts)
  if table_is_empty(paths) then
    callback()
    return function() end
  end
  local cancelled = false
  vim.schedule(function()
    if cancelled then
      return
    end
    local entries = cache.collect(paths, self.opts.max_entries)
    local filtered = filter_entries(entries, prefix)
    local items = {}
    for _, entry in ipairs(filtered) do
      items[#items + 1] = {
        label = entry.key,
        insertText = entry.key,
        kind = completion_kind,
        detail = format_detail(entry),
        documentation = format_documentation(entry),
      }
    end
    callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
  end)
  return function()
    cancelled = true
  end
end

function Source:resolve(item, callback)
  callback(item)
end

Source.setup = config.setup

return Source
