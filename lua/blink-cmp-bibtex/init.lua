--- blink-cmp-bibtex completion source
--- Provides BibTeX citation completion for blink.cmp
--- @module 'blink-cmp-bibtex'

local config = require('blink-cmp-bibtex.config')
local scan = require('blink-cmp-bibtex.scan')
local cache = require('blink-cmp-bibtex.cache')
local local_bib = require('blink-cmp-bibtex.local_bib')
local matchers = require('blink-cmp-bibtex.matchers')

--- @class Source
--- @field opts table Configuration options for this source instance
local Source = {}
Source.__index = Source

--- A cached entry, remembered so it can later be copied to a local bib file
--- @class BibEntryRef
--- @field raw string The raw BibTeX text of the entry
--- @field source_path string The file the entry was read from
--- @field is_global boolean Whether source_path is one of the configured global files

--- Global lookup table for entry raw text, keyed by citation key
--- @type table<string, BibEntryRef>
local entry_lookup = {}

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

--- Check if a file path is in the global_files list
--- @param path string The file path to check
--- @param global_files table|nil List of global file patterns
--- @return boolean True if the path matches a global file pattern
local function is_global_file(path, global_files)
  if not global_files or #global_files == 0 then
    return false
  end
  -- Normalize input path for consistent comparison
  local normalized_path = vim.fs.normalize(path)
  for _, gf in ipairs(global_files) do
    local expanded = vim.fn.expand(gf)
    local normalized = vim.fs.normalize(expanded)
    if normalized_path == normalized then
      return true
    end
  end
  return false
end

