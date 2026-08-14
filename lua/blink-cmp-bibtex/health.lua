--- Health check for blink-cmp-bibtex, run with `:checkhealth blink-cmp-bibtex`
--- Reports the resolved configuration and flags matcher setups that can never fire.
--- @module 'blink-cmp-bibtex.health'

local config = require('blink-cmp-bibtex.config')
local matchers = require('blink-cmp-bibtex.matchers')

local M = {}

-- Neovim 0.9 exposes the older report_* names.
local health = vim.health
local h_start = health.start or health.report_start
local h_ok = health.ok or health.report_ok
local h_warn = health.warn or health.report_warn
local h_info = health.info or health.report_info

--- Describe a matcher chain as a readable string
--- @param chain BibtexMatcherSpec[]
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

  h_start('blink-cmp-bibtex')

  local filetypes = opts.filetypes or {}
  if #filetypes == 0 then
    h_info('filetypes: (empty) — the source is offered in every buffer')
  else
    h_ok('filetypes: ' .. table.concat(filetypes, ', '))
  end
  h_info(string.format('preview_style: %s, max_entries: %d', opts.preview_style, opts.max_entries))
  h_info(string.format('files: %d configured', #(opts.files or {})))
  h_info(string.format('global_files: %d configured', #(opts.global_files or {})))

  h_start('blink-cmp-bibtex: matchers')

  local configured = opts.matchers or {}
  if vim.tbl_isempty(configured) then
    h_warn('no matchers are configured — no completions will ever be offered')
    return
  end

  h_info('shared ({"*"}): ' .. describe_chain(matchers.chain(nil, opts)))

  local names = {}
  for name in pairs(configured) do
    if name ~= '*' then
      names[#names + 1] = name
    end
  end
  table.sort(names)

  local shipped = config.defaults().matchers or {}

  for _, filetype in ipairs(names) do
    local chain = describe_chain(matchers.chain(filetype, opts))
    if #filetypes == 0 or vim.tbl_contains(filetypes, filetype) then
      h_ok(string.format('%s: %s', filetype, chain))
    elseif shipped[filetype] ~= nil then
      -- Shipped with the plugin and dormant by design; not a misconfiguration.
      h_info(string.format("%s: %s (dormant, '%s' is not in filetypes)", filetype, chain, filetype))
    else
      h_warn(
        string.format(
          "matchers for '%s' are configured but '%s' is not in filetypes — completions will not fire there",
          filetype,
          filetype
        ),
        { string.format("add '%s' to the filetypes option to enable it", filetype) }
      )
    end
  end
end

return M
