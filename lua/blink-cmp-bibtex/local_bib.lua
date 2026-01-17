--- Local BibTeX file management module
--- Provides functionality to copy BibTeX entries to a local project-specific file
--- @module blink-cmp-bibtex.local_bib

local M = {}

--- Notify user with an info message
--- @param message string The message to display
local function notify_info(message)
  if not (vim and vim.notify) then
    return
  end
  vim.schedule(function()
    vim.notify(message, vim.log.levels.INFO, { title = 'blink-cmp-bibtex' })
  end)
end

--- Notify user with a warning message
--- @param message string The message to display
local function notify_warn(message)
  if not (vim and vim.notify) then
    return
  end
  vim.schedule(function()
    vim.notify(message, vim.log.levels.WARN, { title = 'blink-cmp-bibtex' })
  end)
end

--- Get the current working directory
--- @return string The current working directory
local function get_cwd()
  return vim.fn.getcwd()
end

--- Check if a file exists
--- @param path string The file path to check
--- @return boolean True if file exists
local function file_exists(path)
  local uv = vim.uv or vim.loop
  local stat = uv.fs_stat(path)
  return stat ~= nil
end

--- Make a path absolute if it's relative
--- @param path string The path to normalize
--- @param base string|nil The base directory (defaults to cwd)
--- @return string The absolute path
local function make_absolute(path, base)
  -- Check for Unix absolute path or Windows absolute path (with separator after drive)
  if path:match('^/') or path:match('^%a:[/\\]') then
    return path
  end
  base = base or get_cwd()
  if vim.fs.joinpath then
    return vim.fs.joinpath(base, path)
  end
  -- Fallback for older Neovim versions
  return base .. '/' .. path
end

--- Ensure parent directory exists for a file path
--- @param path string The file path
local function ensure_parent_dir(path)
  local dir = vim.fs.dirname(path)
  if dir and dir ~= '' then
    vim.fn.mkdir(dir, 'p')
  end
end

--- Resolve the target bib file based on configuration
--- Priority: targets[cwd] > target > pattern match
--- @param opts table The local_bib configuration
--- @param cwd string|nil The current working directory
--- @return string|nil The resolved target path, or nil if not found
function M.resolve_target(opts, cwd)
  cwd = cwd or get_cwd()

  -- Check per-directory targets first
  if opts.targets and opts.targets[cwd] then
    return make_absolute(opts.targets[cwd], cwd)
  end

  -- Check explicit target
  if opts.target then
    return make_absolute(opts.target, cwd)
  end

  -- Check pattern matches
  if opts.patterns then
    for _, pattern in ipairs(opts.patterns) do
      local path = make_absolute(pattern, cwd)
      if file_exists(path) then
        return path
      end
    end
    -- If create_if_missing is true and we have patterns, use the first pattern
    if opts.create_if_missing and #opts.patterns > 0 then
      return make_absolute(opts.patterns[1], cwd)
    end
  end

  return nil
end

--- Check if a citation key already exists in a file
--- @param path string The file path to check
--- @param key string The citation key to look for
--- @return boolean True if the key exists in the file
function M.key_exists_in_file(path, key)
  if not file_exists(path) then
    return false
  end

  local fd, err = io.open(path, 'r')
  if not fd then
    notify_warn(string.format('Cannot read %s: %s', path, err or 'unknown error'))
    return false
  end

  local content = fd:read('*a')
  fd:close()

  -- Look for @entrytype{key, pattern
  local pattern = '@%w+%s*{%s*' .. vim.pesc(key) .. '%s*,'
  return content:match(pattern) ~= nil
end

--- Create an empty bib file
--- @param path string The file path to create
--- @return boolean True if file was created successfully
function M.create_empty_file(path)
  ensure_parent_dir(path)
  local fd, err = io.open(path, 'w')
  if not fd then
    notify_warn(string.format('Cannot create %s: %s', path, err or 'unknown error'))
    return false
  end
  fd:write('% Local bibliography file\n')
  fd:close()
  return true
end

--- Determine the prefix needed before appending an entry
--- Ensures a blank line between entries
--- @param path string The file path to check
--- @return string The prefix to prepend (empty, single newline, or double newline)
local function get_append_prefix(path)
  local uv = vim.uv or vim.loop
  local stat = uv.fs_stat(path)
  if not stat or stat.size == 0 then
    return ''
  end

  -- Read last 2 bytes to check how file ends
  local fd = uv.fs_open(path, 'r', 0)
  if not fd then
    return '\n\n'
  end

  local read_size = math.min(stat.size, 2)
  local last_bytes = uv.fs_read(fd, read_size, stat.size - read_size)
  uv.fs_close(fd)

  if not last_bytes then
    return '\n\n'
  end

  -- Ensure blank line between entries
  if last_bytes:match('\n\n$') then
    return ''
  elseif last_bytes:match('\n$') then
    return '\n'
  else
    return '\n\n'
  end
end

--- Append a BibTeX entry to a file
--- @param path string The file path to append to
--- @param raw string The raw BibTeX entry text
--- @return boolean True if entry was appended successfully
function M.append_entry(path, raw)
  ensure_parent_dir(path)

  local prefix = get_append_prefix(path)

  local fd, err = io.open(path, 'a')
  if not fd then
    notify_warn(string.format('Cannot write to %s: %s', path, err or 'unknown error'))
    return false
  end

  local content = prefix .. raw
  -- Ensure entry ends with newline
  if not content:match('\n$') then
    content = content .. '\n'
  end

  fd:write(content)
  fd:close()
  return true
end

--- Copy a BibTeX entry to the local bib file
--- @param key string The citation key to copy
--- @param raw string The raw BibTeX entry text
--- @param opts table The local_bib configuration
--- @return boolean True if entry was copied successfully
function M.copy_entry(key, raw, opts)
  if not opts or not opts.enabled then
    notify_warn('local_bib is not enabled')
    return false
  end

  local target = M.resolve_target(opts)
  if not target then
    notify_warn('No local bib target found. Configure local_bib.target or local_bib.patterns')
    return false
  end

  -- Create file if needed
  if not file_exists(target) then
    if opts.create_if_missing then
      if not M.create_empty_file(target) then
        return false
      end
    else
      notify_warn(string.format('Target file %s does not exist. Set create_if_missing = true to auto-create', target))
      return false
    end
  end

  -- Check for duplicates
  if opts.duplicate_check and M.key_exists_in_file(target, key) then
    if opts.notify_on_duplicate then
      notify_info(string.format("Entry '%s' already exists in %s", key, vim.fn.fnamemodify(target, ':t')))
    end
    return false
  end

  -- Append entry
  if not M.append_entry(target, raw) then
    return false
  end

  if opts.notify_on_add then
    notify_info(string.format("Added '%s' to %s", key, vim.fn.fnamemodify(target, ':t')))
  end

  return true
end

return M
