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

local function normalize_list(value)
  if value == nil then
    return {}
  end
  if vim.tbl_islist(value) then
    return value
  end
  return { value }
end

local function extract_addbibresource_paths(line)
  local results = {}
  local i = 1
  while true do
    local start_pos, end_pos = line:find('\\addbibresource', i, true)
    if not start_pos then
      break
    end
    i = end_pos + 1
    local cursor = end_pos + 1
    while cursor <= #line and line:sub(cursor, cursor):match('%s') do
      cursor = cursor + 1
    end
    if line:sub(cursor, cursor) == '[' then
      local depth = 1
      cursor = cursor + 1
      while cursor <= #line and depth > 0 do
        local ch = line:sub(cursor, cursor)
        if ch == '[' then
          depth = depth + 1
        elseif ch == ']' then
          depth = depth - 1
        end
        cursor = cursor + 1
      end
    end
    while cursor <= #line and line:sub(cursor, cursor):match('%s') do
      cursor = cursor + 1
    end
    if line:sub(cursor, cursor) ~= '{' then
      goto continue
    end
    local open = cursor
    local depth = 1
    cursor = cursor + 1
    local closing
    while cursor <= #line and depth > 0 do
      local ch = line:sub(cursor, cursor)
      if ch == '{' then
        depth = depth + 1
      elseif ch == '}' then
        depth = depth - 1
        if depth == 0 then
          closing = cursor
          cursor = cursor + 1
          break
        end
      end
      cursor = cursor + 1
    end
    if closing then
      local value = line:sub(open + 1, closing - 1)
      if value and #value > 0 then
        results[#results + 1] = value
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

function M.find_bib_files_from_buffer(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local resources = {}
  for _, line in ipairs(lines) do
    for _, resource in ipairs(extract_addbibresource_paths(line)) do
      resources[#resources + 1] = resource
    end
  end
  local yaml_resources = find_yaml_bibliography(lines)
  vim.list_extend(resources, yaml_resources)
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
  return resolved
end

return M