--- Normalize whitespace for content comparison
--- @param s string|nil
--- @return string
local function normalize_whitespace(s)
  if not s then
    return ''
  end
  -- Parenthesized so the gsub replacement count is not returned alongside the string.
  return (s:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Source status for an entry
--- @class SourceInfo
--- @field status 'unique'|'identical'|'modified'
--- @field is_local boolean
--- @field is_global boolean

--- Compute source status for all entries
--- @param entries table[] Raw entries from cache.collect
--- @param global_files table|nil List of global file patterns
--- @return table<string, SourceInfo> Map of key -> source info
--- @return boolean has_mixed True if entries from both local and global
local function compute_source_status(entries, global_files)
  -- Build set of normalized global file paths
  local global_set = {}
  for _, gf in ipairs(global_files or {}) do
    local expanded = vim.fn.expand(gf)
    local normalized = vim.fs.normalize(expanded)
    global_set[normalized] = true
  end

  -- Group entries by key, tracking source and content
  local by_key = {} -- key -> { local_raw, global_raw, is_local, is_global }

  for _, entry in ipairs(entries) do
    local key = entry.key
    local path = vim.fs.normalize(entry.source_path)
    local is_global = global_set[path] or false
    local raw = normalize_whitespace(entry.raw)

    if not by_key[key] then
      by_key[key] = { is_local = false, is_global = false }
    end

    if is_global then
      by_key[key].is_global = true
      by_key[key].global_raw = by_key[key].global_raw or raw
    else
      by_key[key].is_local = true
      by_key[key].local_raw = by_key[key].local_raw or raw
    end
  end

  -- Compute status and check for mixed sources
  local has_any_local, has_any_global = false, false
  local result = {}

  for key, info in pairs(by_key) do
    if info.is_local then
      has_any_local = true
    end
    if info.is_global then
      has_any_global = true
    end

    local status = 'unique'
    if info.is_local and info.is_global then
      status = (info.local_raw == info.global_raw) and 'identical' or 'modified'
    end

    result[key] = {
      status = status,
      is_local = info.is_local,
      is_global = info.is_global,
    }
  end

  return result, (has_any_local and has_any_global)
end

--- Format source indicator based on source info
--- @param info SourceInfo
--- @return string
local function format_source_indicator(info)
  if info.status == 'unique' then
    if info.is_local and not info.is_global then
      return '[L]'
    elseif info.is_global and not info.is_local then
      return '[G]'
    end
  elseif info.status == 'identical' then
    return '[L=G]'
  elseif info.status == 'modified' then
    return '[L≠G]'
  end
  return ''
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
  -- Trim whitespace and strip leading @ symbol (for multi-ref Pandoc citations)
  local trimmed = candidate:match('^%s*(.-)%s*$') or ''
  return trimmed:match('^@(.*)$') or trimmed
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

--- Extract citation context from the current line and cursor position
--- @param context table Completion context from blink.cmp
--- @param opts table Configuration options
--- @param filetype string|nil The filetype of the current buffer
--- @return BibtexMatchResult|nil result Detection result with prefix and trigger type
--- @return BibtexMatcherSpec|nil spec The matcher that produced the result
local function extract_context(context, opts, filetype)
  local line = context.line or ''
  local col = context.cursor and context.cursor[2] or #line
  local text = line:sub(1, col)
  return matchers.detect(text, opts, {
    bufnr = context.bufnr,
    filetype = filetype,
    line = line,
    col = col,
  })
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

    -- Compute source status from all entries (before filtering and dedup)
    local source_status, has_mixed = compute_source_status(entries, self.opts.global_files)
    local show_indicator = self.opts.source_indicator and has_mixed

    local filtered = filter_entries(entries, prefix)

    -- Sort entries: local first, then global (for deduplication to prefer local)
    table.sort(filtered, function(a, b)
      local a_global = is_global_file(a.source_path, self.opts.global_files)
      local b_global = is_global_file(b.source_path, self.opts.global_files)
      if a_global ~= b_global then
        return not a_global -- local (false) before global (true)
      end
      return a.key < b.key
    end)

    local items = {}
    local style = get_preview_style(self.opts.preview_style)
    local seen_keys = {}

    for _, entry in ipairs(filtered) do
      -- Deduplicate: only process first occurrence (local preferred due to sort)
      if not seen_keys[entry.key] then
        seen_keys[entry.key] = true

        local ctx = build_entry_context(entry)
        local is_global = is_global_file(entry.source_path, self.opts.global_files)
        local detail_text = style.detail(ctx)

        -- Get indicator for labelDetails.description (shown on right side)
        local indicator = ''
        if show_indicator then
          local info = source_status[entry.key]
          if info then
            indicator = format_source_indicator(info)
          end
        end

        -- Store entry in lookup table for later use (e.g., copy to local bib)
        if entry.raw then
          entry_lookup[entry.key] = {
            raw = entry.raw,
            source_path = entry.source_path,
            is_global = is_global,
          }
        end

        items[#items + 1] = {
          label = entry.key,
          insertText = entry.key,
          kind = completion_kind,
          detail = detail_text,
          labelDetails = indicator ~= '' and { description = indicator } or nil,
          documentation = style.documentation(ctx),
          data = {
            source = 'blink-cmp-bibtex',
            key = entry.key,
          },
        }
      end
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

--- Execute after a completion item is accepted
--- Used for auto_add functionality to copy global entries to local bib
--- @param context table Completion context from blink.cmp
--- @param item table The accepted completion item
--- @param callback function Callback to invoke when done
--- @param default_implementation function Default execute implementation
function Source:execute(context, item, callback, default_implementation)
  -- Run default implementation first
  if default_implementation then
    default_implementation(context, item)
  end

  -- Check if auto_add is enabled
  local opts = self.opts
  if not opts.local_bib or not opts.local_bib.enabled or not opts.local_bib.auto_add then
    callback()
    return
  end

  -- Get entry key from item data
  local key = item.data and item.data.key
  if not key then
    callback()
    return
  end

  -- Only auto-add if entry is from a global file
  local entry_data = entry_lookup[key]
  if entry_data and entry_data.is_global then
    local_bib.copy_entry(key, entry_data.raw, opts.local_bib)
  end

  callback()
end

--- Setup function exposed for user configuration
Source.setup = config.setup

--- Internal helpers exposed for testing. Not part of the public API.
Source.__test = { extract_context = extract_context, sanitize_prefix = sanitize_prefix }

--- Copy a BibTeX entry to the local bib file
--- @param key string|nil The citation key to copy (if nil, try to detect from cursor)
--- @return boolean True if entry was copied successfully
function Source.copy_to_local_bib(key)
  local opts = config.get()
  if not opts.local_bib or not opts.local_bib.enabled then
    local msg = 'local_bib is not enabled. Set local_bib.enabled = true in your config'
    vim.notify(msg, vim.log.levels.WARN, { title = 'blink-cmp-bibtex' })
    return false
  end

  -- If no key provided, try to detect from cursor position
  if not key or key == '' then
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    -- Try to extract citation key under/before cursor
    local text = line:sub(1, col + 1)
    -- Match citation key patterns (word chars, colon, underscore, dot, hyphen)
    key = text:match('@([%w:_%.%-]+)$') or text:match('{([%w:_%.%-]+)$') or text:match(',([%w:_%.%-]+)$')
    if not key then
      vim.notify('No citation key found at cursor', vim.log.levels.WARN, { title = 'blink-cmp-bibtex' })
      return false
    end
  end

  -- Get current bib paths for validation
  local bufnr = vim.api.nvim_get_current_buf()
  local paths = scan.resolve_bib_paths(bufnr, opts)

  -- Build set of current paths for validation
  local current_paths = {}
  for _, p in ipairs(paths) do
    current_paths[vim.fs.normalize(p)] = true
  end

  -- Look up the entry in our cache, validating source_path is current
  --- @type BibEntryRef|nil
  local entry_data = entry_lookup[key]
  if entry_data and entry_data.source_path then
    local normalized = vim.fs.normalize(entry_data.source_path)
    if not current_paths[normalized] then
      -- Cached entry is from a different project/context, invalidate it
      entry_data = nil
    end
  end

  if not entry_data or not entry_data.raw then
    -- Entry not in lookup or stale - reload from current bib files
    local entries = cache.collect(paths, opts.max_entries)
    for _, entry in ipairs(entries) do
      if entry.key == key and entry.raw then
        local is_global = is_global_file(entry.source_path, opts.global_files)
        entry_data = {
          raw = entry.raw,
          source_path = entry.source_path,
          is_global = is_global,
        }
        entry_lookup[key] = entry_data
        break
      end
    end
  end

  if not entry_data or not entry_data.raw then
    local msg = string.format("Entry '%s' not found in any bib file", key)
    vim.notify(msg, vim.log.levels.WARN, { title = 'blink-cmp-bibtex' })
    return false
  end

  return local_bib.copy_entry(key, entry_data.raw, opts.local_bib)
end

--- Get the entry lookup table (for debugging/testing)
--- @return table<string, BibEntryRef>
function Source.get_entry_lookup()
  return entry_lookup
end

--- Debug function to inspect source indicator state
--- @return table Debug information
function Source.debug_source_indicators()
  local opts = config.get()
  local bufnr = vim.api.nvim_get_current_buf()
  local paths = scan.resolve_bib_paths(bufnr, opts)
  local entries = cache.collect(paths, opts.max_entries)

  -- Build global_set the same way as compute_source_status
  local global_set = {}
  for _, gf in ipairs(opts.global_files or {}) do
    local expanded = vim.fn.expand(gf)
    local normalized = vim.fs.normalize(expanded)
    global_set[normalized] = true
  end

  -- Classify each entry
  local classification = {}
  for _, entry in ipairs(entries) do
    local path = vim.fs.normalize(entry.source_path)
    local is_global = global_set[path] or false
    classification[entry.key] = {
      source_path = entry.source_path,
      normalized_path = path,
      is_global = is_global,
    }
  end

  -- Compute source status
  local source_status, has_mixed = compute_source_status(entries, opts.global_files)

  return {
    global_files_config = opts.global_files,
    global_set = global_set,
    resolved_paths = paths,
    source_indicator_enabled = opts.source_indicator,
    has_mixed = has_mixed,
    entry_count = #entries,
    sample_entries = classification,
    source_status = source_status,
  }
end

return Source
