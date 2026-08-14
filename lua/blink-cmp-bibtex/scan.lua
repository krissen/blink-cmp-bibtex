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

--- Find the project root directory based on markers
--- @param bufname string Buffer file name
--- @param markers table List of root marker files/directories
--- @return string The root directory path
local function find_root(bufname, markers)
  local uv = vim.uv or vim.loop
  -- Ensure bufname is not just a directory marker like '.' or empty
  local dir
  if not bufname or bufname == '' or bufname == '.' then
    dir = uv.cwd() or ''
  else
    dir = vim.fs.dirname(bufname)
  end
  if markers and #markers > 0 then
    local found = vim.fs.find(markers, { upward = true, path = dir })[1]
    if found then
      return vim.fs.dirname(found)
    end
  end
  return dir
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

--- Find BibTeX files referenced in a buffer
--- Runs the discovery hooks configured for the buffer's filetype; see
--- discovery.lua for the hooks shipped with the plugin.
--- @param bufnr number Buffer number
--- @param opts table|nil Configuration options; the shipped hooks are used when omitted
--- @return string[] List of bibliography file names (not full paths)
function M.find_bib_files_from_buffer(bufnr, opts)
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

  return discovery.collect({
    bufnr = bufnr,
    filetype = vim.bo[bufnr].filetype,
    lines = lines,
    bufname = bufname,
    dir = buffer_dir,
    opts = opts or {},
  })
end

--- Resolve all BibTeX file paths for a buffer
--- Combines buffer-discovered files, manual files, and search paths
--- @param bufnr number Buffer number
--- @param opts table Configuration options
--- @return string[] List of resolved absolute file paths
function M.resolve_bib_paths(bufnr, opts)
  opts = opts or {}
  local manual_files = M.resolve_option_list(opts.files, bufnr)
  local global_files = M.resolve_option_list(opts.global_files, bufnr)
  local search_paths = M.resolve_option_list(opts.search_paths, bufnr)
  local buffer_files = M.find_bib_files_from_buffer(bufnr, opts)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local root = find_root(bufname, opts.root_markers or {})
  local buffer_dir = nil
  -- Only try to get dirname if bufname is a valid file path (not empty, not just '.')
  if bufname and bufname ~= '' and bufname ~= '.' then
    buffer_dir = vim.fs.dirname(bufname)
  end
  if not buffer_dir or buffer_dir == '' then
    local uv = vim.uv or vim.loop
    buffer_dir = uv.cwd() or ''
  end
  local dedup = {}
  local resolved = {}
  local function add_path(path, base_dir)
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
    if expanded and not dedup[expanded] then
      dedup[expanded] = true
      -- Verify file exists and is not a directory
      local uv = vim.uv or vim.loop
      local stat = uv.fs_stat(expanded)
      if not stat then
        return -- File doesn't exist, skip it
      end
      if stat.type == 'directory' then
        return -- Skip directories
      end
      resolved[#resolved + 1] = expanded
    end
  end
  for _, path in ipairs(buffer_files) do
    add_path(path, buffer_dir)
  end
  for _, path in ipairs(manual_files) do
    add_path(path)
  end
  for _, path in ipairs(global_files) do
    add_path(path)
  end
  for _, path in ipairs(search_paths) do
    for _, expanded in ipairs(expand_search_path(path, root)) do
      add_path(expanded)
    end
  end

  -- Auto-include local_bib.target if configured
  if opts.local_bib and opts.local_bib.target then
    add_path(opts.local_bib.target, root)
  end

  return resolved
end

return M
