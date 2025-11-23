--- BibTeX file scanner module
--- Discovers and resolves BibTeX file paths from buffers and configuration
--- @module blink-cmp-bibtex.scan

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

--- BibTeX bibliography command names to recognize
--- @type table<string, boolean>
local bibliography_commands = {
  addbibresource = true,
  ['addbibresource*'] = true,
  addglobalbib = true,
  addsectionbib = true,
  bibliography = true,
  nobibliography = true,
}

--- Trim whitespace from a string
--- @param value string The string to trim
--- @return string The trimmed string
local function trim(value)
  return value:match('^%s*(.-)%s*$') or ''
end

--- Split a comma-separated resource string into individual entries
--- @param value string The resource string to split
--- @return string[] List of resource names
local function split_resources(value)
  local entries = {}
  for part in value:gmatch('[^,]+') do
    local cleaned = trim(part)
    if cleaned ~= '' then
      entries[#entries + 1] = cleaned
    end
  end
  if #entries == 0 and value ~= '' then
    entries[1] = trim(value)
  end
  return entries
end

--- Skip whitespace in a string starting from a given index
--- @param str string The input string
--- @param idx number Starting index
--- @return number The next non-whitespace index
local function skip_whitespace(str, idx)
  while idx <= #str and str:sub(idx, idx):match('%s') do
    idx = idx + 1
  end
  return idx
end

--- Read a balanced block (e.g., braces) from a string
--- @param str string The input string
--- @param idx number Starting index
--- @return string|nil, number The extracted block and next index
local function read_balanced_block(str, idx)
  if str:sub(idx, idx) ~= '{' then
    return nil, idx
  end
  local depth = 1
  local cursor = idx + 1
  while cursor <= #str and depth > 0 do
    local ch = str:sub(cursor, cursor)
    if ch == '{' then
      depth = depth + 1
    elseif ch == '}' then
      depth = depth - 1
      if depth == 0 then
        return str:sub(idx + 1, cursor - 1), cursor + 1
      end
    elseif ch == '\\' and cursor < #str then
      cursor = cursor + 1
    end
    cursor = cursor + 1
  end
  return nil, idx
end

--- Skip optional arguments in a LaTeX command
--- @param str string The input string
--- @param idx number Starting index
--- @return number The index after all optional arguments
local function skip_optional_arguments(str, idx)
  local cursor = skip_whitespace(str, idx)
  while str:sub(cursor, cursor) == '[' do
    local depth = 1
    cursor = cursor + 1
    while cursor <= #str and depth > 0 do
      local ch = str:sub(cursor, cursor)
      if ch == '[' then
        depth = depth + 1
      elseif ch == ']' then
        depth = depth - 1
      end
      cursor = cursor + 1
    end
    cursor = skip_whitespace(str, cursor)
  end
  return cursor
end

--- Extract bibliography file paths from a LaTeX command line
--- @param line string The line to parse
--- @return string[] List of extracted file paths
local function extract_command_paths(line)
  local results = {}
  local i = 1
  while i <= #line do
    local start_pos, end_pos, command = line:find('\\([%a%@]+%*?)', i)
    if not start_pos then
      break
    end
    i = end_pos + 1
    if not bibliography_commands[command] then
      goto continue
    end
    local cursor = skip_optional_arguments(line, i)
    cursor = skip_whitespace(line, cursor)
    local value
    value, i = read_balanced_block(line, cursor)
    if value and #value > 0 then
      local resources = split_resources(value)
      for _, resource in ipairs(resources) do
        results[#results + 1] = resource
      end
    end
    ::continue::
  end
  return results
end

--- Find bibliography files in YAML front matter
--- @param lines string[] Buffer lines to search
--- @return string[] List of bibliography file paths
local function find_yaml_bibliography(lines)
  local resources = {}
  local in_front_matter = false
  local collecting_list = false
  for idx, line in ipairs(lines) do
    if idx == 1 and line:match('^%-%-%-%s*$') then
      in_front_matter = true
    elseif in_front_matter and line:match('^%-%-%-%s*$') then
      break
    elseif in_front_matter then
      local inline = line:match('^bibliography:%s*(.+)$')
      if inline then
        resources[#resources + 1] = trim(inline)
        collecting_list = false
      elseif line:match('^bibliography:%s*$') then
        collecting_list = true
      elseif line:match('^%S') and not line:match('^%s') then
        collecting_list = false
      end
      if collecting_list then
        local list_item = line:match('^%s*%-%s*(.+)%s*$')
        if list_item then
          resources[#resources + 1] = trim(list_item)
        end
      end
    end
  end
  return resources
end

--- Find Typst import statements
--- @param lines string[] Buffer lines to search
--- @return string[] List of imported file paths
local function find_typst_imports(lines)
  local imports = {}
  for _, line in ipairs(lines) do
    -- Match #import patterns with double quotes:
    -- #import "file.typ"
    -- #import "file.typ": item
    -- #import "file.typ": *
    -- Capture the path within double quotes
    for path in line:gmatch('#import%s+"([^"]+)"') do
      if path:match('%.typ$') then
        imports[#imports + 1] = trim(path)
      end
    end
    -- Match #import patterns with single quotes:
    -- #import 'file.typ'
    -- #import 'file.typ': item
    -- #import 'file.typ': *
    -- Capture the path within single quotes
    for path in line:gmatch("#import%s+'([^']+)'") do
      if path:match('%.typ$') then
        imports[#imports + 1] = trim(path)
      end
    end
  end
  return imports
end

--- Read lines from a file
--- @param filepath string The file path to read
--- @return string[]|nil List of lines or nil if file cannot be read
local function read_file_lines(filepath)
  local fd, err = io.open(filepath, 'r')
  if not fd then
    -- Silently return nil for missing imports - this is expected in many cases
    -- as users may import files that don't exist yet or are in different locations
    return nil
  end
  local lines = {}
  for line in fd:lines() do
    lines[#lines + 1] = line
  end
  fd:close()
  return lines
end

--- Platform-specific path separator
--- @type string
local path_separator = package.config:sub(1, 1)

--- Join two path components
--- @param base string|nil Base path
--- @param relative string|nil Relative path
--- @return string|nil The joined path
local function joinpath(base, relative)
  if base == nil or base == '' then
    return relative
  end
  if relative == nil or relative == '' then
    return base
  end
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(base, relative)
  end
  if base:sub(-1) == path_separator then
    return base .. relative
  end
  return base .. path_separator .. relative
end

--- Normalize a path, expanding home directory and resolving relative paths
--- @param path string The path to normalize
--- @return string|nil The normalized path or nil if invalid
local function normalize_path(path)
  if not path or path == '' then
    return nil
  end
  local uv = vim.uv or vim.loop
  local home = uv.os_homedir()
  if home then
    path = path:gsub('^~', home)
  end
  path = vim.fn.expand(path)
  path = vim.fs.normalize(path)
  return path
end

--- Check if a path is absolute
--- @param path string The path to check
--- @return boolean True if the path is absolute
local function is_absolute(path)
  return path:match('^%a:[\\/]') or path:sub(1, 1) == '/'
end

--- Find bibliography files in Typst #bibliography() declarations
--- Recursively follows #import statements to find bibliographies in imported files
--- @param lines string[] Buffer lines to search
--- @param base_dir string|nil Directory to resolve relative imports from
--- @param visited table<string, boolean>|nil Table to track visited files (prevents cycles)
--- @return string[] List of bibliography file paths
local function find_typst_bibliography(lines, base_dir, visited)
  visited = visited or {}
  local resources = {}
  
  -- Find direct bibliography declarations
  for _, line in ipairs(lines) do
    -- Match #bibliography("path/to/file.bib") with double quotes
    for path in line:gmatch('#bibliography%s*%(%s*"([^"]+)"%s*%)') do
      resources[#resources + 1] = trim(path)
    end
    -- Match #bibliography('path/to/file.bib') with single quotes
    for path in line:gmatch("#bibliography%s*%(%s*'([^']+)'%s*%)") do
      resources[#resources + 1] = trim(path)
    end
  end
  
  -- Follow imports to find bibliographies in imported files
  if base_dir then
    local imports = find_typst_imports(lines)
    for _, import_path in ipairs(imports) do
      local full_path
      if is_absolute(import_path) then
        full_path = normalize_path(import_path)
      else
        full_path = normalize_path(joinpath(base_dir, import_path))
      end
      
      if full_path and not visited[full_path] then
        visited[full_path] = true
        local import_lines = read_file_lines(full_path)
        if import_lines then
          local import_dir = vim.fs.dirname(full_path)
          local imported_resources = find_typst_bibliography(import_lines, import_dir, visited)
          for _, resource in ipairs(imported_resources) do
            -- Resolve imported resource paths relative to the imported file's directory
            if not is_absolute(resource) then
              resource = joinpath(import_dir, resource)
            end
            resources[#resources + 1] = resource
          end
        end
      end
    end
  end
  
  return resources
end

--- Find the project root directory based on markers
--- @param bufname string Buffer file name
--- @param markers table List of root marker files/directories
--- @return string The root directory path
local function find_root(bufname, markers)
  local uv = vim.uv or vim.loop
  local dir = bufname ~= '' and vim.fs.dirname(bufname) or (uv.cwd() or '')
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
  if not is_absolute(path) then
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

--- Ensure a path has a bibliography extension (.bib, .yml, or .yaml)
--- @param path string|nil The path to check
--- @return string|nil The path with .bib extension if needed (unless it already has .yml or .yaml)
local function ensure_bib_extension(path)
  if not path or path == '' then
    return path
  end
  if path:find('[%*%?%[]') then
    return path
  end
  -- Accept .bib, .yml, .yaml extensions as-is
  if path:match('%.bib$') or path:match('%.ya?ml$') then
    return path
  end
  local filename = path:match('([^/\\]+)$') or path
  if filename:find('%.') then
    return path
  end
  return path .. '.bib'
end

--- Find BibTeX files referenced in a buffer
--- @param bufnr number Buffer number
--- @return string[] List of bibliography file names (not full paths)
function M.find_bib_files_from_buffer(bufnr)
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
  
  local resources = {}
  for _, line in ipairs(lines) do
    for _, resource in ipairs(extract_command_paths(line)) do
      resources[#resources + 1] = ensure_bib_extension(resource)
    end
  end
  local yaml_resources = find_yaml_bibliography(lines)
  for _, resource in ipairs(yaml_resources) do
    resources[#resources + 1] = ensure_bib_extension(resource)
  end
  local typst_resources = find_typst_bibliography(lines, buffer_dir)
  for _, resource in ipairs(typst_resources) do
    resources[#resources + 1] = ensure_bib_extension(resource)
  end
  return resources
end

--- Resolve all BibTeX file paths for a buffer
--- Combines buffer-discovered files, manual files, and search paths
--- @param bufnr number Buffer number
--- @param opts table Configuration options
--- @return string[] List of resolved absolute file paths
function M.resolve_bib_paths(bufnr, opts)
  opts = opts or {}
  local manual_files = normalize_list(resolve_option(opts.files, bufnr))
  local search_paths = normalize_list(resolve_option(opts.search_paths, bufnr))
  local buffer_files = M.find_bib_files_from_buffer(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local root = find_root(bufname, opts.root_markers or {})
  local buffer_dir = nil
  if bufname and bufname ~= '' then
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
    if is_absolute(path) then
      expanded = normalize_path(path)
    else
      local anchor = base_dir or root or buffer_dir
      expanded = normalize_path(joinpath(anchor, path))
    end
    if expanded and not dedup[expanded] then
      dedup[expanded] = true
      resolved[#resolved + 1] = expanded
    end
  end
  for _, path in ipairs(buffer_files) do
    add_path(path, buffer_dir)
  end
  for _, path in ipairs(manual_files) do
    add_path(path)
  end
  for _, path in ipairs(search_paths) do
    for _, expanded in ipairs(expand_search_path(path, root)) do
      add_path(expanded)
    end
  end
  return resolved
end

return M
