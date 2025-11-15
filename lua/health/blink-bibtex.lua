local config = require('blink-bibtex.config')
local scan = require('blink-bibtex.scan')
local cache = require('blink-bibtex.cache')

local health = vim.health or require('health')
local uv = vim.uv or vim.loop
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local info = health.info or health.report_info
local warn = health.warn or health.report_warn
local errorf = health.error or health.report_error

local function fmt_list(items)
  if not items or #items == 0 then
    return '(none)'
  end
  return table.concat(items, ', ')
end

local function check_filetype(bufnr, opts)
  start('Filetype & buffer state')
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    warn('Current buffer is not loaded; open the file before running :checkhealth blink-bibtex')
    return
  end
  local ft = vim.bo[bufnr].filetype or '(none)'
  info(string.format('Current buffer: %s (filetype=%s)', vim.api.nvim_buf_get_name(bufnr), ft))
  if not opts.filetypes or #opts.filetypes == 0 then
    ok('All filetypes enabled in blink-bibtex')
    return
  end
  if vim.tbl_contains(opts.filetypes, ft) then
    ok(string.format('Filetype %s is enabled for blink-bibtex', ft))
  else
    warn(string.format('Filetype %s is not enabled; update require("blink-bibtex").setup({ filetypes = { ... } })', ft))
  end
end

local function check_paths(bufnr, opts)
  start('Bibliography discovery')
  info('Manual files: ' .. fmt_list(opts.files))
  info('Search paths: ' .. fmt_list(opts.search_paths))
  local resolved = scan.resolve_bib_paths(bufnr, opts)
  if #resolved == 0 then
    warn('No .bib files resolved for this buffer. Verify \\addbibresource declarations or setup.files/search_paths.')
    return
  end
  ok(string.format('Resolved %d bibliography file(s)', #resolved))
  local total_entries = 0
  for _, path in ipairs(resolved) do
    local stat = uv.fs_stat(path)
    if not stat then
      warn(string.format('Missing file: %s (does not exist)', path))
    else
      local entries = cache.collect({ path }, nil)
      local count = #entries
      total_entries = total_entries + count
      if count == 0 then
        warn(string.format('Parsed 0 entries from %s', path))
      else
        ok(string.format('%s — %d entries available', path, count))
      end
    end
  end
  if total_entries == 0 then
    warn('No entries could be parsed from any resolved file.')
  else
    info(string.format('Total entries available across all files: %d', total_entries))
  end
end

local function check_preview(opts)
  start('Preview configuration')
  info('Preview style: ' .. (opts.preview_style or 'apa'))
  info('Max entries per request: ' .. tostring(opts.max_entries or 'unlimited'))
  if opts.debug then
    ok('Debug logging enabled')
  else
    info('Debug logging disabled (set debug = true in setup() for verbose output)')
  end
  if type(opts.log) == 'function' then
    ok('Custom log sink configured via setup({ log = function(level, message) ... end })')
  else
    info('Using vim.notify for log output')
  end
end

local M = {}

function M.check()
  local ok_status, err = pcall(function()
    local opts = config.get()
    local bufnr = vim.api.nvim_get_current_buf()
    check_filetype(bufnr, opts)
    check_paths(bufnr, opts)
    check_preview(opts)
  end)
  if not ok_status then
    errorf(string.format('blink-bibtex health check failed: %s', err))
  end
end

return M
