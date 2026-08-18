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

--- Identify a path by what it points at
--- Symlinked segments give one file several spellings — on macOS a temporary
--- directory is reachable as both /var/... and /private/var/... — and a text
--- comparison reads those as different files. The same bibliography then
--- resolves twice, and one reached through a link is not recognized as the
--- global file it is. A path with nothing behind it cannot be resolved and
--- keeps the spelling it was declared with.
--- @param path string|nil A normalized path
--- @return string|nil The real path, or the path itself when it has none
local function canonical(path)
  if not path or path == '' then
    return path
  end
  local uv = vim.uv or vim.loop
  local real = uv.fs_realpath(path)
  return real and vim.fs.normalize(real) or path
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
--- @param bufnr number|nil Buffer number; an invalid one discovers nothing
--- @param opts table|nil Configuration options; the shipped hooks are used when omitted
--- @param root string|nil The project root, found from opts.root_markers when
---   omitted; passed in by a caller that has already found it, so that finding
---   it does not cost a second walk up the directory tree
--- @return BibtexDiscoveryEntry[] Reported bibliographies, in chain order
function M.find_bib_files_from_buffer_detailed(bufnr, opts, root)
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
    root = root or path_util.find_root(bufname, opts.root_markers or {}),
    opts = opts,
  })
end

--- Find BibTeX files referenced in a buffer
--- The names find_bib_files_from_buffer_detailed reports, in the same order.
--- @param bufnr number|nil Buffer number; an invalid one discovers nothing
--- @param opts table|nil Configuration options; the shipped hooks are used when omitted
--- @return string[] List of bibliography file names (not full paths)
function M.find_bib_files_from_buffer(bufnr, opts)
  local names = {}
  for _, entry in ipairs(M.find_bib_files_from_buffer_detailed(bufnr, opts)) do
    names[#names + 1] = entry.name
  end
  return names
end

--- The path options of a configuration, resolved to lists
--- @class BibtexResolvedOptions
--- @field files string[] The files option
--- @field global_files string[] The global_files option
--- @field search_paths string[] The search_paths option

--- Resolve the path options once
--- Any of them may be a function, which a caller that both counts them and
--- resolves them would otherwise run twice: an expensive one would run twice
--- per call, and one that answers differently the second time would leave the
--- count disagreeing with the list it describes.
--- @param opts table|nil Configuration options
--- @param bufnr number|nil Buffer the options are resolved for
--- @return BibtexResolvedOptions The resolved lists
function M.resolve_options(opts, bufnr)
  opts = opts or {}
  return {
    files = M.resolve_option_list(opts.files, bufnr),
    global_files = M.resolve_option_list(opts.global_files, bufnr),
    search_paths = M.resolve_option_list(opts.search_paths, bufnr),
  }
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
--- lets the health check explain a bibliography that never loads. Paths are
--- identified by what they point at, so two spellings of one file are one
--- source with two origins.
--- @param bufnr number|nil Buffer number; without a valid one only the path
---   options are resolved, anchored at the working directory
--- @param opts table|nil Configuration options
--- @param resolved BibtexResolvedOptions|nil The path options already resolved,
---   from resolve_options; passed in by a caller that has read them for
---   something else, so that a function-valued option runs once
--- @return BibtexBibSource[] The bibliographies, in resolution order
function M.resolve_bib_sources(bufnr, opts, resolved)
  opts = opts or {}
  resolved = resolved or M.resolve_options(opts, bufnr)
  local manual_files = resolved.files
  local global_files = resolved.global_files
  local search_paths = resolved.search_paths
  -- Read before the buffer is scanned, so that the root is found once and
  -- handed to the hooks rather than found again for them.
  local bufname = ''
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    bufname = vim.api.nvim_buf_get_name(bufnr)
  end
  local root = path_util.find_root(bufname, opts.root_markers or {})
  local buffer_files = M.find_bib_files_from_buffer_detailed(bufnr, opts, root)
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
  local sources = {}

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
    expanded = canonical(expanded)
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
      sources[#sources + 1] = source
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

  return sources
end

--- The sources that can actually be read, as plain paths
--- @param sources BibtexBibSource[] What resolve_bib_sources returned
--- @return string[] The paths that exist and are not directories, in order
function M.paths_from_sources(sources)
  local paths = {}
  for _, source in ipairs(sources or {}) do
    if source.exists and not source.is_dir then
      paths[#paths + 1] = source.path
    end
  end
  return paths
end

--- Resolve all BibTeX file paths for a buffer
--- Combines buffer-discovered files, manual files, and search paths; the paths
--- resolve_bib_sources found that can actually be read. A caller that also
--- needs the origins resolves the sources once and reads them with
--- paths_from_sources.
--- @param bufnr number Buffer number
--- @param opts table Configuration options
--- @return string[] List of resolved absolute file paths
function M.resolve_bib_paths(bufnr, opts)
  return M.paths_from_sources(M.resolve_bib_sources(bufnr, opts))
end

--- Build the set of global bibliographies from resolved sources
--- Reads the origins rather than the option, so that classification cannot
--- diverge from resolution: a global file is exactly a path that resolution
--- reached through global_files, anchored and keyed the way resolution
--- anchored and keyed it.
--- @param sources BibtexBibSource[] What resolve_bib_sources returned
--- @return table<string, boolean> The global paths, keyed as the sources are
function M.global_set_from_sources(sources)
  local set = {}
  for _, source in ipairs(sources or {}) do
    for _, origin in ipairs(source.origins) do
      if origin.kind == 'global_files' then
        set[source.path] = true
        break
      end
    end
  end
  return set
end

--- Build the set of global bibliographies for a buffer
--- A convenience over resolve_bib_sources for a caller that needs nothing
--- else; one that has already resolved the sources should read them with
--- global_set_from_sources instead of resolving them a second time, which
--- would call a function-valued option again.
--- @param opts table|nil Configuration options
--- @param bufnr number|nil Buffer the option is resolved for
--- @return table<string, boolean> The global paths
function M.global_set(opts, bufnr)
  return M.global_set_from_sources(M.resolve_bib_sources(bufnr, opts))
end

--- Check whether a path is one of the configured global bibliographies
--- Costs a system call, since the path is compared by what it points at.
--- @param path string|nil The path to classify
--- @param set table<string, boolean>|nil A set built by global_set
--- @return boolean True when the path is a global bibliography
function M.is_global_path(path, set)
  if not path or not set then
    return false
  end
  -- A path that already is a key needs no resolving: the keys are resolved
  -- paths, and every path this is asked about comes from the same resolution.
  if set[path] then
    return true
  end
  local normalized = canonical(path_util.normalize(path))
  return normalized ~= nil and set[normalized] == true
end

return M
