--- blink-cmp-bibtex completion source
--- Provides BibTeX citation completion for blink.cmp
--- @module blink-cmp-bibtex

local config = require('blink-cmp-bibtex.config')
local scan = require('blink-cmp-bibtex.scan')
local cache = require('blink-cmp-bibtex.cache')

--- @class Source
--- @field opts table Configuration options for this source instance
local Source = {}
Source.__index = Source

--- Default completion kind (fallback to 1 if blink.cmp types unavailable)
--- @type number
local completion_kind = 1

do
  local ok, cmp_types = pcall(require, 'blink.cmp.types')
  if ok and cmp_types and cmp_types.CompletionItemKind then
    local kinds = cmp_types.CompletionItemKind
    completion_kind = kinds.Reference or kinds.Value or kinds.Text or completion_kind
  end
end

--- Check if a table is empty
--- @param tbl table|nil The table to check
--- @return boolean True if the table is nil or empty
local function table_is_empty(tbl)
  if not tbl then
    return true
  end
  return next(tbl) == nil
end

--- Sanitize a citation key prefix by handling multi-key citations
--- Extracts the last citation key being typed when multiple keys are separated by commas or semicolons
--- @param prefix string|nil The raw prefix string
--- @return string The sanitized prefix for the current key
local function sanitize_prefix(prefix)
  if not prefix or prefix == '' then
    return ''
  end
  -- Normalize semicolons to commas and extract last segment
  local normalized = prefix:gsub(';', ',')
  local segments = vim.split(normalized, ',', { trimempty = false })
  local candidate = segments[#segments] or ''
  -- Trim whitespace in one operation
  return candidate:match('^%s*(.-)%s*$') or ''
end

--- Format author/editor list into a readable string
--- @param fields table BibTeX entry fields
--- @return string|nil Formatted author string or nil if not available
local function format_author_list(fields)
  if not fields then
    return nil
  end
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

--- Format container information (journal, book, publisher)
--- @param fields table BibTeX entry fields
--- @return string|nil Formatted container string or nil if not available
local function format_container(fields)
  if not fields then
    return nil
  end
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

--- Build a context object from a BibTeX entry for preview formatting
--- @param entry table The BibTeX entry
--- @return table Context object with normalized fields
local function build_entry_context(entry)
  if not entry or not entry.fields then
    return {
      author = nil,
      year = 'n.d.',
      title = '[no title]',
      journal = nil,
      publisher = nil,
      volume = nil,
      number = nil,
      pages = nil,
      doi = nil,
      url = nil,
      container = nil,
    }
  end
  local fields = entry.fields
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
  local container = format_container(fields)
  return {
    author = author,
    year = year,
    title = title,
    journal = journal,
    publisher = publisher,
    volume = volume,
    number = number,
    pages = pages,
    doi = doi,
    url = url,
    container = container,
  }
end

--- Available preview style templates
--- @type table<string, {detail: function, documentation: function}>
local preview_styles = {}

preview_styles.apa = {
  detail = function(ctx)
    local author = ctx.author or 'Unknown'
    if ctx.container then
      return string.format('%s (%s) – %s (%s)', author, ctx.year, ctx.title, ctx.container)
    end
    return string.format('%s (%s) – %s', author, ctx.year, ctx.title)
  end,
  documentation = function(ctx)
    local lines = {}
    if ctx.author then
      table.insert(lines, string.format('%s (%s).', ctx.author, ctx.year))
    else
      table.insert(lines, string.format('(%s).', ctx.year))
    end
    table.insert(lines, string.format('%s.', ctx.title))
    if ctx.journal then
      local segment = ctx.journal
      if ctx.volume then
        segment = string.format('%s, %s', segment, ctx.volume)
        if ctx.number then
          segment = string.format('%s(%s)', segment, ctx.number)
        end
      end
      if ctx.pages then
        segment = string.format('%s, %s', segment, ctx.pages)
      end
      table.insert(lines, segment .. '.')
    elseif ctx.container then
      table.insert(lines, ctx.container .. '.')
    elseif ctx.publisher then
      table.insert(lines, ctx.publisher .. '.')
    end
    if ctx.doi then
      table.insert(lines, 'https://doi.org/' .. ctx.doi:gsub('^https?://doi.org/', ''))
    elseif ctx.url then
      table.insert(lines, ctx.url)
    end
    return table.concat(lines, '\n')
  end,
}

preview_styles.ieee = {
  detail = function(ctx)
    local pieces = {}
    table.insert(pieces, ctx.author or 'Unknown')
    table.insert(pieces, string.format('"%s,"', ctx.title))
    if ctx.journal then
      table.insert(pieces, ctx.journal)
    elseif ctx.container then
      table.insert(pieces, ctx.container)
    end
    if ctx.volume then
      local segment = string.format('vol. %s', ctx.volume)
      if ctx.number then
        segment = string.format('%s, no. %s', segment, ctx.number)
      end
      table.insert(pieces, segment)
    end
    if ctx.pages then
      table.insert(pieces, string.format('pp. %s', ctx.pages))
    end
    table.insert(pieces, string.format('%s.', ctx.year))
    return table.concat(pieces, ' ')
  end,
  documentation = function(ctx)
    local lines = {}
    local line = {}
    table.insert(line, ctx.author or 'Unknown')
    table.insert(line, string.format('"%s,"', ctx.title))
    if ctx.journal then
      table.insert(line, ctx.journal)
    elseif ctx.container then
      table.insert(line, ctx.container)
    end
    if ctx.volume then
      local vol = string.format('vol. %s', ctx.volume)
      if ctx.number then
        vol = string.format('%s, no. %s', vol, ctx.number)
      end
      table.insert(line, vol)
    end
    if ctx.pages then
      table.insert(line, string.format('pp. %s', ctx.pages))
    end
    table.insert(line, string.format('%s.', ctx.year))
    table.insert(lines, table.concat(line, ', '))
    if ctx.publisher then
      table.insert(lines, ctx.publisher .. '.')
    end
    if ctx.doi then
      table.insert(lines, 'DOI: ' .. ctx.doi)
    elseif ctx.url then
      table.insert(lines, 'URL: ' .. ctx.url)
    end
    return table.concat(lines, '\n')
  end,
}

--- Get a preview style by name, falling back to APA if not found
--- @param name string The style name
--- @return table The preview style template
local function get_preview_style(name)
  return preview_styles[name] or preview_styles.apa
end

--- Match LaTeX citation commands in text
--- @param text string The text to search
--- @param opts table Configuration options with citation_commands
--- @return table|nil Citation detection result or nil if no match
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
  local command, modifier = command_segment:match('\\([%a@]+)(%*?)$')
  if not command then
    return nil
  end
  for _, allowed in ipairs(opts.citation_commands or {}) do
    if command == allowed then
      return {
        prefix = prefix,
        command = command .. (modifier or ''),
        trigger = 'latex',
      }
    end
  end
  return nil
end

--- Match Pandoc-style citation syntax
--- @param text string The text to search
--- @return table|nil Citation detection result or nil if no match
local function match_pandoc_citation(text)
  local prefix = text:match('%[@([^%]]*)$')
  if prefix then
    return { prefix = prefix, trigger = 'pandoc' }
  end
  local boundary = text:match('[^%w@]@([%w:_%-%.,]*)$')
  if boundary then
    return { prefix = boundary, trigger = 'pandoc' }
  end
  local line_start = text:match('^@([%w:_%-%.,]*)$')
  if line_start then
    return { prefix = line_start, trigger = 'pandoc' }
  end
  return nil
end

--- Match Typst-style citation syntax
--- @param text string The text to search
--- @return table|nil Citation detection result or nil if no match
local function match_typst_citation(text)
  -- Restrict Typst citation pattern: only match @ after a word character or underscore
  local prefix = text:match("[%w_]@([%w:_%-%.,]*)$") -- match word@abc, not line-start or after non-word
  if prefix then
    return { prefix = prefix, trigger = "typst" }
  end
  local prefix_cite = text:match("#cite%s*%(%s*<([^>]*)$") -- match #cite(<abc
  if prefix_cite then
    return { prefix = prefix_cite, trigger = "typst" }
  end
  return nil
end

--- Extract citation context from the current line and cursor position
--- @param context table Completion context from blink.cmp
--- @param opts table Configuration options
--- @param filetype string|nil The filetype of the current buffer
--- @return table|nil Detection result with prefix and trigger type
local function extract_context(context, opts, filetype)
  local line = context.line or ''
  local col = context.cursor and context.cursor[2] or #line
  local text = line:sub(1, col)
  local latex = match_latex_citation(text, opts)
  if latex then
    return latex
  end
  -- Check Typst patterns first for Typst files to prevent Pandoc interception
  if filetype == 'typst' then
    local typst = match_typst_citation(text)
    if typst then
      return typst
    end
  end
  local pandoc = match_pandoc_citation(text)
  if pandoc then
    return pandoc
  end
  -- Check Typst patterns for other filetypes as fallback
  if filetype ~= 'typst' then
    return match_typst_citation(text)
  end
  return nil
end

--- Filter entries by prefix match
--- @param entries table[] List of BibTeX entries
--- @param prefix string The prefix to match against
--- @return table[] Filtered list of entries
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

--- Return an empty completion response
--- @return table Empty response object
local function empty_response()
  return {
    items = {},
    is_incomplete_forward = false,
    is_incomplete_backward = false,
  }
end

--- Create a new source instance
--- @param opts table|nil Optional configuration overrides
--- @return Source A new source instance
function Source.new(opts)
  local self = setmetatable({}, Source)
  self.opts = config.extend(opts)
  return self
end

--- Get completion items for the current context
--- @param context table Completion context from blink.cmp
--- @param callback function Callback to invoke with completion results
--- @return function Cancellation function
function Source:get_completions(context, callback)
  local bufnr = context.bufnr or vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  if #self.opts.filetypes > 0 and not vim.tbl_contains(self.opts.filetypes, ft) then
    callback(empty_response())
    return function() end
  end
  local detection = extract_context(context, self.opts, ft)
  if not detection then
    callback(empty_response())
    return function() end
  end
  local prefix = sanitize_prefix(detection.prefix)
  local paths = scan.resolve_bib_paths(bufnr, self.opts)
  if table_is_empty(paths) then
    callback(empty_response())
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
    local style = get_preview_style(self.opts.preview_style)
    for _, entry in ipairs(filtered) do
      local ctx = build_entry_context(entry)
      items[#items + 1] = {
        label = entry.key,
        insertText = entry.key,
        kind = completion_kind,
        detail = style.detail(ctx),
        documentation = style.documentation(ctx),
      }
    end
    callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
  end)
  return function()
    cancelled = true
  end
end

--- Resolve additional details for a completion item
--- @param item table The completion item to resolve
--- @param callback function Callback to invoke with resolved item
function Source:resolve(item, callback)
  callback(item)
end

--- Setup function exposed for user configuration
Source.setup = config.setup

return Source
