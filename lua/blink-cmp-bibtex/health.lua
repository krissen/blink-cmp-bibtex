--- Health check for blink-cmp-bibtex, run with `:checkhealth blink-cmp-bibtex`
--- Reports the resolved configuration and flags matcher setups that can never fire.
--- @module 'blink-cmp-bibtex.health'

local config = require('blink-cmp-bibtex.config')
local discovery = require('blink-cmp-bibtex.discovery')
local matchers = require('blink-cmp-bibtex.matchers')
local scan = require('blink-cmp-bibtex.scan')

local M = {}

--- Describe a chain as a readable string
--- Reads only the name and priority every chain entry carries, so it serves the
--- matcher chain and the discovery chain alike.
--- @param chain table[] A matcher or discovery chain
--- @return string
local function describe_chain(chain)
  if #chain == 0 then
    return 'none'
  end
  local parts = {}
  for _, spec in ipairs(chain) do
    parts[#parts + 1] = string.format('%s (priority %d)', spec.name, spec.priority)
  end
  return table.concat(parts, ', ')
end

--- Whether a buffer is the one :checkhealth renders its report into
--- Neovim's runtime names that buffer 'health://', runs every check, and only
--- then sets the 'checkhealth' filetype, so while this check is running the
--- name is what identifies it. The filetype is read as well, for a version
--- that sets it before running the checks.
--- @param bufnr integer The buffer to classify
--- @return boolean
local function is_report_buffer(bufnr)
  if vim.bo[bufnr].filetype == 'checkhealth' then
    return true
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  -- Matched at the front and after a directory, since a version that expands
  -- the name against the working directory reports the latter.
  return name:sub(1, 9) == 'health://' or name:match('/health://$') ~= nil
end

--- The buffer the report is about
--- :checkhealth renders its output in a buffer of its own, so the buffer that
--- is current while check() runs is the report rather than the document the
--- user was editing. The alternate buffer is the one they came from; falling
--- back to a visible buffer covers a report opened without an alternate.
--- @return integer The buffer to resolve bibliographies for
local function target_buffer()
  local current = vim.api.nvim_get_current_buf()
  if not is_report_buffer(current) then
    return current
  end
  local alternate = vim.fn.bufnr('#')
  if alternate > 0 and vim.api.nvim_buf_is_valid(alternate) and not is_report_buffer(alternate) then
    return alternate
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if not is_report_buffer(buf) then
      return buf
    end
  end
  return current
end

--- Render a declaring file for the report
--- Shown relative to the buffer's own directory while it is underneath it,
--- which keeps a project-local declaration short, and as a home-relative path
--- otherwise, which keeps one from elsewhere unambiguous.
--- @param file string The declaring file
--- @param buffer_dir string|nil The directory of the buffer being reported on
--- @return string
local function describe_file(file, buffer_dir)
  local normalized = vim.fs.normalize(file)
  if buffer_dir and buffer_dir ~= '' then
    local prefix = vim.fs.normalize(buffer_dir):gsub('/$', '') .. '/'
    if normalized:sub(1, #prefix) == prefix then
      return normalized:sub(#prefix + 1)
    end
  end
  return vim.fn.fnamemodify(normalized, ':~')
end

--- Describe where a declaration was found, when its origin says
--- A hook that reads its document as one text reports no line, and a hook that
--- reads the project around the buffer reports a file without one.
--- @param origin BibtexBibOrigin The origin to read
--- @param buffer_dir string|nil The directory of the buffer being reported on
--- @param bufname string The name of the buffer being reported on
--- @return string|nil The position, or nil when the origin carries none
local function describe_position(origin, buffer_dir, bufname)
  local declared_in = origin.file or (origin.line and bufname) or nil
  if declared_in and declared_in ~= '' then
    local shown = describe_file(declared_in, buffer_dir)
    return origin.line and string.format('%s:%d', shown, origin.line) or shown
  end
  if origin.line then
    return string.format('line %d', origin.line)
  end
  return nil
end

--- Describe where one bibliography came from
--- @param origin BibtexBibOrigin The origin to describe
--- @param buffer_dir string|nil The directory of the buffer being reported on
--- @param bufname string The name of the buffer being reported on
--- @return string
local function describe_origin(origin, buffer_dir, bufname)
  if origin.kind == 'buffer' then
    local description = 'buffer discovery: ' .. (origin.hook or 'unknown')
    local position = describe_position(origin, buffer_dir, bufname)
    return position and string.format('%s, %s', description, position) or description
  end
  if origin.kind == 'search_paths' then
    return string.format('search_paths: %s', origin.detail)
  end
  if origin.kind == 'local_bib' then
    return 'local_bib.target'
  end
  return origin.kind
end

--- Describe every origin of one bibliography
--- @param source BibtexBibSource The source to describe
--- @param buffer_dir string|nil The directory of the buffer being reported on
--- @param bufname string The name of the buffer being reported on
--- @return string
local function describe_origins(source, buffer_dir, bufname)
  local parts = {}
  for _, origin in ipairs(source.origins) do
    parts[#parts + 1] = describe_origin(origin, buffer_dir, bufname)
  end
  return table.concat(parts, '; also ')
end

--- What a path that is not there means, judged by where it came from
--- A GAP package's conventional bibliography name and a local_bib target that
--- is created on the first copy are not mistakes: nobody wrote them down, and
--- nothing is wrong until something tries to read them. A path the buffer
--- declared is corrected in the document, not in the configuration.
--- @param origin BibtexBibOrigin The origin to classify
--- @param opts table Configuration options
--- @return 'option'|'declared'|'pending' What kind of absence this origin means
local function absence_kind(origin, opts)
  if origin.kind == 'buffer' then
    -- The convention names a file the package never declared anywhere.
    if origin.hook == 'gap_package' and not origin.file then
      return 'pending'
    end
    return 'declared'
  end
  if origin.kind == 'local_bib' and opts.local_bib and opts.local_bib.create_if_missing then
    return 'pending'
  end
  return 'option'
end

--- Report one bibliography that is not there
--- @param source BibtexBibSource The source to report
--- @param opts table Configuration options
--- @param buffer_dir string|nil The directory of the buffer being reported on
--- @param bufname string The name of the buffer being reported on
--- @param shown string The path as it is rendered
--- @return table { level: 'info'|'warn', message: string, advice: string[]|nil }
local function describe_absence(source, opts, buffer_dir, bufname, shown)
  local found = {}
  for _, origin in ipairs(source.origins) do
    found[absence_kind(origin, opts)] = found[absence_kind(origin, opts)] or origin
  end

  if found.option then
    -- Named the way the buffer origins are: the sentence says where the path
    -- was written, which is where it has to be corrected.
    return {
      level = 'warn',
      message = string.format(
        'missing: %s — configured in %s but the file does not exist',
        shown,
        describe_origin(found.option, buffer_dir, bufname)
      ),
      advice = { 'fix the path or remove it from the option' },
    }
  end
  if found.declared then
    local position = describe_position(found.declared, buffer_dir, bufname)
    return {
      level = 'warn',
      message = position
          and string.format('missing: %s — declared in %s but the file does not exist', shown, position)
        or string.format(
          'missing: %s — declared by %s but the file does not exist',
          shown,
          describe_origin(found.declared, buffer_dir, bufname)
        ),
      advice = { 'create the file, or correct the declaration' },
    }
  end
  local pending = found.pending
  local description = pending and pending.kind == 'local_bib' and 'local_bib.target, created on first copy'
    or 'gap_package convention'
  return {
    level = 'info',
    message = string.format('not present yet: %s (%s)', shown, description),
  }
end

--- Run the health check
function M.check()
  local opts = config.get()
  local bufnr = target_buffer()

  -- Resolved per call so that Neovim 0.9's report_* names are honoured and the
  -- reporters stay stubbable from tests.
  local health = vim.health
  --- @type fun(name: string)
  local h_start = health.start or health.report_start
  --- @type fun(message: string)
  local h_ok = health.ok or health.report_ok
  --- @type fun(message: string, advice?: string|string[])
  local h_warn = health.warn or health.report_warn
  --- @type fun(message: string)
  local h_info = health.info or health.report_info

  h_start('blink-cmp-bibtex')

  local filetypes = type(opts.filetypes) == 'table' and opts.filetypes or {}
  if #filetypes == 0 then
    h_info('filetypes: (empty) — the source is offered in every buffer')
  else
    h_ok('filetypes: ' .. table.concat(filetypes, ', '))
  end
  h_info(string.format('preview_style: %s, max_entries: %s', tostring(opts.preview_style), tostring(opts.max_entries)))
  -- files and global_files may be a list, a bare string, or a function, so they
  -- are resolved the same way the scanner resolves them before being counted.
  h_info(string.format('files: %d configured', #scan.resolve_option_list(opts.files, bufnr)))
  h_info(string.format('global_files: %d configured', #scan.resolve_option_list(opts.global_files, bufnr)))
  h_info(string.format('search_paths: %d configured', #scan.resolve_option_list(opts.search_paths, bufnr)))
  h_info(string.format('root_markers: %d configured', #scan.resolve_option_list(opts.root_markers, bufnr)))

  h_start('blink-cmp-bibtex: bibliographies')

  --- Report the bibliographies the buffer resolves, and where each came from
  local function report_bibliographies()
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local buffer_dir = bufname ~= '' and vim.fs.dirname(bufname) or nil
    local filetype = vim.bo[bufnr].filetype
    h_info(
      string.format(
        "current buffer: %s (filetype '%s')",
        bufname ~= '' and vim.fn.fnamemodify(bufname, ':~') or '(unnamed)',
        filetype
      )
    )
    if #filetypes > 0 and not vim.tbl_contains(filetypes, filetype) then
      h_warn(
        string.format(
          "filetype '%s' is not in filetypes — the source is not offered in this buffer; "
            .. 'the list below is what it would use',
          filetype
        ),
        { 'add the filetype to filetypes to enable completion here' }
      )
    end

    local sources = scan.resolve_bib_sources(bufnr, opts)
    if #sources == 0 then
      h_info('no bibliographies resolve for this buffer')
    end

    -- Read off the resolution above rather than resolved a second time, which
    -- would call a function-valued option again.
    local global_set = scan.global_set_from_sources(sources)
    local global_lines, local_lines, unusable = {}, {}, {}
    for _, source in ipairs(sources) do
      local origins = describe_origins(source, buffer_dir, bufname)
      local shown = vim.fn.fnamemodify(source.path, ':~')
      if not source.exists then
        unusable[#unusable + 1] = describe_absence(source, opts, buffer_dir, bufname, shown)
      elseif source.is_dir then
        unusable[#unusable + 1] = {
          level = 'warn',
          message = string.format('skipped: %s (%s) — is a directory', shown, origins),
          advice = { 'point the option at a bibliography file rather than a directory' },
        }
      -- Looked up rather than classified: the set is keyed by the paths of
      -- these very sources, so resolving one again would only cost a system
      -- call to arrive at the key it already is.
      elseif global_set[source.path] then
        global_lines[#global_lines + 1] = string.format('global: %s (%s)', shown, origins)
      else
        local_lines[#local_lines + 1] = string.format('local: %s (%s)', shown, origins)
      end
    end

    for _, message in ipairs(global_lines) do
      h_ok(message)
    end
    for _, message in ipairs(local_lines) do
      h_ok(message)
    end
    for _, entry in ipairs(unusable) do
      if entry.level == 'info' then
        h_info(entry.message)
      else
        h_warn(entry.message, entry.advice)
      end
    end

    h_info('provider-level opts (sources.providers.bibtex.opts) are not visible to this report')
  end

  -- A discovery hook is user code and may raise; the rest of the report is
  -- worth more than the section that could not be built.
  local resolved_ok, resolution_error = pcall(report_bibliographies)
  if not resolved_ok then
    h_warn(
      string.format('the bibliographies could not be resolved: %s', tostring(resolution_error)),
      { 'check the discovery hooks and the path options in the configuration' }
    )
  end

  --- Report one configurable chain, filetype by filetype
  --- @param section string The section heading
  --- @param configured table The chains as configured
  --- @param chain_for fun(filetype: string|nil): table[] Builds the chain
  --- @param shipped table The chains the plugin ships
  --- @param empty_message string Reported when nothing at all is configured
  --- @param consequence string What a dormant filetype key means for the user
  local function report_section(section, configured, chain_for, shipped, empty_message, consequence)
    h_start('blink-cmp-bibtex: ' .. section)

    if type(configured) ~= 'table' or vim.tbl_isempty(configured) then
      h_warn(empty_message)
      return
    end

    h_info('shared ({"*"}): ' .. describe_chain(chain_for(nil)))

    local names = {}
    for name in pairs(configured) do
      if name ~= '*' then
        names[#names + 1] = name
      end
    end
    table.sort(names)

    for _, filetype in ipairs(names) do
      local chain = describe_chain(chain_for(filetype))
      if #filetypes == 0 or vim.tbl_contains(filetypes, filetype) then
        h_ok(string.format('%s: %s', filetype, chain))
      elseif shipped[filetype] ~= nil then
        -- Shipped with the plugin and dormant by design; not a misconfiguration.
        h_info(string.format("%s: %s (dormant, '%s' is not in filetypes)", filetype, chain, filetype))
      else
        h_warn(
          string.format(
            "%s for '%s' are configured but '%s' is not in filetypes — %s",
            section,
            filetype,
            filetype,
            consequence
          ),
          { string.format("add '%s' to the filetypes option to enable it", filetype) }
        )
      end
    end
  end

  local defaults = config.defaults()

  report_section(
    'matchers',
    type(opts.matchers) == 'table' and opts.matchers or {},
    function(filetype)
      return matchers.chain(filetype, opts)
    end,
    defaults.matchers or {},
    'no matchers are configured — no completions will ever be offered',
    'completions will not fire there'
  )

  -- Absent means the shipped hooks are in force; false, or anything else that
  -- is not a table, means discovery is off.
  local discovery_configured = opts.discovery
  if discovery_configured == nil or discovery_configured == true then
    discovery_configured = defaults.discovery or {}
  elseif type(discovery_configured) ~= 'table' then
    discovery_configured = {}
  end

  report_section(
    'discovery',
    discovery_configured,
    function(filetype)
      return discovery.chain(filetype, opts)
    end,
    defaults.discovery or {},
    'buffer discovery is disabled — only files, global_files and search_paths will be used',
    'bibliographies will not be discovered there'
  )
end

return M
