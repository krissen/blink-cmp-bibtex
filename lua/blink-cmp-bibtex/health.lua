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

--- The buffer the report is about
--- :checkhealth renders its output in a buffer of its own, so the buffer that
--- is current while check() runs is the report rather than the document the
--- user was editing. The alternate buffer is the one they came from; falling
--- back to a visible buffer covers a report opened without an alternate.
--- @return integer The buffer to resolve bibliographies for
local function target_buffer()
  local current = vim.api.nvim_get_current_buf()
  if vim.bo[current].filetype ~= 'checkhealth' then
    return current
  end
  local alternate = vim.fn.bufnr('#')
  if alternate > 0 and vim.api.nvim_buf_is_valid(alternate) and vim.bo[alternate].filetype ~= 'checkhealth' then
    return alternate
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype ~= 'checkhealth' then
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

--- Describe where one bibliography came from
--- @param origin BibtexBibOrigin The origin to describe
--- @param buffer_dir string|nil The directory of the buffer being reported on
--- @param bufname string The name of the buffer being reported on
--- @return string
local function describe_origin(origin, buffer_dir, bufname)
  if origin.kind == 'buffer' then
    local description = 'buffer discovery: ' .. (origin.hook or 'unknown')
    -- A hook that reads the document as one text reports no line, and there is
    -- then nothing to point at.
    if origin.line then
      local declared_in = origin.file or bufname
      if declared_in and declared_in ~= '' then
        description = string.format('%s, %s:%d', description, describe_file(declared_in, buffer_dir), origin.line)
      else
        description = string.format('%s, line %d', description, origin.line)
      end
    end
    return description
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

    local global_set = scan.global_set(opts, bufnr)
    local global_lines, local_lines, unusable = {}, {}, {}
    for _, source in ipairs(sources) do
      local origins = describe_origins(source, buffer_dir, bufname)
      local shown = vim.fn.fnamemodify(source.path, ':~')
      if not source.exists then
        unusable[#unusable + 1] = {
          message = string.format('missing: %s (%s) — declared but the file does not exist', shown, origins),
          advice = { 'fix the path or remove it from the option' },
        }
      elseif source.is_dir then
        unusable[#unusable + 1] = {
          message = string.format('skipped: %s (%s) — is a directory', shown, origins),
          advice = { 'point the option at a bibliography file rather than a directory' },
        }
      elseif scan.is_global_path(source.path, global_set) then
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
      h_warn(entry.message, entry.advice)
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
