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

--- Entry raw text from the most recent completion round, keyed by citation key
--- @type table<string, BibEntryRef>
local entry_lookup = {}

--- The same table from the round before it
--- Two generations are kept so that Source:execute still resolves an accepted
--- item when a new round has already replaced the lookup, while the memory a
--- session holds stays bounded by two rounds instead of growing with every key
--- ever completed.
--- @type table<string, BibEntryRef>
local previous_entry_lookup = {}

--- Look up a remembered entry, falling back to the previous round
--- @param key string The citation key
--- @return BibEntryRef|nil
local function recall_entry(key)
  return entry_lookup[key] or previous_entry_lookup[key]
end

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
--- @param global_set table<string, boolean> The set scan.global_set built
--- @return table<string, SourceInfo> Map of key -> source info
--- @return boolean has_mixed True if entries from both local and global
local function compute_source_status(entries, global_set)
  -- Group entries by key, tracking source and content
  local by_key = {} -- key -> { local_raw, global_raw, is_local, is_global }

  for _, entry in ipairs(entries) do
    local key = entry.key
    local is_global = scan.is_global_path(entry.source_path, global_set)
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

--- Characters that separate keys when a matcher does not say otherwise
--- @type string
local DEFAULT_SEPARATORS = ',;'

--- Sanitize a citation key prefix by handling multi-key citations
--- Extracts the last citation key being typed when several keys are listed.
--- Which characters separate them depends on the syntax: LaTeX and Typst use a
--- comma, while Pandoc also uses a semicolon. A semicolon is an ordinary
--- character in a key otherwise, and the parser accepts it as one.
--- @param prefix string|nil The raw prefix string
--- @param separators string|nil Separator characters; defaults to a comma and a semicolon
--- @return string The sanitized prefix for the current key
local function sanitize_prefix(prefix, separators)
  if not prefix or prefix == '' then
    return ''
  end
  separators = separators or DEFAULT_SEPARATORS
  if separators == '' then
    separators = DEFAULT_SEPARATORS
  end
  -- Normalize every separator to the first one, then take the last segment
  local primary = separators:sub(1, 1)
  local normalized = prefix
  for index = 2, #separators do
    normalized = normalized:gsub('%' .. separators:sub(index, index), primary)
  end
  local segments = vim.split(normalized, primary, { plain = true, trimempty = false })
  local candidate = segments[#segments] or ''
  -- Trim whitespace and strip leading @ symbol (for multi-ref Pandoc citations)
  local trimmed = candidate:match('^%s*(.-)%s*$') or ''
  return trimmed:match('^@(.*)$') or trimmed
end

--- The key separators that apply to a match
--- @param detection BibtexMatchResult The match result
--- @param spec BibtexMatcherSpec|nil The matcher that produced it
--- @return string
local function separators_for(detection, spec)
  return detection.separators or (spec and spec.separators) or DEFAULT_SEPARATORS
end

--- Whether a detected prefix should be reduced to the key being typed
--- A match may opt out per match or per matcher; sanitizing is the default.
--- @param detection BibtexMatchResult The match result
--- @param spec BibtexMatcherSpec|nil The matcher that produced it
--- @return boolean
local function wants_sanitized_prefix(detection, spec)
  local wanted = detection.sanitize
  if wanted == nil then
    wanted = spec and spec.sanitize
  end
  if wanted == nil then
    wanted = true
  end
  return wanted
end

--- Characters that end a citation key in one syntax or another
--- The parser accepts any run of non-comma, non-whitespace characters as a key,
--- so the cursor scan stops at delimiters rather than at an allowed alphabet:
--- otherwise a key like smith/2020 or a+b would be cut at its punctuation.
--- @type string
local KEY_DELIMITERS = [[%s,{}%[%]()<>"'\]]

--- Matches one character a citation key may contain
--- @type string
local KEY_CHARACTER = '[^' .. KEY_DELIMITERS .. ']'

--- Detect the citation key the cursor sits in or after
--- The matchers read the text up to the cursor, while the cursor here may sit
--- anywhere inside a finished key, so the text is first extended to the end of
--- that key. The chain runs for the buffer's filetype, which is what makes the
--- GAPDoc and user-registered syntaxes work here and not just in completion.
--- The original patterns remain as a fallback for text no matcher claims.
--- @param bufnr number The buffer to read the filetype from
--- @param opts table Configuration options
--- @return string|nil The citation key, or nil when the cursor is not on one
local function key_under_cursor(bufnr, opts)
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local finish = math.min(col + 1, #line)
  while finish < #line and line:sub(finish + 1, finish + 1):match(KEY_CHARACTER) do
    finish = finish + 1
  end
  -- A separator the scan swallowed belongs to the next key, not to this one.
  local text = line:sub(1, finish):gsub('[,;]+$', '')

  local detection, spec = matchers.detect(text, opts, {
    bufnr = bufnr,
    filetype = vim.bo[bufnr].filetype,
    line = line,
    col = finish,
  })
  if detection then
    local key = detection.prefix
    if wants_sanitized_prefix(detection, spec) then
      key = sanitize_prefix(detection.prefix, separators_for(detection, spec))
    end
    if key and key ~= '' then
      return key
    end
  end

  return text:match('@(' .. KEY_CHARACTER .. '+)$')
    or text:match('{(' .. KEY_CHARACTER .. '+)$')
    or text:match(',(' .. KEY_CHARACTER .. '+)$')
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

--- Whether the source is active in the current buffer
--- blink.cmp collects trigger characters only from enabled providers, which is
--- what keeps matcher trigger characters scoped to their filetypes.
--- @return boolean
function Source:enabled()
  local ft = vim.bo.filetype
  return #self.opts.filetypes == 0 or vim.tbl_contains(self.opts.filetypes, ft)
end

--- Characters that should open the completion menu in the current buffer
--- @return string[]
function Source:get_trigger_characters()
  return matchers.trigger_characters(vim.bo.filetype, self.opts)
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
  local detection, spec = extract_context(context, self.opts, ft)
  if not detection then
    callback(empty_response())
    return function() end
  end
  local prefix = detection.prefix or ''
  if wants_sanitized_prefix(detection, spec) then
    prefix = sanitize_prefix(detection.prefix, separators_for(detection, spec))
  end
  local paths = scan.resolve_bib_paths(bufnr, self.opts)
  if table_is_empty(paths) then
    callback(empty_response())
    return function() end
  end
  -- Built once for the round: global_files may be a function, and resolving it
  -- per entry would call it once per completion item.
  local global_set = scan.global_set(self.opts, bufnr)
  local cancelled = false
  vim.schedule(function()
    if cancelled then
      return
    end
    local entries = cache.collect(paths, self.opts.max_entries)

    -- Compute source status from all entries (before filtering and dedup)
    local source_status, has_mixed = compute_source_status(entries, global_set)
    local show_indicator = self.opts.source_indicator and has_mixed

    local filtered = filter_entries(entries, prefix)

    -- Sort entries: local first, then global (for deduplication to prefer local)
    table.sort(filtered, function(a, b)
      local a_global = scan.is_global_path(a.source_path, global_set)
      local b_global = scan.is_global_path(b.source_path, global_set)
      if a_global ~= b_global then
        return not a_global -- local (false) before global (true)
      end
      return a.key < b.key
    end)

    local items = {}
    local style = get_preview_style(self.opts.preview_style)
    local seen_keys = {}
    -- Built fresh per round and swapped in below, so a round that is cancelled
    -- or fails part way leaves the remembered entries untouched.
    local round_lookup = {}

    for _, entry in ipairs(filtered) do
      -- Deduplicate: only process first occurrence (local preferred due to sort)
      if not seen_keys[entry.key] then
        seen_keys[entry.key] = true

        local ctx = build_entry_context(entry)
        local is_global = scan.is_global_path(entry.source_path, global_set)
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
          round_lookup[entry.key] = {
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
    previous_entry_lookup = entry_lookup
    entry_lookup = round_lookup
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
  local entry_data = recall_entry(key)
  if entry_data and entry_data.is_global then
    local_bib.copy_entry(key, entry_data.raw, opts.local_bib)
  end

  callback()
end

--- Setup function exposed for user configuration
Source.setup = config.setup

--- Internal helpers exposed for testing. Not part of the public API.
Source.__test = {
  extract_context = extract_context,
  sanitize_prefix = sanitize_prefix,
  key_under_cursor = key_under_cursor,
}

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

  local bufnr = vim.api.nvim_get_current_buf()

  -- If no key provided, try to detect from cursor position
  if not key or key == '' then
    key = key_under_cursor(bufnr, opts)
    if not key then
      vim.notify('No citation key found at cursor', vim.log.levels.WARN, { title = 'blink-cmp-bibtex' })
      return false
    end
  end

  -- Get current bib paths for validation
  local paths = scan.resolve_bib_paths(bufnr, opts)

  -- Build set of current paths for validation
  local current_paths = {}
  for _, p in ipairs(paths) do
    current_paths[vim.fs.normalize(p)] = true
  end

  -- Look up the entry in our cache, validating source_path is current
  --- @type BibEntryRef|nil
  local entry_data = recall_entry(key)
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
    local global_set = scan.global_set(opts, bufnr)
    for _, entry in ipairs(entries) do
      if entry.key == key and entry.raw then
        local is_global = scan.is_global_path(entry.source_path, global_set)
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

--- Get the entry lookup table of the most recent completion round
--- The previous round is retained separately and is not included here.
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

  -- Resolved the same way the scanner resolves it
  local global_set = scan.global_set(opts, bufnr)

  -- Classify each entry
  local classification = {}
  for _, entry in ipairs(entries) do
    classification[entry.key] = {
      source_path = entry.source_path,
      normalized_path = vim.fs.normalize(entry.source_path),
      is_global = scan.is_global_path(entry.source_path, global_set),
    }
  end

  -- Compute source status
  local source_status, has_mixed = compute_source_status(entries, global_set)

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
