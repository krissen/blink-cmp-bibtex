local log = require('blink-bibtex.log')

local M = {}

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

local function is_list(value)
  if value == nil then
    return false
  end
  if vim.islist then
    return vim.islist(value)
  end
  return vim.tbl_islist(value)
end

local function normalize_list(value)
  if value == nil then
    return {}
  end
  if is_list(value) then
    return value
  end
  return { value }
end

local bibliography_commands = {
  addbibresource = true,
  ['addbibresource*'] = true,
  addglobalbib = true,
  addsectionbib = true,
  bibliography = true,
  nobibliography = true,
}

local function trim(value)
  return (value:gsub('^%s+', ''):gsub('%s+$', ''))
end

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

local function skip_whitespace(str, idx)
  while idx <= #str and str:sub(idx, idx):match('%s') do
    idx = idx + 1
  end
  return idx
end

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
    elseif ch == '\\' then
      cursor = cursor + 1
    end
    cursor = cursor + 1
  end
  return nil, idx
end

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

local function find_yaml_bibliography(lines)
  local resources = {}
  local in_front_matter = false
  for idx, line in ipairs(lines) do
    if idx == 1 and line:match('^%-%-%-%s*$') then
      in_front_matter = true
    elseif in_front_matter and line:match('^%-%-%-%s*$') then
      break
    elseif in_front_matter then
      local single = line:match('^bibliography:%s*(.+)$')
      if single then
        resources[#resources + 1] = single
      end
      local list_item = line:match('^%s*%-%s*(.+%.bib)%s*$')
      if list_item then
        resources[#resources + 1] = list_item
      end
    end
  end
  return resources
end

local function normalize_path(path)
  if not path or path == '' then
    return nil
  end
  local home = vim.loop.os_homedir()
  if home then
    path = path:gsub('^~', home)
  end
  path = vim.fn.expand(path)
  path = vim.fs.normalize(path)
  return path
end

local function is_absolute(path)
  return path:match('^%a:[\\/]') or path:sub(1, 1) == '/'
end

local function find_root(bufname, markers)
  local dir = bufname ~= '' and vim.fs.dirname(bufname) or vim.loop.cwd()
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

local function ensure_bib_extension(path)
  if not path or path == '' then
    return path
  end
  if path:find('[%*%?%[]') then
    return path
  end
  if path:match('%.bib$') then
    return path
  end
  local filename = path:match('([^/\\]+)$') or path
  if filename:find('%.') then
    return path
  end
  return path .. '.bib'
end

function M.find_bib_files_from_buffer(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
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
  log.debug('buffer-declared bibliography resources', { buffer = bufnr, resources = resources })
  return resources
end

function M.resolve_bib_paths(bufnr, opts)
  opts = opts or {}
  local manual_files = normalize_list(resolve_option(opts.files, bufnr))
  local search_paths = normalize_list(resolve_option(opts.search_paths, bufnr))
  local buffer_files = M.find_bib_files_from_buffer(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local root = find_root(bufname, opts.root_markers or {})
  local dedup = {}
  local resolved = {}
  local function add_path(path)
    if not path or path == '' then
      return
    end
    local expanded
    if is_absolute(path) then
      expanded = normalize_path(path)
    else
      expanded = normalize_path(table.concat({ root, path }, '/'))
    end
    if expanded and not dedup[expanded] then
      dedup[expanded] = true
      resolved[#resolved + 1] = expanded
    end
  end
  for _, path in ipairs(buffer_files) do
    add_path(path)
  end
  for _, path in ipairs(manual_files) do
    add_path(path)
  end
  for _, path in ipairs(search_paths) do
    for _, expanded in ipairs(expand_search_path(path, root)) do
      add_path(expanded)
    end
  end
  log.debug('resolved bibliography paths', {
    buffer = bufnr,
    resolved = resolved,
    manual = manual_files,
    search = search_paths,
    detected = buffer_files,
  })
  return resolved
end

return M
