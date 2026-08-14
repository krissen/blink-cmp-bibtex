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

--- Check if a path is absolute
--- @param path string The path to check
--- @return boolean True if the path is absolute
function M.is_absolute(path)
  return path:match('^%a:[\\/]') or path:sub(1, 1) == '/'
end

return M
