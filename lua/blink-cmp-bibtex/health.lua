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

--- Run the health check
function M.check()
  local opts = config.get()
  local bufnr = vim.api.nvim_get_current_buf()

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

  local filetypes = opts.filetypes or {}
  if #filetypes == 0 then
    h_info('filetypes: (empty) — the source is offered in every buffer')
  else
    h_ok('filetypes: ' .. table.concat(filetypes, ', '))
  end
  h_info(string.format('preview_style: %s, max_entries: %d', opts.preview_style, opts.max_entries))
  -- files and global_files may be a list, a bare string, or a function, so they
  -- are resolved the same way the scanner resolves them before being counted.
  h_info(string.format('files: %d configured', #scan.resolve_option_list(opts.files, bufnr)))
  h_info(string.format('global_files: %d configured', #scan.resolve_option_list(opts.global_files, bufnr)))

  --- Report one configurable chain, filetype by filetype
  --- @param section string The section heading
  --- @param configured table The chains as configured
  --- @param chain_for fun(filetype: string|nil): table[] Builds the chain
  --- @param shipped table The chains the plugin ships
  --- @param empty_message string Reported when nothing at all is configured
  --- @param consequence string What a dormant filetype key means for the user
  local function report_section(section, configured, chain_for, shipped, empty_message, consequence)
    h_start('blink-cmp-bibtex: ' .. section)

    if vim.tbl_isempty(configured) then
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
    opts.matchers or {},
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
  if discovery_configured == nil then
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
