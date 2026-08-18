--- BibTeX file scanner module
--- Discovers and resolves BibTeX file paths from buffers and configuration
--- @module 'blink-cmp-bibtex.scan'

local discovery = require('blink-cmp-bibtex.discovery')
local path_util = require('blink-cmp-bibtex.path')

local M = {}

--- Resolve an option value (may be a function or static value)
--- @param value any The option value to resolve
--- @param ... any Additional arguments to pass if value is a function
--- @return any The resolved value
local function resolve_option(value, ...)
  if type(value) == 'function' then
    local ok, result = pcall(value, ...)
    if ok then
      return result
    end
    return {}
  end
  return value
end

--- Check if a value is a list-like table
--- @param value any The value to check
--- @return boolean True if the value is a list
local function is_list(value)
  if value == nil then
    return false
  end
  if vim.islist then
    return vim.islist(value)
  end
  -- Fallback for older Neovim versions
  if type(value) ~= 'table' then
    return false
  end
  local count = 0
  for _ in pairs(value) do
    count = count + 1
  end
  return count == #value
end

--- Normalize a value to a list format
--- @param value any The value to normalize
--- @return table A list-like table
local function normalize_list(value)
  if value == nil then
    return {}
  end
  if is_list(value) then
    return value
  end
  return { value }
end

--- Resolve a path option to a list of paths
--- Accepts a list, a bare string, or a function returning either; a function
--- that raises is treated as configuring nothing.
--- @param value any The option value
--- @param ... any Arguments passed to value when it is a function
--- @return table A list-like table of paths
function M.resolve_option_list(value, ...)
  return normalize_list(resolve_option(value, ...))
end

