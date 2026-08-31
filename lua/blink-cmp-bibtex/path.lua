--- Path helpers shared by the scanner and the discovery hooks
--- Extracted so that discovery.lua can resolve the paths it finds without
--- depending on scan.lua, which depends on it.
--- @module 'blink-cmp-bibtex.path'

local M = {}

--- Platform-specific path separator
--- @type string
local path_separator = package.config:sub(1, 1)

--- Join two path components
--- @param base string|nil Base path
--- @param relative string|nil Relative path
--- @return string|nil The joined path
function M.joinpath(base, relative)
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
--- @param path string|nil The path to normalize
--- @return string|nil The normalized path or nil if invalid
function M.normalize(path)
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

--- Find the project root directory based on markers
--- @param bufname string Buffer file name
--- @param markers table List of root marker files/directories
--- @return string The root directory path
function M.find_root(bufname, markers)
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

--- Check if a path is absolute
--- Recognizes slash paths, Windows drive-letter paths and UNC network paths.
--- @param path string The path to check
--- @return boolean True if the path is absolute
function M.is_absolute(path)
  return path:match('^%a:[\\/]') ~= nil or path:match('^[/\\][/\\]') ~= nil or path:sub(1, 1) == '/'
end

return M