local function expand_search_path(path, root)
  local resolved = {}
  if not path_util.is_absolute(path) then
    path = vim.fs.normalize(table.concat({ root, path }, '/'))
  end
  if path:find('[%*%?%[]') then
    local matches = vim.fn.glob(path, false, true)
    for _, match in ipairs(matches) do
      resolved[#resolved + 1] = vim.fs.normalize(match)
    end
  else
    resolved[#resolved + 1] = vim.fs.normalize(path)
  end
  return resolved
end

--- Find BibTeX files referenced in a buffer, with where each was declared
--- Runs the discovery hooks configured for the buffer's filetype; see
--- discovery.lua for the hooks shipped with the plugin.
--- @param bufnr number Buffer number
--- @param opts table|nil Configuration options; the shipped hooks are used when omitted
--- @return BibtexDiscoveryEntry[] Reported bibliographies, in chain order
function M.find_bib_files_from_buffer_detailed(bufnr, opts)
  opts = opts or {}
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return {}
  end
  local ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
  if not ok or not lines then
    return {}
  end

  -- Get buffer directory for resolving imports
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local buffer_dir = nil
  if bufname and bufname ~= '' then
    buffer_dir = vim.fs.dirname(bufname)
  end

  return discovery.collect_detailed({
    bufnr = bufnr,
    filetype = vim.bo[bufnr].filetype,
    lines = lines,
    bufname = bufname,
    dir = buffer_dir,
    root = path_util.find_root(bufname, opts.root_markers or {}),
    opts = opts,
  })
end

--- Find BibTeX files referenced in a buffer
--- The names find_bib_files_from_buffer_detailed reports, in the same order.
--- @param bufnr number Buffer number
--- @param opts table|nil Configuration options; the shipped hooks are used when omitted
--- @return string[] List of bibliography file names (not full paths)
function M.find_bib_files_from_buffer(bufnr, opts)
  local names = {}
  for _, entry in ipairs(M.find_bib_files_from_buffer_detailed(bufnr, opts)) do
    names[#names + 1] = entry.name
  end
  return names
end

--- Where one bibliography came from
--- The kind names the option or the mechanism that reported it, and the detail
--- is what it was reported as: the raw option value, the glob pattern it was
--- expanded from, or the name declared in the buffer. Only a buffer origin
--- carries the hook that found it and the position of the declaration.
--- @class BibtexBibOrigin
--- @field kind 'buffer'|'files'|'global_files'|'search_paths'|'local_bib' What reported it
--- @field detail string The value it was reported as
--- @field hook string|nil The discovery hook that found it
--- @field file string|nil The declaring file, when it is not the buffer itself
--- @field line integer|nil The line the declaration was found on, 1-based

--- One bibliography path, with everything that asked for it
--- @class BibtexBibSource
--- @field path string The normalized absolute path
--- @field exists boolean Whether anything is at that path
--- @field is_dir boolean Whether what is there is a directory
--- @field origins BibtexBibOrigin[] Everything that reported this path, in order

--- Resolve every bibliography a buffer asks for, with where each came from
--- Same order and deduplication as resolve_bib_paths, except that nothing is
--- dropped: a path reported twice keeps both origins, and a path with nothing
--- behind it is reported with exists = false rather than skipped, which is what
--- lets the health check explain a bibliography that never loads.
--- @param bufnr number Buffer number
--- @param opts table|nil Configuration options
--- @return BibtexBibSource[] The bibliographies, in resolution order
function M.resolve_bib_sources(bufnr, opts)
  opts = opts or {}
  local manual_files = M.resolve_option_list(opts.files, bufnr)
  local global_files = M.resolve_option_list(opts.global_files, bufnr)
  local search_paths = M.resolve_option_list(opts.search_paths, bufnr)
  local buffer_files = M.find_bib_files_from_buffer_detailed(bufnr, opts)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local root = path_util.find_root(bufname, opts.root_markers or {})
  local buffer_dir = nil
  -- Only try to get dirname if bufname is a valid file path (not empty, not just '.')
  if bufname and bufname ~= '' and bufname ~= '.' then
    buffer_dir = vim.fs.dirname(bufname)
  end
  if not buffer_dir or buffer_dir == '' then
    local uv = vim.uv or vim.loop
    buffer_dir = uv.cwd() or ''
  end
  --- @type table<string, BibtexBibSource>
  local index = {}
  --- @type BibtexBibSource[]
  local resolved = {}

  --- Record one reported path, statting it the first time it is seen
  --- @param path string|nil The path as reported
  --- @param base_dir string|nil What a relative path is resolved against
  --- @param origin BibtexBibOrigin Where the path came from
  local function add_path(path, base_dir, origin)
    if not path or path == '' then
      return
    end
    local expanded
    if path_util.is_absolute(path) then
      expanded = path_util.normalize(path)
    else
      local anchor = base_dir or root or buffer_dir
      expanded = path_util.normalize(path_util.joinpath(anchor, path))
    end
    if not expanded then
      return
    end
    local source = index[expanded]
    if not source then
      local uv = vim.uv or vim.loop
      local stat = uv.fs_stat(expanded)
      source = {
        path = expanded,
        exists = stat ~= nil,
        is_dir = stat ~= nil and stat.type == 'directory',
        origins = {},
      }
      index[expanded] = source
      resolved[#resolved + 1] = source
    end
    source.origins[#source.origins + 1] = origin
  end

  for _, entry in ipairs(buffer_files) do
    add_path(entry.name, buffer_dir, {
      kind = 'buffer',
      detail = entry.name,
      hook = entry.hook,
      file = entry.file,
      line = entry.line,
    })
  end
  for _, path in ipairs(manual_files) do
    add_path(path, nil, { kind = 'files', detail = path })
  end
  for _, path in ipairs(global_files) do
    add_path(path, nil, { kind = 'global_files', detail = path })
  end
  for _, path in ipairs(search_paths) do
    for _, expanded in ipairs(expand_search_path(path, root)) do
      -- The pattern rather than what it expanded to, since that is what the
      -- user wrote and what they would have to change.
      add_path(expanded, nil, { kind = 'search_paths', detail = path })
    end
  end

  -- Auto-include local_bib.target if configured
  if opts.local_bib and opts.local_bib.target then
    add_path(opts.local_bib.target, root, { kind = 'local_bib', detail = opts.local_bib.target })
  end

  return resolved
end

--- Resolve all BibTeX file paths for a buffer
--- Combines buffer-discovered files, manual files, and search paths; the paths
--- resolve_bib_sources found that can actually be read.
--- @param bufnr number Buffer number
--- @param opts table Configuration options
--- @return string[] List of resolved absolute file paths
function M.resolve_bib_paths(bufnr, opts)
  local paths = {}
  for _, source in ipairs(M.resolve_bib_sources(bufnr, opts)) do
    if source.exists and not source.is_dir then
      paths[#paths + 1] = source.path
    end
  end
  return paths
end

--- Build the set of normalized global bibliography paths
--- global_files takes the same forms as any other path option, so it is
--- resolved and normalized the same way the scanner resolves it. Callers that
--- need to classify several paths build the set once and reuse it.
--- @param opts table|nil Configuration options
--- @param bufnr number|nil Buffer the option is resolved for
--- @return table<string, boolean> The normalized global paths
function M.global_set(opts, bufnr)
  local set = {}
  for _, path in ipairs(M.resolve_option_list(opts and opts.global_files, bufnr)) do
    local normalized = path_util.normalize(path)
    if normalized then
      set[normalized] = true
    end
  end
  return set
end

--- Check whether a path is one of the configured global bibliographies
--- @param path string|nil The path to classify
--- @param set table<string, boolean>|nil A set built by global_set
--- @return boolean True when the path is a global bibliography
function M.is_global_path(path, set)
  if not path or not set then
    return false
  end
  local normalized = path_util.normalize(path)
  return normalized ~= nil and set[normalized] == true
end

return M
